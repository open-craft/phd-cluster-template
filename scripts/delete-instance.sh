#!/usr/bin/env bash
#
# Instance deletion script. This script provides functions to delete
# OpenEdX instances and clean up all associated resources.

set -uo pipefail

function __phd_delete_workflows() {
    local instance_name="$1"

    if [ -z "$instance_name" ]; then
        __log_error "Instance name is required"
        echo "Usage: __phd_delete_workflows <instance_name>"
        return 1
    fi

    __phd_check_command_installed "kubectl" || return 1

    __log_info "Deleting workflows for instance '$instance_name'"

    # Delete MySQL provision workflow
    kubectl delete workflow "mysql-provision-${instance_name}" -n "$instance_name" 2>/dev/null || echo "MySQL provision workflow not found"

    # Delete MongoDB provision workflow
    kubectl delete workflow "mongodb-provision-${instance_name}" -n "$instance_name" 2>/dev/null || echo "MongoDB provision workflow not found"

    # Delete storage provision workflow
    kubectl delete workflow "storage-provision-${instance_name}" -n "$instance_name" 2>/dev/null || echo "Storage provision workflow not found"

    __log_success "Workflows deleted for instance '$instance_name'"
}

function __phd_create_deprovision_workflows() {
    local instance_name="$1"

    if [ -z "$instance_name" ]; then
        __log_error "Instance name is required"
        echo "Usage: __phd_create_deprovision_workflows <instance_name>"
        return 1
    fi

    __phd_check_command_installed "kubectl" || return 1

    __log_info "Creating deprovision workflows for instance '$instance_name'"

    # Note: PHD_INSTANCE_* variables are set by __phd_parse_instance_config
    # which should be called before this function

    # Apply the deprovision workflows using manifest files (ignore namespace not found errors)
    __phd_run_command "apply MySQL deprovision workflow" \
        __phd_kubectl_apply_from_url "$instance_name" "${OPENCRAFT_MANIFESTS_URL}/phd-mysql-deprovision-workflow.yml" || {
        __log_warning "Failed to apply MySQL deprovision workflow (this may be expected if resources don't exist)"
    }

    __phd_run_command "apply MongoDB deprovision workflow" \
        __phd_kubectl_apply_from_url "$instance_name" "${OPENCRAFT_MANIFESTS_URL}/phd-mongodb-deprovision-workflow.yml" || {
        __log_warning "Failed to apply MongoDB deprovision workflow (this may be expected if resources don't exist)"
    }

    __phd_run_command "apply storage deprovision workflow" \
        __phd_kubectl_apply_from_url "$instance_name" "${OPENCRAFT_MANIFESTS_URL}/phd-storage-deprovision-workflow.yml" || {
        __log_warning "Failed to apply storage deprovision workflow (this may be expected if resources don't exist)"
    }

    # Wait for deprovision workflows to complete
    __log_info "Waiting for deprovision workflows to complete..."
    local auto_cleanup="true"

    # Check MySQL workflow
    if ! kubectl wait --for=condition=Completed workflow/mysql-deprovision-$instance_name -n $instance_name --timeout=300s 2>/dev/null; then
        auto_cleanup="false"
        __log_warning "MySQL deprovision workflow timed out"
    else
        # Check if workflow actually succeeded (not just completed)
        local mysql_status=$(kubectl get workflow mysql-deprovision-$instance_name -n $instance_name -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$mysql_status" != "Succeeded" ]; then
            auto_cleanup="false"
            __log_warning "MySQL deprovision workflow failed with status: $mysql_status"
        else
            __log_debug "MySQL deprovision workflow succeeded"
        fi
    fi

    # Check MongoDB workflow
    if ! kubectl wait --for=condition=Completed workflow/mongodb-deprovision-$instance_name -n $instance_name --timeout=300s 2>/dev/null; then
        auto_cleanup="false"
        __log_warning "MongoDB deprovision workflow timed out"
    else
        # Check if workflow actually succeeded (not just completed)
        local mongodb_status=$(kubectl get workflow mongodb-deprovision-$instance_name -n $instance_name -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$mongodb_status" != "Succeeded" ]; then
            auto_cleanup="false"
            __log_warning "MongoDB deprovision workflow failed with status: $mongodb_status"
        else
            __log_debug "MongoDB deprovision workflow succeeded"
        fi
    fi

    # Check Storage workflow
    if ! kubectl wait --for=condition=Completed workflow/storage-deprovision-$instance_name -n $instance_name --timeout=300s 2>/dev/null; then
        auto_cleanup="false"
        __log_warning "Storage deprovision workflow timed out"
    else
        # Check if workflow actually succeeded (not just completed)
        local storage_status=$(kubectl get workflow storage-deprovision-$instance_name -n $instance_name -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$storage_status" != "Succeeded" ]; then
            auto_cleanup="false"
            __log_warning "Storage deprovision workflow failed with status: $storage_status"
        else
            __log_debug "Storage deprovision workflow succeeded"
        fi
    fi

    # Get workflow status
    kubectl get workflows -n $instance_name

    __log_debug "auto_cleanup flag is set to: $auto_cleanup"

    if [ "$auto_cleanup" = "true" ]; then
        __log_warning "Cleaning up workflows to save resources..."
        kubectl delete workflow mysql-deprovision-$instance_name -n $instance_name 2>/dev/null
        kubectl delete workflow mongodb-deprovision-$instance_name -n $instance_name 2>/dev/null
        kubectl delete workflow storage-deprovision-$instance_name -n $instance_name 2>/dev/null
    fi

    __log_success "Deprovision workflows created and completed successfully for instance '$instance_name'"
}

function __phd_delete_argocd_application() {
    local instance_name="$1"

    if [ -z "$instance_name" ]; then
        __log_error "Instance name is required"
        echo "Usage: __phd_delete_argocd_application <instance_name>"
        return 1
    fi

    __log_info "Deleting ArgoCD Application for instance '$instance_name'"
    kubectl delete application "${instance_name}.kubernetes.default.svc" -n argocd 2>/dev/null || echo "ArgoCD Application not found"
}

function __phd_cleanup_rbac() {
    local instance_name="$1"

    if [ -z "$instance_name" ]; then
        __log_error "Instance name is required"
        echo "Usage: __phd_cleanup_rbac <instance_name>"
        return 1
    fi

    __log_info "Cleaning up RBAC resources for instance '$instance_name'"
    kubectl delete clusterrole "${instance_name}-workflows" 2>/dev/null || true
    kubectl delete clusterrolebinding "${instance_name}-binding" 2>/dev/null || true
}

function __phd_delete_instance() {
    local instance_name="$1"

    if [ -z "$instance_name" ]; then
        __log_error "Instance name is required"
        echo "Usage: __phd_delete_instance <instance_name>"
        return 1
    fi

    __phd_check_command_installed "kubectl" || return 1

    __log_info "Deleting instance '$instance_name'"

    if ! kubectl get namespace "$instance_name" >/dev/null 2>&1; then
        __log_warning "Namespace '$instance_name' does not exist"
        return 0
    fi

    __log_info "Deleting namespace '$instance_name' and all its resources..."
    kubectl delete namespace "$instance_name" --timeout=300s || {
        __log_warning "Failed to delete namespace (some resources may still be terminating)"
        return 1
    }

    if kubectl get namespace "$instance_name" >/dev/null 2>&1; then
        __log_warning "Namespace '$instance_name' still exists"
        kubectl get namespace "$instance_name"
        return 1
    else
        __log_success "Namespace '$instance_name' successfully deleted"
    fi

    rm -rf "$INSTANCES_DIR/$instance_name"

    __log_success "Instance '$instance_name' deleted successfully"
}
