#!/usr/bin/env bash
#
# Instance bootstrapping script. This script provides functions to initialize
# a new OpenEdX instance.

set -uo pipefail

function __phd_set_instance_rbac() {
    local namespace="$1"

    if [ -z "$namespace" ]; then
        __log_error "Namespace is required"
        echo "Usage: __phd_set_instance_rbac <namespace>"
        return 1
    fi

    __phd_check_command_installed "kubectl" || return 1
    __phd_check_env_var_set "OPENCRAFT_MANIFESTS_URL" || return 1

    __phd_run_command "configure instance RBAC for namespace '$namespace'" \
        __phd_kubectl_apply_from_url "$namespace" "${OPENCRAFT_MANIFESTS_URL}/openedx-instance-rbac.yml" || return 1

    __log_success "Instance RBAC configured successfully for namespace '$namespace'"
}

function __phd_create_workflows() {
    local instance_name="$1"

    if [ -z "$instance_name" ]; then
        __log_error "Instance name is required"
        echo "Usage: __phd_create_workflows <instance_name>"
        return 1
    fi

    __phd_check_command_installed "kubectl" || return 1

    __log_info "Creating parameterized workflows for instance '$instance_name'"

    # Note: PHD_INSTANCE_* variables are set by __phd_parse_instance_config
    # which should be called before this function

    # Apply the parameterized workflows using manifest files
    __phd_run_command "apply MySQL provision workflow" \
        __phd_kubectl_apply_from_url "$instance_name" "${OPENCRAFT_MANIFESTS_URL}/phd-mysql-provision-workflow.yml" || return 1

    __phd_run_command "apply MongoDB provision workflow" \
        __phd_kubectl_apply_from_url "$instance_name" "${OPENCRAFT_MANIFESTS_URL}/phd-mongodb-provision-workflow.yml" || return 1

    __phd_run_command "apply storage provision workflow" \
        __phd_kubectl_apply_from_url "$instance_name" "${OPENCRAFT_MANIFESTS_URL}/phd-storage-provision-workflow.yml" || return 1

    # Wait for workflows to complete
    __log_info "Waiting for provision workflows to complete..."
    local auto_cleanup="true"

    # Check MySQL workflow
    if ! kubectl wait --for=condition=Completed workflow/mysql-provision-$instance_name -n $instance_name --timeout=300s 2>/dev/null; then
        auto_cleanup="false"
        __log_warning "MySQL provision workflow timed out"
    else
        # Check if workflow actually succeeded (not just completed)
        local mysql_status=$(kubectl get workflow mysql-provision-$instance_name -n $instance_name -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$mysql_status" != "Succeeded" ]; then
            auto_cleanup="false"
            __log_warning "MySQL provision workflow failed with status: $mysql_status"
        else
            __log_debug "MySQL provision workflow succeeded"
        fi
    fi

    # Check MongoDB workflow
    if ! kubectl wait --for=condition=Completed workflow/mongodb-provision-$instance_name -n $instance_name --timeout=300s 2>/dev/null; then
        auto_cleanup="false"
        __log_warning "MongoDB provision workflow timed out"
    else
        # Check if workflow actually succeeded (not just completed)
        local mongodb_status=$(kubectl get workflow mongodb-provision-$instance_name -n $instance_name -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$mongodb_status" != "Succeeded" ]; then
            auto_cleanup="false"
            __log_warning "MongoDB provision workflow failed with status: $mongodb_status"
        else
            __log_debug "MongoDB provision workflow succeeded"
        fi
    fi

    # Check Storage workflow
    if ! kubectl wait --for=condition=Completed workflow/storage-provision-$instance_name -n $instance_name --timeout=300s 2>/dev/null; then
        auto_cleanup="false"
        __log_warning "Storage provision workflow timed out"
    else
        # Check if workflow actually succeeded (not just completed)
        local storage_status=$(kubectl get workflow storage-provision-$instance_name -n $instance_name -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$storage_status" != "Succeeded" ]; then
            auto_cleanup="false"
            __log_warning "Storage provision workflow failed with status: $storage_status"
        else
            __log_debug "Storage provision workflow succeeded"
        fi
    fi

    # Get workflow status
    kubectl get workflows -n $instance_name

    __log_debug "auto_cleanup flag is set to: $auto_cleanup"

    if [ "$auto_cleanup" = "true" ]; then
        __log_warning "Cleaning up workflows to save resources..."
        kubectl delete workflow mysql-provision-$instance_name -n $instance_name 2>/dev/null
        kubectl delete workflow mongodb-provision-$instance_name -n $instance_name 2>/dev/null
        kubectl delete workflow storage-provision-$instance_name -n $instance_name 2>/dev/null

        __log_success "Workflows created and completed successfully for instance '$instance_name'"
    else
        __log_error "Workflows may have failed for instance '$instance_name'"
        return 1
    fi
}

function __phd_create_argocd_application() {
    local instance_name="$1"

    if [ -z "$instance_name" ]; then
        __log_error "Instance name is required"
        echo "Usage: __phd_create_argocd_application <instance_name>"
        return 1
    fi

    __phd_check_command_installed "kubectl" || return 1

    __log_info "Creating ArgoCD Application for instance '$instance_name'"

    # Check if the application.yml file exists
    local application_file="${INSTANCES_DIR}/${instance_name}/application.yml"
    if [ ! -f "$application_file" ]; then
        __log_error "ArgoCD Application file not found: $application_file"
        return 1
    fi

    # Apply the ArgoCD Application from the instance's application.yml file
    __phd_run_command "create ArgoCD Application for instance '$instance_name'" \
        kubectl apply -f "$application_file" || return 1

    __log_success "ArgoCD Application created successfully for instance '$instance_name'"
}

function __phd_bootstrap_instance() {
    local instance_name="$1"
    local instance_template_repository="${2:-https://github.com/open-craft/phd-cluster-template.git}"
    local platform_name="${3:-My Open edX Instance}"
    local edx_platform_repository="${4:-https://github.com/openedx/edx-platform.git}"
    local edx_platform_version="${5:-release/teak}"
    local tutor_version="${6:-v20.0.1}"

    if [ -z "$instance_name" ]; then
        __log_error "Instance name is required"
        echo "Usage: __phd_bootstrap_instance <instance_name> [template_repo] [platform_name] [edx_repo] [edx_version] [tutor_version]"
        return 1
    fi

    # Verify prerequisites
    __phd_check_command_installed "kubectl" || return 1
    __phd_check_command_installed "cookiecutter" || return 1

    __log_info "Bootstrapping instance '$instance_name' from template '$instance_template_repository'"

    # Clean up any existing cached template to avoid interactive prompts
    local template_name=$(basename "$instance_template_repository" .git)
    local cached_template_path="$HOME/.cookiecutters/$template_name"
    if [ -d "$cached_template_path" ]; then
        __log_info "Removing cached template to ensure fresh download"
        rm -rf "$cached_template_path"
    fi

    # Create a cookiecutter config file to override defaults
    local config_file="/tmp/cookiecutter-config-${instance_name}.json"
    cat >"$config_file" <<EOF
{
    "instance_name": "$instance_name",
    "platform_repository": "$edx_platform_repository",
    "platform_version": "$edx_platform_version",
    "tutor_version": "$tutor_version"
}
EOF

    __log_info "Created cookiecutter config: $config_file"

    pushd "$INSTANCES_DIR" >/dev/null || return 1

    # Call cookiecutter with config file
    __phd_run_command "generate instance configuration" \
        cookiecutter "$instance_template_repository" \
        --directory instance-template \
        --config-file "$config_file" \
        --no-input || {
        popd >/dev/null
        return 1
    }

    # Clean up config file
    rm -f "$config_file"

    __log_info "Creating namespace '$instance_name'"
    kubectl create namespace "$instance_name" || return 1

    __log_success "Instance \"$instance_name\" bootstrapped successfully"
}
