#!/usr/bin/env bash
#
# Instance RBAC configuration script. This script provides functions to set up
# RBAC permissions for OpenEdX instances.

set -uo pipefail

function __phd_set_instance_rbac() {
    local namespace="$1"

    __phd_check_command_installed "kubectl" || return 1
    __phd_check_env_var_set "OPENCRAFT_MANIFESTS_URL" || return 1

    __phd_run_command "configure instance RBAC for namespace '$namespace'" \
        __phd_kubectl_apply_from_url "$namespace" "${OPENCRAFT_MANIFESTS_URL}/openedx-instance-rbac.yml" || return 1

    __log_success "Instance RBAC configured successfully for namespace '$namespace'"
}