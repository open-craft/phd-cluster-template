"""
Argo user create command.
"""

import argparse
import base64
import getpass
import time

from phd.cli.utils import exit_with_error, run_command_with_logging
from phd.config import get_config
from phd.exceptions import KubernetesError
from phd.kubeconfig import setup_kubeconfig
from phd.kubernetes import KubernetesClient
from phd.password import bcrypt_password
from phd.utils import (
    get_logger,
    log_success,
    sanitize_username,
)

logger = get_logger(__name__)

VALID_ROLES = ["admin", "developer", "readonly"]
DEFAULT_ROLE = "developer"
ARGO_NAMESPACE = "argo"
ARGOCD_NAMESPACE = "argocd"
TOKEN_WAIT_TIMEOUT = 30
TOKEN_WAIT_INTERVAL = 1


def _prompt_for_password(username: str) -> str:
    """
    Prompt user for password with confirmation.

    Args:
        username: Username for context in the prompt

    Returns:
        The validated password

    Raises:
        ValueError: If passwords don't match or password is empty
    """

    logger.info("Enter a password for %s:", username)
    password = getpass.getpass("Password: ")
    password_confirm = getpass.getpass("Confirm password: ")

    if password != password_confirm:
        raise ValueError("Passwords do not match")

    if not password:
        raise ValueError("Password cannot be empty")

    return password


def _update_rbac_policy(  # pylint: disable=duplicate-code
    k8s_client: KubernetesClient,
    configmap_name: str,
    namespace: str,
    username: str,
    role: str,
) -> None:
    """
    Update RBAC policy in a ConfigMap by adding/updating user role assignment.

    Args:
        k8s_client: Kubernetes client
        configmap_name: Name of the ConfigMap containing RBAC policy
        namespace: Namespace of the ConfigMap
        username: Username to add to policy
        role: Role to assign to user
    """

    config_map = run_command_with_logging(
        logger,
        f"read {configmap_name} RBAC config",
        k8s_client.read_config_map,
        name=configmap_name,
        namespace=namespace,
    )

    if config_map.data is None:
        config_map.data = {}

    policy_lines = [
        line
        for line in config_map.data.get("policy.csv", "").split("\n")
        if f"g, {username}, " not in line
    ]
    policy_lines.append(f"g, {username}, role:{role}")
    new_policy = "\n".join(policy_lines)

    run_command_with_logging(
        logger,
        f"update {configmap_name} RBAC policy for user '{username}'",
        k8s_client.patch_config_map,
        name=configmap_name,
        namespace=namespace,
        data={"policy.csv": new_policy},
    )


def _configure_argo_workflows_user(
    k8s_client: KubernetesClient,
    username: str,
    role: str,
    password_hash: str,
) -> None:
    """
    Configure Argo Workflows user with SSO and RBAC.

    Args:
        k8s_client: Kubernetes client
        username: Username to configure
        role: Role to assign
        password_hash: Bcrypt password hash
    """

    enabled_b64 = base64.b64encode(b"true").decode("utf-8")
    hash_b64 = base64.b64encode(password_hash.encode("utf-8")).decode("utf-8")
    tokens_b64 = base64.b64encode(b"").decode("utf-8")

    # Sanitize username for use as Kubernetes secret key
    sanitized_username = sanitize_username(username)

    run_command_with_logging(
        logger,
        f"update Argo Workflows SSO secret for user '{username}'",
        k8s_client.patch_secret,
        name="argo-server-sso",
        namespace=ARGO_NAMESPACE,
        data={
            f"accounts.{sanitized_username}.enabled": enabled_b64,
            f"accounts.{sanitized_username}.password": hash_b64,
            f"accounts.{sanitized_username}.tokens": tokens_b64,
        },
    )

    _update_rbac_policy(
        k8s_client,
        "argo-server-rbac-config",
        ARGO_NAMESPACE,
        sanitized_username,
        role,
    )

    log_success(
        logger,
        f"Argo Workflows user '{username}' configured with role '{role}'",
    )
    logger.warning("Restart the argo-server pod to apply login changes:")
    logger.warning("  kubectl delete pod -n argo -l app=argo-server")


