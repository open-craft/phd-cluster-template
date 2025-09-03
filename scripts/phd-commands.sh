#!/usr/bin/env bash
#
# Main entry point for PHD commands. This script provides the public interface
# for PHD functionality and includes all necessary utilities.

set -uo pipefail

################################################################################
# Constants and configuration
################################################################################

# Default timeouts
readonly PHD_CURL_TIMEOUT="${PHD_CURL_TIMEOUT:-30}"
readonly PHD_CURL_CONNECT_TIMEOUT="${PHD_CURL_CONNECT_TIMEOUT:-10}"
readonly PHD_CURL_MAX_RETRIES="${PHD_CURL_MAX_RETRIES:-3}"
readonly PHD_CURL_RETRY_DELAY="${PHD_CURL_RETRY_DELAY:-5}"

# Remote/local scripts configuration
readonly USE_LOCAL_SCRIPTS="${USE_LOCAL_SCRIPTS:-false}"
readonly REMOTE_SCRIPTS_VERSION="${REMOTE_SCRIPTS_VERSION:-main}"
readonly REMOTE_SCRIPTS_DIR_URL="${REMOTE_SCRIPTS_DIR_URL:-https://raw.githubusercontent.com/open-craft/phd-cluster-template/${REMOTE_SCRIPTS_VERSION}/scripts}"

# Determine scripts directory
if [ -n "${SCRIPTS_DIR:-}" ]; then
    # Convert to absolute path if SCRIPTS_DIR is provided
    SCRIPTS_DIR="$(realpath "${SCRIPTS_DIR}" 2>/dev/null || readlink -f "${SCRIPTS_DIR}" 2>/dev/null || echo "${SCRIPTS_DIR}")"
else
    # Use remote URL if SCRIPTS_DIR is not provided
    SCRIPTS_DIR="$REMOTE_SCRIPTS_DIR_URL"
fi
readonly SCRIPTS_DIR

# OpenCraft manifests configuration
readonly OPENCRAFT_MANIFESTS_VERSION="${OPENCRAFT_MANIFESTS_VERSION:-main}"
readonly OPENCRAFT_MANIFESTS_URL="https://raw.githubusercontent.com/open-craft/phd-cluster-template/${OPENCRAFT_MANIFESTS_VERSION}/manifests"

# Argo versions
readonly ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"
readonly ARGO_WORKFLOWS_VERSION="${ARGO_WORKFLOWS_VERSION:-stable}"

# URLs for Argo installations
readonly ARGOCD_INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
readonly ARGO_WORKFLOWS_INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-workflows/${ARGO_WORKFLOWS_VERSION}/manifests/install.yaml"

################################################################################
# Logging functions
################################################################################

function __log_debug() {
    if [ "${PHD_DEBUG:-}" != "true" ]; then
        return 0
    fi

    echo -e "\033[30m[DEBUG]\033[0m   $1" >&2
}

function __log_info() {
    echo -e "\033[34m[INFO]\033[0m    $1" >&2
}

function __log_error() {
    echo -e "\033[31m[ERROR]\033[0m   $1" >&2
}

function __log_warning() {
    echo -e "\033[33m[WARNING]\033[0m $1" >&2
}

function __log_success() {
    echo -e "\033[32m[SUCCESS]\033[0m $1" >&2
}

################################################################################
# Core utility functions
################################################################################

function __phd_run_command() {
    local cmd_description="$1"
    shift
    local cmd=("$@")

    __log_info "$cmd_description"
    if ! "${cmd[@]}"; then
        __log_error "Failed to $cmd_description"
        return 1
    fi
}

function __phd_check_env_var_set() {
    local variable_name="$1"
    local variable_value
    eval "variable_value=\$${variable_name}"
    if [ -z "$variable_value" ]; then
        __log_error "Environment variable $variable_name is not set"
        return 1
    fi
}

