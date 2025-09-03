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
    if ! command -v "$1" &>/dev/null; then
        __log_error "$1 command is not installed"
        return 1
    fi
    __log_debug "$1 command is installed"
}

function __phd_yq_eval() {
    local expression="$1"
    local file="$2"
    local yq_version

    yq_version="$(yq --version 2>/dev/null || true)"

    if [[ "$yq_version" == yq\ \(https://github.com/mikefarah/yq/* ]]; then
        yq eval -r "$expression" "$file"
    else
        yq -r "$expression" "$file"
    fi
}

function __phd_yq_get_or_default() {
    local expression="$1"
    local default_value="$2"
    local file="$3"
    local value

    value="$(__phd_yq_eval "$expression" "$file")"

    if [[ -z "$value" || "$value" == "null" ]]; then
        echo "$default_value"
    else
        echo "$value"
    fi
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

function __phd_detect_storage_provider() {
    local storage_type="${1:-spaces}"

    case "$storage_type" in
    spaces)
        echo "digitalocean"
        ;;
    s3)
        echo "aws"
        ;;
    *)
        __log_warning "Unknown storage type: $storage_type, defaulting to digitalocean"
        echo "digitalocean"
        ;;
    esac
}

function __phd_detect_mongodb_provider() {
    local mongodb_host="${1}"
    local mongodb_cluster_id="${2:-}"

    # If cluster ID is provided, assume DigitalOcean managed
    if [ -n "$mongodb_cluster_id" ]; then
        echo "digitalocean_api"
        return
    fi

    # Detect based on hostname patterns
    case "$mongodb_host" in
    *.db.ondigitalocean.com)
        # DigitalOcean managed database with direct connection
        __log_debug "Detected DigitalOcean managed MongoDB (direct connection)"
        echo "mongodb_direct"
        ;;
    *.mongodb.net)
        # MongoDB Atlas
        __log_debug "Detected MongoDB Atlas"
        echo "mongodb_direct"
        ;;
    *)
        # Self-hosted or other
        __log_debug "Using direct MongoDB connection for: $mongodb_host"
        echo "mongodb_direct"
        ;;
    esac
}

function __phd_validate_storage_config() {
    local storage_type="$1"
    local region="$2"
    local endpoint_url="$3"
    local provider

    provider="$(__phd_detect_storage_provider "$storage_type")"

    __log_debug "Detected storage provider: $provider"

    # Validate endpoint URL format based on provider
    case "$provider" in
    digitalocean)
        if [ -n "$endpoint_url" ] && [[ ! "$endpoint_url" =~ ^https://[a-z0-9-]+\.digitaloceanspaces\.com$ ]]; then
            __log_warning "Endpoint URL format may be incorrect for DigitalOcean Spaces"
            __log_warning "Expected format: https://\${region}.digitaloceanspaces.com"
        fi
        ;;
    aws)
        if [ -n "$endpoint_url" ]; then
            __log_warning "AWS S3 typically doesn't require a custom endpoint URL"
            __log_warning "Consider removing STORAGE_ENDPOINT_URL or ensure this is intentional (e.g., for S3-compatible services)"
        fi
        ;;
    esac

    # Validate credentials are set
    if [ "${PHD_INSTANCE_STORAGE_ACCESS_KEY_ID:-your_access_key}" = "your_access_key" ]; then
        __log_warning "Storage access key is not configured. Set PHD_STORAGE_ACCESS_KEY_ID environment variable."
    fi

    if [ "${PHD_INSTANCE_STORAGE_SECRET_ACCESS_KEY:-your_secret_key}" = "your_secret_key" ]; then
        __log_warning "Storage secret key is not configured. Set PHD_STORAGE_SECRET_ACCESS_KEY environment variable."
    fi
}

