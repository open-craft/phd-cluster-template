#! /bin/env bash

set -uo pipefail

function __phd_set_instance_rbac() {
    local namespace="$1"

    __phd_check_command_installed "kubectl"
    __phd_check_env_var_set "OPENCRAFT_MANIFESTS_URL"

    __log_info "Setting instance RBAC"
    kubectl apply -n "$namespace" -f "${OPENCRAFT_MANIFESTS_URL}/openedx-instance-rbac.yml"

    __log_success "Instance RBAC set successfully"
}
