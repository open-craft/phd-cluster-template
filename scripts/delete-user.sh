#!/usr/bin/env bash
#
# User deletion script for Argo. This script removes users from both ArgoCD
# and Argo Workflows and cleans up all associated Kubernetes resources.
#

set -uo pipefail

function __phd_delete_argo_user() {
    local username="$1"

    if [ -z "$username" ]; then
        __log_error "Username is required"
        return 1
    fi

    # Verify prerequisites
    __phd_check_command_installed "kubectl" || return 1
    __phd_source_script "${SCRIPTS_DIR}" "set-admin-password.sh" || return 1

    __log_info "Starting deletion of user '$username' and all associated resources"
    __log_warning "This will permanently remove the user and all their permissions"

    # Confirm deletion
    local confirm=""
    echo -n "Are you sure you want to delete user '$username'? (y/N): "
    read confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        __log_info "User deletion cancelled"
        return 0
    fi

    local errors=0

    # Remove ArgoCD user
    __log_info "Removing ArgoCD user '$username'..."
    if ! __phd_run_command "remove ArgoCD user from argocd-cm" kubectl patch configmap argocd-cm -n "argocd" --type=merge --patch="{\"data\": {\"accounts.$username\": null}}" 2>/dev/null; then
        __log_warning "Failed to remove user from argocd-cm (user may not exist)"
    fi

    if ! __phd_run_command "remove ArgoCD user from argocd-secret" kubectl patch secret argocd-secret -n "argocd" --type=merge --patch="{\"data\": {\"accounts.$username.password\": null}}" 2>/dev/null; then
        __log_warning "Failed to remove user from argocd-secret (user may not exist)"
    fi

    # Remove ArgoCD RBAC policy
    local acd_current_policy
    acd_current_policy=$(__phd_run_command "get current ArgoCD RBAC policy" \
        kubectl get configmap argocd-rbac-cm -n "argocd" -o jsonpath='{.data.policy\.csv}' || echo "") || true

    if [ -n "$acd_current_policy" ]; then
        local acd_new_policy
        acd_new_policy=$(__phd_run_command "prepare new ArgoCD RBAC policy" \
            echo "$acd_current_policy" | grep -v "g, $username, " || true)

        if [ "$acd_new_policy" != "$acd_current_policy" ]; then
            local acd_policy_json
            acd_policy_json=$(printf "%s" "$acd_new_policy" | jq -Rs .) || true
            if [ -n "$acd_policy_json" ]; then
                __phd_run_command "update ArgoCD RBAC policy for user '$username'" kubectl patch configmap argocd-rbac-cm -n "argocd" --type=merge --patch="{\"data\": {\"policy.csv\": $acd_policy_json}}" || __log_warning "Failed to update ArgoCD RBAC policy"
            fi
        fi
    fi

    # Remove Argo Workflows user from SSO secret
    __log_info "Removing Argo Workflows user '$username' from SSO secret..."
    if ! __phd_run_command "remove user from Argo Workflows SSO" kubectl patch secret argo-server-sso -n "argo" --type=merge --patch="{
  \"data\": {
    \"accounts.$username.enabled\": null,
    \"accounts.$username.password\": null,
    \"accounts.$username.tokens\": null
  }
}" 2>/dev/null; then
        __log_warning "Failed to remove user from argo-server-sso (user may not exist)"
    fi

    # Remove Argo Workflows RBAC policy
    __log_info "Removing Argo Workflows RBAC policy for user '$username'..."
    local current_policy
    current_policy=$(__phd_run_command "get current Argo Workflows RBAC policy" \
        kubectl get configmap argo-server-rbac-config -n "argo" -o jsonpath='{.data.policy\.csv}' || echo "") || true

    if [ -n "$current_policy" ]; then
        local new_policy
        new_policy=$(__phd_run_command "prepare new Argo Workflows RBAC policy" \
            echo "$current_policy" | grep -v "g, $username, " || true)

        if [ "$new_policy" != "$current_policy" ]; then
            local policy_json
            policy_json=$(printf "%s" "$new_policy" | jq -Rs .) || true
            if [ -n "$policy_json" ]; then
                __phd_run_command "update Argo Workflows RBAC policy for user '$username'" kubectl patch configmap argo-server-rbac-config -n "argo" --type=merge --patch="{\"data\": {\"policy.csv\": $policy_json}}" || __log_warning "Failed to update Argo Workflows RBAC policy"
            fi
        fi
    fi

    # Remove Kubernetes service account
    __log_info "Removing Kubernetes service account for user '$username'..."
    if ! __phd_run_command "delete service account for user '$username'" kubectl delete serviceaccount "$username" -n "argo" 2>/dev/null; then
        __log_warning "Failed to delete service account (may not exist)"
    fi

    # Remove token secret
    __log_info "Removing token secret for user '$username'..."
    if ! __phd_run_command "delete token secret for user '$username'" kubectl delete secret "${username}-token" -n "argo" 2>/dev/null; then
        __log_warning "Failed to delete token secret (may not exist)"
    fi

    # Remove RBAC role
    __log_info "Removing RBAC role for user '$username'..."
    if ! __phd_run_command "delete role for user '$username'" kubectl delete role "${username}-workflows" -n "argo" 2>/dev/null; then
        __log_warning "Failed to delete role (may not exist)"
    fi

    # Remove role binding
    __log_info "Removing role binding for user '$username'..."
    if ! __phd_run_command "delete role binding for user '$username'" kubectl delete rolebinding "${username}-binding" -n "argo" 2>/dev/null; then
        __log_warning "Failed to delete role binding (may not exist)"
    fi

    # Remove cluster role
    __log_info "Removing cluster role for user '$username'..."
    if ! __phd_run_command "delete cluster role for user '$username'" kubectl delete clusterrole "${username}-cluster-workflows" 2>/dev/null; then
        __log_warning "Failed to delete cluster role (may not exist)"
    fi

    # Remove cluster role binding
    __log_info "Removing cluster role binding for user '$username'..."
    if ! __phd_run_command "delete cluster role binding for user '$username'" kubectl delete clusterrolebinding "${username}-cluster-binding" 2>/dev/null; then
        __log_warning "Failed to delete cluster role binding (may not exist)"
    fi

    __log_success "User '$username' deletion process completed"
    __log_warning "Restart the servers to apply all changes:"
    __log_warning "  ArgoCD: kubectl delete pod -n argocd -l app.kubernetes.io/name=argocd-server"
    __log_warning "  Argo Workflows: kubectl delete pod -n argo -l app=argo-server"

    if [ $errors -gt 0 ]; then
        __log_warning "Some cleanup operations failed - manual cleanup may be required"
        return 1
    fi
}