function __phd_parse_instance_config() {
    local instance_name="$1"
    local config_file="${INSTANCES_DIR}/${instance_name}/config.yml"

    if [ -z "$instance_name" ] || [ ! -f "$config_file" ]; then
        __log_error "Instance name or config file not found"
        echo "Usage: __phd_parse_instance_config <instance_name>"
        return 1
    fi

    __phd_check_command_installed "yq" || return 1

    __log_info "Parsing instance configuration from $config_file"

    # Set instance name
    export PHD_INSTANCE_NAME="$instance_name"

    # Extract MySQL configuration - instance-specific values from config
    export PHD_INSTANCE_MYSQL_DATABASE="$(__phd_yq_get_or_default '.MYSQL_DATABASE' "openedx" "$config_file")"
    export PHD_INSTANCE_MYSQL_USERNAME="$(__phd_yq_get_or_default '.MYSQL_USERNAME' "openedx_user" "$config_file")"
    export PHD_INSTANCE_MYSQL_PASSWORD="$(__phd_yq_get_or_default '.MYSQL_PASSWORD' "openedx_password_123" "$config_file")"
    export PHD_INSTANCE_MYSQL_HOST="$(__phd_yq_get_or_default '.MYSQL_HOST' "mysql" "$config_file")"
    export PHD_INSTANCE_MYSQL_PORT="$(__phd_yq_get_or_default '.MYSQL_PORT' "3306" "$config_file")"

    # Extract MongoDB configuration - instance-specific values from config
    export PHD_INSTANCE_MONGODB_DATABASE="$(__phd_yq_get_or_default '.MONGODB_DATABASE' "openedx" "$config_file")"
    export PHD_INSTANCE_MONGODB_USERNAME="$(__phd_yq_get_or_default '.MONGODB_USERNAME' "openedx_user" "$config_file")"
    export PHD_INSTANCE_MONGODB_PASSWORD="$(__phd_yq_get_or_default '.MONGODB_PASSWORD' "openedx_password_123" "$config_file")"
    export PHD_INSTANCE_MONGODB_HOST="$(__phd_yq_get_or_default '.MONGODB_HOST' "mongodb" "$config_file")"
    export PHD_INSTANCE_MONGODB_PORT="$(__phd_yq_get_or_default '.MONGODB_PORT' "27017" "$config_file")"

    # MongoDB provider-specific configuration (optional, from global env or config)
    export PHD_INSTANCE_MONGODB_CLUSTER_ID="${PHD_MONGODB_CLUSTER_ID:-}"
    export PHD_INSTANCE_DIGITALOCEAN_TOKEN="${PHD_DIGITALOCEAN_TOKEN:-}"
    export PHD_INSTANCE_MONGODB_PROVIDER="$(__phd_detect_mongodb_provider "$PHD_INSTANCE_MONGODB_HOST" "$PHD_INSTANCE_MONGODB_CLUSTER_ID")"

    # Extract storage configuration - instance-specific values from config
    export PHD_INSTANCE_STORAGE_BUCKET_NAME="$(__phd_yq_get_or_default '.STORAGE_BUCKET_NAME' "${instance_name}-storage" "$config_file")"
    export PHD_INSTANCE_STORAGE_TYPE="$(__phd_yq_get_or_default '.STORAGE_TYPE' "spaces" "$config_file")"
    export PHD_INSTANCE_STORAGE_REGION="$(__phd_yq_get_or_default '.STORAGE_REGION' "nyc3" "$config_file")"
    export PHD_INSTANCE_STORAGE_ENDPOINT_URL="$(__phd_yq_get_or_default '.STORAGE_ENDPOINT_URL' "https://nyc3.digitaloceanspaces.com" "$config_file")"

    # Global credentials from environment (not instance-specific)
    export PHD_INSTANCE_MYSQL_ROOT_USER="${PHD_MYSQL_ROOT_USER}"
    export PHD_INSTANCE_MYSQL_ROOT_PASSWORD="${PHD_MYSQL_ROOT_PASSWORD}"
    export PHD_INSTANCE_MONGODB_ADMIN_USER="${PHD_MONGODB_ADMIN_USER}"
    export PHD_INSTANCE_MONGODB_ADMIN_PASSWORD="${PHD_MONGODB_ADMIN_PASSWORD}"
    export PHD_INSTANCE_MONGODB_ADMIN_DATABASE="${PHD_MONGODB_ADMIN_DATABASE}"
    export PHD_INSTANCE_STORAGE_ACCESS_KEY_ID="${PHD_STORAGE_ACCESS_KEY_ID}"
    export PHD_INSTANCE_STORAGE_SECRET_ACCESS_KEY="${PHD_STORAGE_SECRET_ACCESS_KEY}"

    # Validate storage configuration
    __phd_validate_storage_config "$PHD_INSTANCE_STORAGE_TYPE" "$PHD_INSTANCE_STORAGE_REGION" "$PHD_INSTANCE_STORAGE_ENDPOINT_URL"

    __log_success "Instance configuration parsed successfully"
    __log_debug "MySQL: ${PHD_INSTANCE_MYSQL_DATABASE}@${PHD_INSTANCE_MYSQL_HOST}:${PHD_INSTANCE_MYSQL_PORT} (user: ${PHD_INSTANCE_MYSQL_USERNAME})"
    __log_debug "MongoDB: ${PHD_INSTANCE_MONGODB_DATABASE}@${PHD_INSTANCE_MONGODB_HOST}:${PHD_INSTANCE_MONGODB_PORT} (user: ${PHD_INSTANCE_MONGODB_USERNAME}) - provider: ${PHD_INSTANCE_MONGODB_PROVIDER}"
    __log_debug "Storage: ${PHD_INSTANCE_STORAGE_BUCKET_NAME} (${PHD_INSTANCE_STORAGE_TYPE} in ${PHD_INSTANCE_STORAGE_REGION}) - provider: $(__phd_detect_storage_provider "$PHD_INSTANCE_STORAGE_TYPE")"

    # Warn if using digitalocean_api provider without required credentials
    if [ "$PHD_INSTANCE_MONGODB_PROVIDER" = "digitalocean_api" ]; then
        if [ -z "${PHD_INSTANCE_DIGITALOCEAN_TOKEN}" ]; then
            __log_warning "MongoDB provider is 'digitalocean_api' but PHD_DIGITALOCEAN_TOKEN is not set"
        fi
        if [ -z "${PHD_INSTANCE_MONGODB_CLUSTER_ID}" ]; then
            __log_warning "MongoDB provider is 'digitalocean_api' but PHD_MONGODB_CLUSTER_ID is not set"
        fi
    fi
}

