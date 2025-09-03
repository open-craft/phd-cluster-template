#!/usr/bin/env bash
#
# Argo Workflows installation script. This script provides functions to install
# and configure Argo Workflows and its templates in a Kubernetes cluster.

set -uo pipefail

function __phd_install_argo_workflows() {
    # Verify prerequisites
    __phd_check_command_installed "kubectl" || return 1
    __phd_check_env_var_set "OPENCRAFT_MANIFESTS_URL" || return 1
    __phd_check_env_var_set "ARGO_WORKFLOWS_INSTALL_URL" || return 1
    __phd_check_env_var_set "PHD_CLUSTER_DOMAIN" || return 1
    __phd_source_script "${SCRIPTS_DIR}" "set-admin-password.sh" || return 1

    local had_plaintext_env="${PHD_ARGO_ADMIN_PASSWORD:-}"
    local had_bcrypt_env="${PHD_ARGO_ADMIN_PASSWORD_BCRYPT:-}"
    local generated_password="false"
    if [ -z "$had_plaintext_env" ] && [ -z "$had_bcrypt_env" ]; then
        generated_password="true"
    fi

    local plaintext
    plaintext=$(__phd_resolve_plaintext_password) || return 1

    local bcrypt
    bcrypt=$(__phd_bcrypt_password "$plaintext") || return 1

    export PHD_ARGO_ADMIN_PASSWORD_BCRYPT="$bcrypt"

    # Create namespace and install Argo Workflows
    __phd_run_command "create Argo Workflows namespace" \
        kubectl create namespace argo || return 1

    __phd_run_command "install Argo Workflows core components" \
        __phd_kubectl_apply_from_url argo "${ARGO_WORKFLOWS_INSTALL_URL}" || return 1

    # Configure ingress
    __phd_run_command "configure Argo Workflows ingress" \
        __phd_kubectl_apply_from_url argo "${OPENCRAFT_MANIFESTS_URL}/argo-workflows-ingress.yml" || return 1

    # Configure Argo Server authentication
    __phd_run_command "configure Argo Server admin auth" \
        __phd_kubectl_apply_from_url argo "${OPENCRAFT_MANIFESTS_URL}/argo-server-auth.yml" || return 1

    # Create workflow-executor token in the argo namespace
    __log_info "Creating workflow-executor token in argo namespace"
    cat <<EOF | kubectl apply -f - || return 1
apiVersion: v1
kind: Secret
metadata:
  name: workflow-executor-token
  namespace: argo
  annotations:
    kubernetes.io/service-account.name: workflow-executor
type: kubernetes.io/service-account-token
EOF

    __log_success "Argo Workflows installed successfully"
}

function __phd_install_argo_workflows_templates() {
    # Verify prerequisites
    __phd_check_command_installed "kubectl" || return 1
    __phd_check_env_var_set "OPENCRAFT_MANIFESTS_URL" || return 1

    # Install workflow templates
    __phd_run_command "install MySQL provisioning template" \
        __phd_kubectl_apply_from_url argo "${OPENCRAFT_MANIFESTS_URL}/phd-mysql-provision-template.yml" || return 1

    __phd_run_command "install MongoDB provisioning template" \
        __phd_kubectl_apply_from_url argo "${OPENCRAFT_MANIFESTS_URL}/phd-mongodb-provision-template.yml" || return 1

    __phd_run_command "install storage provisioning template" \
        __phd_kubectl_apply_from_url argo "${OPENCRAFT_MANIFESTS_URL}/phd-storage-provision-template.yml" || return 1

    __phd_run_command "install MySQL deprovision template" \
        __phd_kubectl_apply_from_url argo "${OPENCRAFT_MANIFESTS_URL}/phd-mysql-deprovision-template.yml" || return 1

    __phd_run_command "install MongoDB deprovision template" \
        __phd_kubectl_apply_from_url argo "${OPENCRAFT_MANIFESTS_URL}/phd-mongodb-deprovision-template.yml" || return 1

    __phd_run_command "install storage deprovision template" \
        __phd_kubectl_apply_from_url argo "${OPENCRAFT_MANIFESTS_URL}/phd-storage-deprovision-template.yml" || return 1

    __log_success "Argo Workflows templates installed successfully"
}
