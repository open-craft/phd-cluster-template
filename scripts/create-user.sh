#!/usr/bin/env bash
#
# User management script for Argo. This script provides functions to create and
# configure users in Argo with appropriate roles and permissions.

set -uo pipefail

function __phd_create_argo_user() {
    local username="$1"
    local role="${2:-developer}"
    local password="${3:-}"

    if [ -z "$username" ]; then
        __log_error "Username is required"
        echo "Usage: __phd_create_argo_user <username> [role] [password]"
        return 1
    fi

    # Verify prerequisites
    __phd_check_command_installed "kubectl" || return 1
    __phd_check_command_installed "python3" || return 1
    __phd_check_command_installed "base64" || return 1
    __phd_check_command_installed "jq" || return 1

    __phd_source_script "${SCRIPTS_DIR}" "set-admin-password.sh" || return 1

    if [ -z "$password" ]; then
        password=$(__phd_ask_for_password) || return 1
    fi

    __log_info "Creating user \"$username\" with role \"$role\""

    local hash
    hash=$(__phd_bcrypt_password "$password") || return 1

    local enabled_b64
    enabled_b64=$(__phd_run_command "encode enabled flag" echo -n "true" | base64 -w0) || return 1

    local hash_b64
    hash_b64=$(__phd_run_command "encode password hash" echo -n "$hash" | base64 -w0) || return 1

    local tokens_b64
    tokens_b64=$(__phd_run_command "encode tokens" echo -n "" | base64 -w0) || return 1

    __phd_run_command "update SSO secret for user '$username'" kubectl patch secret argo-server-sso -n "argo" --patch="{
  \"data\": {
    \"accounts.$username.enabled\": \"$enabled_b64\",
    \"accounts.$username.password\": \"$hash_b64\",
    \"accounts.$username.tokens\": \"$tokens_b64\"
  }
}" --type=merge || return 1

    local current_policy
    current_policy=$(__phd_run_command "get current RBAC policy" \
        kubectl get configmap argo-server-rbac-config -n "argo" -o jsonpath='{.data.policy\.csv}') || return 1

    local new_policy
    new_policy=$(__phd_run_command "prepare new RBAC policy" \
        echo "$current_policy" | grep -v "g, $username, " || true)

    new_policy="$new_policy
g, $username, role:$role"

    # JSON-escape policy content using jq -Rs
    local new_policy_json
    new_policy_json=$(printf "%s" "$new_policy" | jq -Rs .) || return 1

    __phd_run_command "update RBAC policy for user '$username'" kubectl patch configmap argo-server-rbac-config -n "argo" --type=merge --patch="{\"data\": {\"policy.csv\": $new_policy_json}}" || return 1

    __log_success "User \"$username\" created successfully with \"$role\" role"
    __log_warning "Restart the argo-server to apply changes:"
    __log_warning "  kubectl delete pod -n argo -l app=argo-server"

    __log_info "Configuring matching ArgoCD user \"$username\" with role \"$role\""

    # Enable user login in argocd-cm
    __phd_run_command "enable ArgoCD user in argocd-cm" kubectl patch configmap argocd-cm -n "argocd" --type merge --patch="{\"data\": {\"accounts.$username\": \"login\"}}" || return 1

    # Set user password in argocd-secret
    local argocd_pwd_b64
    argocd_pwd_b64=$(__phd_run_command "encode ArgoCD password hash" echo -n "$hash" | base64 -w0) || return 1
    __phd_run_command "update ArgoCD password in argocd-secret" kubectl patch secret argocd-secret -n "argocd" --type=merge --patch="{\"data\": {\"accounts.$username.password\": \"$argocd_pwd_b64\"}}" || return 1

    # Update ArgoCD RBAC policy
    local acd_current_policy
    acd_current_policy=$(__phd_run_command "get current ArgoCD RBAC policy" \
        kubectl get configmap argocd-rbac-cm -n "argocd" -o jsonpath='{.data.policy\.csv}' || echo "") || return 1

    local acd_new_policy
    acd_new_policy=$(__phd_run_command "prepare new ArgoCD RBAC policy" \
        echo "$acd_current_policy" | grep -v "g, $username, " || true)
    acd_new_policy="$acd_new_policy
