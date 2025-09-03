#!/usr/bin/env bash
#
# User management script for Argo. This script provides functions to create and
# configure users in Argo with appropriate roles and permissions.

set -uo pipefail

function __phd_create_argo_user() {
    local username="$1"
    local role="${2:-developer}"
    local password="${3:-}"

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

    # Create service account for Argo Workflows token
    __phd_run_command "create service account for user '$username'" \
        kubectl create serviceaccount "$username" -n "argo" || return 1

    # Create role for the user based on their Argo Server role
    local argo_workflows_role_name="${username}-workflows"
    local argo_workflows_cluster_role_name="${username}-cluster-workflows"
    local role_yaml
    local cluster_role_yaml
    case "$role" in
        "admin")
            role_yaml="apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: $argo_workflows_role_name
  namespace: argo
rules:
- apiGroups: [\"argoproj.io\"]
  resources: [\"workflows\", \"workflowtemplates\", \"cronworkflows\", \"workfloweventbindings\"]
  verbs: [\"*\"]
- apiGroups: [\"\"]
  resources: [\"pods\", \"pods/log\", \"secrets\", \"configmaps\", \"services\"]
  verbs: [\"*\"]
- apiGroups: [\"apps\"]
  resources: [\"deployments\"]
  verbs: [\"*\"]
"
            cluster_role_yaml="apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: $argo_workflows_cluster_role_name
rules:
- apiGroups: [\"argoproj.io\"]
  resources: [\"clusterworkflowtemplates\"]
  verbs: [\"*\"]
- apiGroups: [\"\"]
  resources: [\"namespaces\"]
  verbs: [\"get\", \"list\", \"watch\"]
"
            ;;
        "developer")
            role_yaml="apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: $argo_workflows_role_name
  namespace: argo
rules:
- apiGroups: [\"argoproj.io\"]
  resources: [\"workflows\", \"workflowtemplates\", \"cronworkflows\", \"workfloweventbindings\"]
  verbs: [\"create\", \"delete\", \"get\", \"list\", \"watch\", \"update\", \"patch\"]
- apiGroups: [\"\"]
  resources: [\"pods\", \"pods/log\", \"secrets\", \"configmaps\"]
  verbs: [\"get\", \"list\", \"watch\", \"create\", \"update\", \"patch\", \"delete\"]
"
            cluster_role_yaml="apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: $argo_workflows_cluster_role_name
rules:
- apiGroups: [\"argoproj.io\"]
  resources: [\"clusterworkflowtemplates\"]
  verbs: [\"create\", \"delete\", \"get\", \"list\", \"watch\", \"update\", \"patch\"]
"
            ;;
        "readonly")
            role_yaml="apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: $argo_workflows_role_name
  namespace: argo
rules:
- apiGroups: [\"argoproj.io\"]
  resources: [\"workflows\", \"workflowtemplates\", \"cronworkflows\", \"workfloweventbindings\"]
  verbs: [\"get\", \"list\", \"watch\"]
- apiGroups: [\"\"]
  resources: [\"pods\", \"pods/log\", \"secrets\", \"configmaps\"]
  verbs: [\"get\", \"list\", \"watch\"]
"
            cluster_role_yaml="apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: $argo_workflows_cluster_role_name
rules:
- apiGroups: [\"argoproj.io\"]
  resources: [\"clusterworkflowtemplates\"]
  verbs: [\"get\", \"list\", \"watch\"]
"
            ;;
        *)
            __log_error "Unknown role '$role' for Argo Workflows token creation"
            return 1
            ;;
    esac

    # Apply the namespace-scoped role
    __phd_run_command "create role for user '$username'" \
        echo "$role_yaml" | kubectl apply -f - || return 1

    # Apply the cluster-scoped role if it exists
    if [ -n "$cluster_role_yaml" ]; then
        __phd_run_command "create cluster role for user '$username'" \
            echo "$cluster_role_yaml" | kubectl apply -f - || return 1
    fi

    # Bind the service account to the namespace-scoped role
    __phd_run_command "bind service account to role for user '$username'" \
        kubectl create rolebinding "${username}-binding" --role="$argo_workflows_role_name" --serviceaccount="argo:$username" -n "argo" || return 1

    # Bind the service account to the cluster-scoped role if it exists
    if [ -n "$cluster_role_yaml" ]; then
        __phd_run_command "bind service account to cluster role for user '$username'" \
            kubectl create clusterrolebinding "${username}-cluster-binding" --clusterrole="$argo_workflows_cluster_role_name" --serviceaccount="argo:$username" || return 1
    fi

    # Create secret for the service account token
    local token_secret_name="${username}-token"
    local token_secret_yaml="apiVersion: v1
kind: Secret
metadata:
  name: $token_secret_name
  namespace: argo
  annotations:
    kubernetes.io/service-account.name: $username
type: kubernetes.io/service-account-token"

    __phd_run_command "create token secret for user '$username'" \
        echo "$token_secret_yaml" | kubectl apply -f - || return 1

    # Wait for token to be available and extract it
    __log_info "Waiting for token to be generated..."
    local token=""

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