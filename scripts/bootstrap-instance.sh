#! /bin/env bash

set -uo pipefail

function __phd_bootstrap_instance() {
    local namespace="$1"

    __phd_check_command_installed "kubectl"
    __phd_check_env_var_set "OPENCRAFT_MANIFESTS_URL"

    __log_info "Bootstrapping \"$namespace\" instance"

    __log_success "Instance \"$namespace\" bootstrapped successfully"
}