function __phd_check_command_installed() {
    if ! command -v "$1" &> /dev/null; then
        __log_error "$1 command is not installed"
        return 1
    fi
    __log_debug "$1 command is installed"
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

function __phd_load_context_as_env_vars() {
    __phd_check_command_installed "jq" || return 1

    local context_json_file="$1"
    cat "$context_json_file" | jq -r 'to_entries[] | "export PHD_\(.key | ascii_upcase)=\(.value)"' | source /dev/stdin

    __log_debug "Context loaded as environment variables"
    export | grep -e "^PHD_"
}

# Render {{ VAR }} placeholders from environment variables, in-memory
function __phd_render_stream() {
    perl -pe 's/{{\s*([A-Za-z_][A-Za-z0-9_]*)\s*}}/exists $ENV{$1} ? $ENV{$1} : $&/ge'
}

################################################################################
# Script loading functions
################################################################################

# Build curl with common flags and optional GitHub token
function __phd_curl_to_stdout() {
    local url="$1"
    local -a args=(
        --fail
        --silent
        --show-error
        --location
        --connect-timeout "$PHD_CURL_CONNECT_TIMEOUT"
        --max-time "$PHD_CURL_TIMEOUT"
    )
    curl "${args[@]}" "$url"
}

# Apply Kubernetes manifests from a URL, supporting private repos via token
function __phd_kubectl_apply_from_url() {
    local namespace="$1"
    local url="$2"
    __log_info "apply manifests from ${url}"
    if ! __phd_curl_to_stdout "$url" | __phd_render_stream | kubectl apply -n "$namespace" -f -; then
        __log_error "kubectl apply failed for ${url}"
        return 1
    fi
}

function __phd_source_script() {
    local script_url="$1"
    local script_path="$2"
    local retries=0

    if $USE_LOCAL_SCRIPTS; then
        __log_info "Using local scripts from $script_url"
        # shellcheck disable=SC1090
        source "$script_url/$script_path" || {
            __log_error "Failed to source local script $script_path"
            return 1
        }
        return 0
    fi

    __log_info "Fetching remote script $script_path from $script_url"
    
    while [ $retries -lt "$PHD_CURL_MAX_RETRIES" ]; do
        # shellcheck disable=SC1090
        if source <(__phd_curl_to_stdout "$script_url/$script_path"); then
            __log_success "Sourced script $script_path successfully"
            return 0
        fi
        
        retries=$((retries + 1))
        if [ $retries -lt "$PHD_CURL_MAX_RETRIES" ]; then
            __log_warning "Failed to fetch script, retrying in $PHD_CURL_RETRY_DELAY seconds (attempt $retries of $PHD_CURL_MAX_RETRIES)"
            sleep "$PHD_CURL_RETRY_DELAY"
        fi
    done

    __log_error "Failed to fetch script after $PHD_CURL_MAX_RETRIES attempts"
    return 1
}

################################################################################
# PHD commands
################################################################################

function phd_install_argocd() {
    __phd_source_script "${SCRIPTS_DIR}" "install-argocd.sh" || return 1
    __phd_install_argocd || return 1
}

function phd_install_argo_workflows() {
    __phd_source_script "${SCRIPTS_DIR}" "install-argo-workflows.sh" || return 1
    __phd_install_argo_workflows || return 1
    __phd_install_argo_workflows_templates || return 1
}

function phd_install_all() {
    phd_install_argocd || return 1
    phd_install_argo_workflows || return 1
}

function phd_create_argo_user() {
    local username="$1"
    local role="${2:-}"
    local password="${3:-}"

    __phd_source_script "${SCRIPTS_DIR}" "create-user.sh" || return 1
    __phd_create_argo_user "$username" "$role" "$password" || return 1
}

function phd_delete_argo_user() {
    local username="$1"

    __phd_source_script "${SCRIPTS_DIR}" "delete-user.sh" || return 1
    __phd_delete_argo_user "$username" || return 1
}

# TODO: this should be part of an instance bootstrap command, not a standalone command
# function phd_set_instance_rbac() {
#     local namespace="$1"
# 
#     __phd_source_script "${SCRIPTS_DIR}" "set-instance-rbac.sh" || return 1
#     __phd_set_instance_rbac "$namespace" || return 1
# }

function phd_generate_config() {
    local template_file="$1"
    local output_file="$2"
    local config_file="${3:-}"

    __phd_source_script "${SCRIPTS_DIR}" "render-template.sh" || return 1
    __phd_generate_config "$template_file" "$output_file" "$config_file" || return 1
}

function phd_generate_config_interactive() {
    local template_file="$1"
    local output_file="$2"
    local config_file="${3:-}"

    __phd_source_script "${SCRIPTS_DIR}" "render-template.sh" || return 1
    __phd_generate_config "$template_file" "$output_file" "$config_file" || return 1
}

function phd_validate_config() {
    local config_file="$1"

    __phd_source_script "${SCRIPTS_DIR}" "render-template.sh" || return 1
    __phd_validate_config "$config_file" || return 1
}

__log_success "PHD commands loaded successfully"
__log_info "Loading context as environment variables"
__phd_load_context_as_env_vars "${ROOT_DIR}/context.json" || return 1