g, $username, role:$role"

    local acd_policy_json
    acd_policy_json=$(printf "%s" "$acd_new_policy" | jq -Rs .) || return 1

    __phd_run_command "update ArgoCD RBAC policy for user '$username'" kubectl patch configmap argocd-rbac-cm -n "argocd" --type=merge --patch="{\"data\": {\"policy.csv\": $acd_policy_json}}" || return 1

    __log_success "ArgoCD user \"$username\" configured with role \"$role\""
    __log_warning "Restart the argocd-server pod to apply login changes:"
    __log_warning "  kubectl delete pod -n argocd -l app.kubernetes.io/name=argocd-server"

    __log_info "Creating Argo Workflows access token for user \"$username\""

    # Create service account for Argo Workflows token (idempotent)
    __phd_run_command "create service account for user '$username'" \
        kubectl create serviceaccount "$username" -n "argo" --dry-run=client -o yaml | kubectl apply -f - || return 1

    # Set environment variables for template rendering
    export PHD_ARGO_USERNAME="$username"
    export PHD_ARGO_ROLE="$role"

    # Apply role-specific RBAC manifests
    case "$role" in
    "admin")
        __phd_run_command "create admin role for user '$username'" \
            __phd_kubectl_apply_from_url argo "${OPENCRAFT_MANIFESTS_URL}/argo-user-admin-role.yml" || return 1
        ;;
    "developer")
        __phd_run_command "create developer role for user '$username'" \
            __phd_kubectl_apply_from_url argo "${OPENCRAFT_MANIFESTS_URL}/argo-user-developer-role.yml" || return 1
        ;;
    "readonly")
        __phd_run_command "create readonly role for user '$username'" \
            __phd_kubectl_apply_from_url argo "${OPENCRAFT_MANIFESTS_URL}/argo-user-readonly-role.yml" || return 1
        ;;
    *)
        __log_error "Unknown role '$role' for Argo Workflows token creation"
        return 1
        ;;
    esac

    # Apply role bindings
    __phd_run_command "create role bindings for user '$username'" \
        __phd_kubectl_apply_from_url argo "${OPENCRAFT_MANIFESTS_URL}/argo-user-bindings.yml" || return 1

    # Create token secret
    __phd_run_command "create token secret for user '$username'" \
        __phd_kubectl_apply_from_url argo "${OPENCRAFT_MANIFESTS_URL}/argo-user-token-secret.yml" || return 1

    # Wait for token to be available and extract it
    __log_info "Waiting for token to be generated..."
    local token=""
    local token_secret_name="${username}-token"

    # Wait up to 30 seconds for the token to be generated
    for i in {1..30}; do
        token=$(__phd_run_command "get token for user '$username'" \
            kubectl get secret "$token_secret_name" -n "argo" -o jsonpath='{.data.token}' | base64 --decode 2>/dev/null || echo "")

        if [ -n "$token" ]; then
            break
        fi
        sleep 1
    done

    if [ -z "$token" ]; then
        __log_error "Failed to generate token for user '$username'"
        return 1
    fi

    __log_info "Configuring token for UI access..."
    __phd_run_command "configure token for UI access for user '$username'" kubectl patch secret argo-server-sso -n "argo" --type=merge --patch="{
  \"stringData\": {
    \"accounts.$username.tokens\": \"$token\"
  }
}" || return 1

    __log_success "Argo Workflows access token created successfully for user '$username'"
    __log_warning "Argo Workflows API and UI Token for user '$username':"
    __log_warning "  $token"
    __log_info ""
    __log_info "This token can be used with:"
    __log_info "  curl -H \"Authorization: Bearer \$TOKEN\" https://workflows.$PHD_CLUSTER_DOMAIN/api/v1/workflows/argo"
    __log_info "  argo --server=https://workflows.$PHD_CLUSTER_DOMAIN --token=\$TOKEN list"
    __log_info ""
    __log_warning "Restart the argo-server pod to apply UI token changes:"
    __log_warning "  kubectl delete pod -n argo -l app=argo-server"

}

function __phd_update_argo_user_permissions() {
    local username="$1"
    local role="${2:-developer}"

    if [ -z "$username" ]; then
        __log_error "Username is required"
        echo "Usage: __phd_update_argo_user_permissions <username> [role]"
        return 1
    fi

    __log_info "Updating permissions for user \"$username\" with role \"$role\""

    # Set environment variables for template rendering
    export PHD_ARGO_USERNAME="$username"
    export PHD_ARGO_ROLE="$role"

    # Apply role-specific RBAC manifests
    case "$role" in
    "admin")
        __phd_run_command "update admin role for user '$username'" \
            __phd_kubectl_apply_from_url argo "${OPENCRAFT_MANIFESTS_URL}/argo-user-admin-role.yml" || return 1
        ;;
    "developer")
        __phd_run_command "update developer role for user '$username'" \
            __phd_kubectl_apply_from_url argo "${OPENCRAFT_MANIFESTS_URL}/argo-user-developer-role.yml" || return 1
        ;;
    "readonly")
        __phd_run_command "update readonly role for user '$username'" \
            __phd_kubectl_apply_from_url argo "${OPENCRAFT_MANIFESTS_URL}/argo-user-readonly-role.yml" || return 1
        ;;
    *)
        __log_error "Unknown role '$role' for Argo Workflows permission update"
        return 1
        ;;
    esac

    # Apply role bindings
    __phd_run_command "update role bindings for user '$username'" \
        __phd_kubectl_apply_from_url argo "${OPENCRAFT_MANIFESTS_URL}/argo-user-bindings.yml" || return 1

    __log_success "Permissions updated for user \"$username\" with role \"$role\""
    __log_warning "The user may need to log out and log back in for changes to take effect"
}
