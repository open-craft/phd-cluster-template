#!/usr/bin/env bash

set -uo pipefail

# Remote/local scripts
USE_LOCAL_SCRIPTS="${USE_LOCAL_SCRIPTS:-false}"
REMOTE_SCRIPTS_VERSION="${REMOTE_SCRIPTS_VERSION:-main}"
REMOTE_SCRIPTS_DIR_URL="${REMOTE_SCRIPTS_DIR_URL:-https://raw.githubusercontent.com/opencraft/phd-cluster-template/${REMOTE_SCRIPTS_VERSION}/scripts}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$(dirname "${BASH_SOURCE[0]:-$0}")}"

# OpenCraft manifests
OPENCRAFT_MANIFESTS_VERSION="${OPENCRAFT_MANIFESTS_VERSION:-main}"
# shellcheck disable=SC2034
OPENCRAFT_MANIFESTS_URL="https://raw.githubusercontent.com/opencraft/phd-cluster-template/${OPENCRAFT_MANIFESTS_VERSION}/manifests"

################################################################################
# Logging functions
################################################################################

function __log_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

function __log_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
}

function __log_warning() {
    echo -e "\033[33m[WARNING]\033[0m $1"
}

function __log_success() {
    echo -e "\033[32m[SUCCESS]\033[0m $1"
}

################################################################################
# Utility functions
################################################################################

function __phd_fetch_source_script() {
local script_url="$1"
    local script_path="$2"

    if $USE_LOCAL_SCRIPTS; then
        __log_info "Using local scripts from $script_url"
        # shellcheck disable=SC1090
        source "$script_url/$script_path"
        return 0
    fi

    __log_info "Fetching and sourcing remote script $script_path from $script_url"
    # shellcheck disable=SC1090
    source <(curl -sSL "$script_url/$script_path") || {
        __log_error "Failed to source remote script $script_path from $script_url"
        return 1
    }
    __log_success "Sourced remote script $script_path from $script_url"
}

function __phd_check_env_var_set() {
    local variable_name="$1"
    if [ -z "${!variable_name}" ]; then
        __log_error "Environment variable $variable_name is not set"
        exit 1
    fi
}

function __phd_check_command_installed() {
    if ! command -v "$1" &> /dev/null; then
        __log_error "$1 command is not installed"
        exit 1
    fi
    __log_success "$1 command is installed"
}

function __phd_ask_for_password() {
    local password
    local password_confirm

    printf "Enter password: " >&2
    read -rs password
    echo >&2
    printf "Confirm password: " >&2
    read -rs password_confirm
    echo >&2

    if [ "$password" != "$password_confirm" ]; then
        __log_error "Passwords do not match"
        return 1
    fi

    echo "$password"
}

function __phd_generate_from_template() {
    local template_file="$1"
    local output_file="$2"
    local config_vars_file="$3"

    __log_info "Generating file from template: $template_file"

    set -a
    # shellcheck disable=SC1090
    source "$config_vars_file"
    set +a

    envsubst < "$template_file" > "$output_file"

    __log_success "Generated file: $output_file"
}


################################################################################
# PHD commands
################################################################################

function phd_install_argocd() {
    __phd_fetch_source_script "${SCRIPTS_DIR}" "install-argocd.sh"
    __phd_install_argocd
}

function phd_install_argo_workflows() {
    __phd_fetch_source_script "${SCRIPTS_DIR}" "install-argo-workflows.sh"
    __phd_install_argo_workflows
    __phd_install_argo_workflows_templates
}

function phd_create_argo_user() {
    local username="$1"
    local password="${2:-$(__phd_ask_for_password)}"
    local role="${3:-developer}"

    __phd_fetch_source_script "${SCRIPTS_DIR}" "create-user.sh"
    __phd_create_argo_user "$username" "$password" "$role"
}

function phd_set_instance_rbac() {
    local namespace="$1"

    __phd_fetch_source_script "${SCRIPTS_DIR}" "set-instance-rbac.sh"
    __phd_set_instance_rbac "$namespace"
}

function phd_install_all() {
    phd_install_argocd
    phd_install_argo_workflows
}

function phd_generate_config() {
    local template_file="$1"
    local output_file="$2"
    local config_file="${3:-}"

    __phd_fetch_source_script "${SCRIPTS_DIR}" "generate-config.sh"
    __phd_generate_config "$template_file" "$output_file" "$config_file"
}

function phd_generate_config_interactive() {
    local template_file="$1"
    local output_file="$2"
    local config_file="${3:-}"

    __phd_fetch_source_script "${SCRIPTS_DIR}" "generate-config.sh"
    __phd_generate_config_interactive "$template_file" "$output_file" "$config_file"
}

function phd_validate_config() {
    local config_file="$1"

    __phd_fetch_source_script "${SCRIPTS_DIR}" "generate-config.sh"
    __phd_validate_config "$config_file"
}

__log_success "PHD commands loaded successfully"
