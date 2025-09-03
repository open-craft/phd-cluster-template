#!/usr/bin/env bash
#
# ArgoCD installation script. This script provides functions to install and
# configure ArgoCD in a Kubernetes cluster.

set -uo pipefail

function __phd_install_argocd() {
    # Verify prerequisites
    __phd_check_command_installed "kubectl" || return 1
    __phd_check_env_var_set "OPENCRAFT_MANIFESTS_URL" || return 1
    __phd_check_env_var_set "ARGOCD_INSTALL_URL" || return 1
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

    local mtime
    mtime=$(__phd_get_password_mtime) || return 1

    export PHD_ARGO_ADMIN_PASSWORD_BCRYPT="$bcrypt"
    export PHD_ARGOCD_ADMIN_PASSWORD_MTIME="$mtime"

    # Create namespace and install ArgoCD
    __phd_run_command "create ArgoCD namespace" \
        kubectl create namespace argocd || return 1

    __phd_run_command "install ArgoCD core components" \
        __phd_kubectl_apply_from_url argocd "${ARGOCD_INSTALL_URL}" || return 1

    # Ensure base argocd-cm exists (local auth)
    __phd_run_command "ensure base ArgoCD configmap" \
        __phd_kubectl_apply_from_url argocd "${OPENCRAFT_MANIFESTS_URL}/argocd-base-config.yml" || return 1

    # Configure ingress
    __phd_run_command "configure ArgoCD ingress" \
        __phd_kubectl_apply_from_url argocd "${OPENCRAFT_MANIFESTS_URL}/argocd-ingress.yml" || return 1

    # Configure ArgoCD admin password
    __phd_run_command "configure ArgoCD admin password" \
        __phd_kubectl_apply_from_url argocd "${OPENCRAFT_MANIFESTS_URL}/argocd-admin-password.yml" || return 1

    if [ "$generated_password" = "true" ]; then
        __log_warning "Generated Argo admin password (store securely): $plaintext"
    fi

    __log_success "ArgoCD installed successfully"
}