def _configure_argocd_user(
    k8s_client: KubernetesClient,
    username: str,
    role: str,
    password_hash: str,
) -> None:
    """
    Configure ArgoCD user with account and RBAC.

    Args:
        k8s_client: Kubernetes client
        username: Username to configure
        role: Role to assign
        password_hash: Bcrypt password hash
    """

    logger.info("Configuring ArgoCD user '%s'", username)

    sanitized_username = sanitize_username(username)

    argocd_cm = run_command_with_logging(
        logger,
        "read ArgoCD config",
        k8s_client.read_config_map,
        name="argocd-cm",
        namespace=ARGOCD_NAMESPACE,
    )
    if argocd_cm.data is None:
        argocd_cm.data = {}

    argocd_cm.data[f"accounts.{sanitized_username}"] = "login"

    run_command_with_logging(
        logger,
        f"update ArgoCD config for user '{username}'",
        k8s_client.patch_config_map,
        name="argocd-cm",
        namespace=ARGOCD_NAMESPACE,
        data=argocd_cm.data,
    )

    hash_b64 = base64.b64encode(password_hash.encode("utf-8")).decode("utf-8")
    run_command_with_logging(
        logger,
        f"update ArgoCD secret for user '{username}'",
        k8s_client.patch_secret,
        name="argocd-secret",
        namespace=ARGOCD_NAMESPACE,
        data={f"accounts.{sanitized_username}.password": hash_b64},
    )

    _update_rbac_policy(
        k8s_client,
        "argocd-rbac-cm",
        ARGOCD_NAMESPACE,
        sanitized_username,
        role,
    )

    log_success(logger, f"ArgoCD user '{username}' configured with role '{role}'")
    logger.warning("Restart the argocd-server pod to apply login changes:")
    logger.warning(
        "  kubectl delete pod -n argocd -l app.kubernetes.io/name=argocd-server"
    )


def _wait_for_token_generation(
    k8s_client: KubernetesClient,
    username: str,
    timeout: int = TOKEN_WAIT_TIMEOUT,
) -> str:
    """
    Wait for service account token to be generated.

    Args:
        k8s_client: Kubernetes client
        username: Username for which to wait for token
        timeout: Maximum time to wait in seconds

    Returns:
        The generated token

    Raises:
        KubernetesError: If token generation times out
    """

    logger.info("Waiting for token to be generated...")
    token_secret_name = f"{username}-token"

    for _ in range(timeout):
        try:
            secret = k8s_client.read_secret(
                name=token_secret_name, namespace=ARGO_NAMESPACE
            )
            if secret.data and "token" in secret.data:
                token = base64.b64decode(secret.data["token"]).decode("utf-8")
                return token
        except Exception:  # pylint: disable=broad-exception-caught
            pass
        time.sleep(TOKEN_WAIT_INTERVAL)

    raise KubernetesError(f"Failed to generate token for user '{username}'")


def _create_service_account_and_token(
    k8s_client: KubernetesClient,
    username: str,
    role: str,
) -> str:
    """
    Create service account, RBAC, and token secret for Argo Workflows API access.

    Args:
        k8s_client: Kubernetes client
        username: Username to create service account for
        role: Role to assign

    Returns:
        The generated access token

    Raises:
        KubernetesError: If token generation fails
    """

    logger.info("Creating Argo Workflows access token for user '%s'", username)

    config = get_config()
    manifests_url = config.cluster.opencraft_manifests_url  # pylint: disable=no-member

    # Use DNS-1123 safe name for K8s objects (service account, bindings)
    k8s_name = sanitize_username(username)

    run_command_with_logging(
        logger,
        f"create service account for user '{username}'",
        k8s_client.apply_manifest,
        f"""
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {k8s_name}
  namespace: {ARGO_NAMESPACE}
""",
        ARGO_NAMESPACE,
    )

    role_manifest_map = {
        "admin": f"{manifests_url}/argo-user-admin-role.yml",
        "developer": f"{manifests_url}/argo-user-developer-role.yml",
        "readonly": f"{manifests_url}/argo-user-readonly-role.yml",
    }

    variables = {"PHD_ARGO_USERNAME": k8s_name, "PHD_ARGO_ROLE": role}

    run_command_with_logging(
        logger,
        f"create {role} role for user '{username}'",
        k8s_client.apply_manifest_from_url,
        role_manifest_map[role],
        ARGO_NAMESPACE,
        variables,
    )

    run_command_with_logging(
        logger,
        f"create role bindings for user '{username}'",
        k8s_client.apply_manifest_from_url,
        f"{manifests_url}/argo-user-bindings.yml",
        ARGO_NAMESPACE,
        variables,
    )

    run_command_with_logging(
        logger,
        f"create token secret for user '{username}'",
        k8s_client.apply_manifest_from_url,
        f"{manifests_url}/argo-user-token-secret.yml",
        ARGO_NAMESPACE,
        variables,
    )

    token = _wait_for_token_generation(k8s_client, k8s_name)

    run_command_with_logging(
        logger,
        f"configure token for UI access for user '{username}'",
        k8s_client.patch_secret,
        name="argo-server-sso",
        namespace=ARGO_NAMESPACE,
        string_data={
            f"accounts.{sanitize_username(username)}.tokens": token,
        },
    )

    return token


