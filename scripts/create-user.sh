#! /bin/env bash

set -uo pipefail

# shellcheck disable=SC2155
function __phd_create_argo_user() {
    local username="$1"
    local password="$2"
    local role="${3:-developer}"

    __phd_check_command_installed "kubectl"
    __phd_check_command_installed "python3"

    __log_info "Creating user \"$username\" with role \"$role\""

    local hash=$(python3 -c "
import bcrypt
password = '$password'.encode('utf-8')
salt = bcrypt.gensalt(rounds=10)
hashed = bcrypt.hashpw(password, salt)
print(hashed.decode('utf-8'))
")

    # Base64 encode for Kubernetes secret
    local enabled_b64=$(echo -n "true" | base64 -w0)
    local hash_b64=$(echo -n "$hash" | base64 -w0)
    local tokens_b64=$(echo -n "" | base64 -w0)

    __log_info "Updating SSO secret for user $username"
    kubectl patch secret argo-server-sso -n "argo" --patch="{
  \"data\": {
    \"accounts.$username.enabled\": \"$enabled_b64\",
    \"accounts.$username.password\": \"$hash_b64\",
    \"accounts.$username.tokens\": \"$tokens_b64\"
  }
}" --type=merge

    __log_info "Updating RBAC policy for user $username"
    local current_policy=$(kubectl get configmap argo-server-rbac-config -n "argo" -o jsonpath='{.data.policy\.csv}')

    # Remove existing mapping for this user (if any)
    local new_policy=$(echo "$current_policy" | grep -v "g, $username, " || true)

    # Add new mapping
    new_policy="$new_policy
g, $username, role:$role"

    # Update the ConfigMap
    kubectl patch configmap argo-server-rbac-config -n "argo" --patch="{
  \"data\": {
    \"policy.csv\": \"$new_policy\"
  }
}"

    __log_success "User \"$username\" created successfully with \"$role\" role"
    __log_warning "Restart the argo-server to apply changes:"
    __log_warning "  kubectl delete pod -n argo -l app=argo-server"
}