# Render {{ VAR }} placeholders from environment variables, in-memory
function __phd_render_stream() {
    perl -pe 's/{{\s*([A-Za-z_][A-Za-z0-9_]*)\s*}}/exists $ENV{$1} ? $ENV{$1} : $&/ge'
}

################################################################################
# Script loading functions
################################################################################

# Build curl with common flags
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

    if [ -z "$username" ]; then
        __log_error "Username is required"
        echo "Usage: phd_create_argo_user <username> [role] [password]"
        return 1
    fi

    __phd_source_script "${SCRIPTS_DIR}" "create-user.sh" || return 1
    __phd_create_argo_user "$username" "$role" "$password" || return 1
}

function phd_update_argo_user_permissions() {
    local username="$1"
    local role="${2:-admin}"

    if [ -z "$username" ]; then
        __log_error "Username is required"
        echo "Usage: phd_update_argo_user_permissions <username> [role]"
        echo "  username: Argo user to update"
        echo "  role: admin, developer, or readonly (default: admin)"
        return 1
    fi

    __phd_source_script "${SCRIPTS_DIR}" "create-user.sh" || return 1
    __phd_update_argo_user_permissions "$username" "$role" || return 1
}

function phd_delete_argo_user() {
    local username="$1"

    if [ -z "$username" ]; then
        __log_error "Username is required"
        echo "Usage: phd_delete_argo_user <username>"
        return 1
    fi

    __phd_source_script "${SCRIPTS_DIR}" "delete-user.sh" || return 1
    __phd_delete_argo_user "$username" || return 1
}

function phd_create_instance() {
    local instance_name="$1"
    local instance_template_repository="${2:-https://github.com/open-craft/phd-cluster-template.git}"
    local platform_name="${3:-My Open edX Instance}"
    local edx_platform_repository="${4:-https://github.com/openedx/edx-platform.git}"
    local edx_platform_version="${5:-release/teak}"
    local tutor_version="${6:-v20.0.1}"

    if [ -z "$instance_name" ]; then
        __log_error "Instance name is required"
        echo "Usage: phd_create_instance <instance_name> [template_repo] [platform_name] [edx_repo] [edx_version] [tutor_version]"
        return 1
    fi

    __phd_source_script "${SCRIPTS_DIR}" "create-instance.sh" || return 1
    __phd_bootstrap_instance "$instance_name" "$instance_template_repository" "$platform_name" "$edx_platform_repository" "$edx_platform_version" "$tutor_version" || return 1
    __phd_parse_instance_config "$instance_name" || return 1
    __phd_set_instance_rbac "$instance_name" || return 1

    # Create workflow-executor token in the instance namespace
    __log_info "Creating workflow-executor token in namespace '$instance_name'"
    cat <<EOF | kubectl apply -f - || return 1
apiVersion: v1
kind: Secret
metadata:
  name: workflow-executor-token
  namespace: $instance_name
  annotations:
    kubernetes.io/service-account.name: workflow-executor
type: kubernetes.io/service-account-token
EOF
    __phd_create_workflows "$instance_name" || return 1
    __phd_create_argocd_application "$instance_name" || return 1
}

function phd_delete_instance() {
    local instance_name="$1"

    if [ -z "$instance_name" ]; then
        __log_error "Instance name is required"
        echo "Usage: phd_delete_instance <instance_name>"
        return 1
    fi

    __phd_source_script "${SCRIPTS_DIR}" "delete-instance.sh" || return 1
    __phd_parse_instance_config "$instance_name" || return 1
    __phd_delete_workflows "$instance_name" || return 1
    __phd_delete_argocd_application "$instance_name" || return 1
    __phd_create_deprovision_workflows "$instance_name" || return 1
    __phd_delete_instance "$instance_name" || return 1
}

__log_success "PHD commands loaded successfully"
__log_info "Loading context as environment variables"
__phd_load_context_as_env_vars "${ROOT_DIR}/context.json" || return 1
