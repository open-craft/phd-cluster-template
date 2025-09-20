#! /bin/env bash

set -uo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"
ARGOCD_INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

function __phd_install_argocd() {
    __phd_check_command_installed "kubectl"
    __phd_check_env_var_set "OPENCRAFT_MANIFESTS_URL"

    __log_info "Installing ArgoCD"
    kubectl create namespace argocd
    kubectl apply -n argocd -f "${ARGOCD_INSTALL_URL}"

    __log_info "Applying ArgoCD ingress"
    kubectl apply -n argocd -f "${OPENCRAFT_MANIFESTS_URL}/argocd-ingress.yml"

    __log_success "ArgoCD installed successfully"
}
