#! /bin/env bash

set -uo pipefail

ARGO_WORKFLOWS_VERSION="${ARGO_WORKFLOWS_VERSION:-stable}"
ARGO_WORKFLOWS_INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-workflows/${ARGO_WORKFLOWS_VERSION}/manifests/install.yaml"

function __phd_install_argo_workflows() {
    __phd_check_command_installed "kubectl"
    __phd_check_env_var_set "OPENCRAFT_MANIFESTS_URL"

    __log_info "Installing Argo Workflows"
    kubectl create namespace argo
    kubectl apply -n argo -f "${ARGO_WORKFLOWS_INSTALL_URL}"

    __log_info "Applying Argo Workflows ingress"
    kubectl apply -n argo -f "${OPENCRAFT_MANIFESTS_URL}/argo-workflows-ingress.yml"

    __log_success "Argo Workflows installed successfully"
}

function __phd_install_argo_workflows_templates() {
    __phd_check_command_installed "kubectl"

    __log_info "Installing Argo Workflows templates"
    kubectl apply -n argo -f "${OPENCRAFT_MANIFESTS_URL}/phd-mysql-provision-template.yml"
    kubectl apply -n argo -f "${OPENCRAFT_MANIFESTS_URL}/phd-mongodb-provision-template.yml"
    kubectl apply -n argo -f "${OPENCRAFT_MANIFESTS_URL}/phd-storage-provision-template.yml"

    __log_success "Argo Workflows templates installed successfully"
}