def create_argo_user(
    username: str, role: str = DEFAULT_ROLE, password: str = ""
) -> None:
    """
    Create an Argo user with the specified role and password.

    This orchestrates the creation of an Argo user across:
    - Argo Workflows (SSO and RBAC)
    - ArgoCD (account and RBAC)
    - Kubernetes service account and token for API access

    Args:
        username: Username to create
        role: User role (admin, developer, or readonly)
        password: User password (will prompt if not provided)

    Raises:
        KubernetesError: If user creation fails
        ValueError: If invalid role is provided or password validation fails
    """

    if role not in VALID_ROLES:
        raise ValueError(
            f"Invalid role '{role}'. Must be one of: {', '.join(VALID_ROLES)}"
        )

    if not password:
        password = _prompt_for_password(username)

    logger.info("Creating user '%s' with role '%s'", username, role)

    k8s_client = KubernetesClient()
    config = get_config()
    password_hash = bcrypt_password(password)

    _configure_argo_workflows_user(k8s_client, username, role, password_hash)

    _configure_argocd_user(k8s_client, username, role, password_hash)

    token = _create_service_account_and_token(k8s_client, username, role)

    log_success(
        logger,
        f"Argo Workflows access token created successfully for user '{username}'",
    )
    logger.warning("Argo Workflows API and UI Token for user '%s':", username)
    logger.warning("  %s", token)
    logger.info("")
    logger.info("This token can be used with:")
    logger.info(
        '  curl -H "Authorization: Bearer $TOKEN" https://workflows.%s/api/v1/workflows/argo',
        config.cluster.cluster_domain,  # pylint: disable=no-member
    )
    logger.info(
        "  argo --server=https://workflows.%s --token=$TOKEN list",
        config.cluster.cluster_domain,  # pylint: disable=no-member
    )
    logger.info("")
    logger.warning("Restart the argo-server pod to apply UI token changes:")
    logger.warning("  kubectl delete pod -n argo -l app=argo-server")


def main() -> None:
    """
    Main entry point for argo user create command.
    """

    parser = argparse.ArgumentParser(
        description="Create an Argo user with specified role and password"
    )
    parser.add_argument("username", help="Username to create")
    parser.add_argument(
        "--role",
        default=DEFAULT_ROLE,
        choices=VALID_ROLES,
        help=f"User role (default: {DEFAULT_ROLE})",
    )
    parser.add_argument(
        "--password", default="", help="User password (will prompt if not provided)"
    )

    args = parser.parse_args()

    setup_kubeconfig()

    try:
        create_argo_user(args.username, args.role, args.password)
    except ValueError as e:
        exit_with_error(logger, f"Validation error: {e}", exc_info=False)
    except KubernetesError as e:
        exit_with_error(logger, f"Kubernetes error: {e}")
    except KeyboardInterrupt:
        exit_with_error(logger, "User creation cancelled", exc_info=False)
    except Exception as e:  # pylint: disable=broad-exception-caught
        exit_with_error(logger, f"Unexpected error: {e}")
