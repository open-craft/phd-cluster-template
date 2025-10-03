"""
Argo user update command.
"""

import argparse

from phd.cli.utils import exit_with_error, run_command_with_logging
from phd.config import get_config
from phd.exceptions import KubernetesError
from phd.kubeconfig import setup_kubeconfig
from phd.kubernetes import KubernetesClient
from phd.utils import get_logger, log_success

logger = get_logger(__name__)

VALID_ROLES = ["admin", "developer", "readonly"]
DEFAULT_ROLE = "developer"
ARGO_NAMESPACE = "argo"
ARGOCD_NAMESPACE = "argocd"


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


def _apply_role_manifests(
    k8s_client: KubernetesClient,
    username: str,
    role: str,
    manifests_url: str,
) -> None:
    """
    Apply role-specific RBAC manifests for Argo Workflows.

    Args:
        k8s_client: Kubernetes client
        username: Username to apply manifests for
        role: Role to apply
        manifests_url: Base URL for manifests
    """

    role_manifest_map = {
        "admin": f"{manifests_url}/argo-user-admin-role.yml",
        "developer": f"{manifests_url}/argo-user-developer-role.yml",
        "readonly": f"{manifests_url}/argo-user-readonly-role.yml",
    }

    variables = {"PHD_ARGO_USERNAME": username, "PHD_ARGO_ROLE": role}

    run_command_with_logging(
        logger,
        f"update {role} role for user '{username}'",
        k8s_client.apply_manifest_from_url,
        role_manifest_map[role],
        ARGO_NAMESPACE,
        variables,
    )

    run_command_with_logging(
        logger,
        f"update role bindings for user '{username}'",
        k8s_client.apply_manifest_from_url,
        f"{manifests_url}/argo-user-bindings.yml",
        ARGO_NAMESPACE,
        variables,
    )


def update_argo_user_permissions(username: str, role: str = DEFAULT_ROLE) -> None:
    """
    Update Argo user permissions to the specified role.

    Updates RBAC policies for both Argo Workflows and ArgoCD.

    Args:
        username: Username to update
        role: New user role (admin, developer, or readonly)

    Raises:
        KubernetesError: If permission update fails
        ValueError: If invalid role is provided
    """

    if role not in VALID_ROLES:
        raise ValueError(
            f"Invalid role '{role}'. Must be one of: {', '.join(VALID_ROLES)}"
        )

    logger.info("Updating permissions for user '%s' with role '%s'", username, role)

    k8s_client = KubernetesClient()
    config = get_config()

    _apply_role_manifests(
        k8s_client,
        username,
        role,
        config.cluster.opencraft_manifests_url,  # pylint: disable=no-member
    )

    _update_rbac_policy(
        k8s_client,
        "argo-server-rbac-config",
        ARGO_NAMESPACE,
        username,
        role,
    )

    _update_rbac_policy(
        k8s_client,
        "argocd-rbac-cm",
        ARGOCD_NAMESPACE,
        username,
        role,
    )

    log_success(logger, f"Permissions updated for user '{username}' with role '{role}'")
    logger.warning(
        "The user may need to log out and log back in for changes to take effect"
    )


def main() -> None:
    """
    Main entry point for argo user update command.
    """

    parser = argparse.ArgumentParser(
        description="Update Argo user permissions to specified role"
    )
    parser.add_argument("username", help="Username to update")
    parser.add_argument(
        "--role",
        default=DEFAULT_ROLE,
        choices=VALID_ROLES,
        help=f"New user role (default: {DEFAULT_ROLE})",
    )

    args = parser.parse_args()

    setup_kubeconfig()

    try:
        update_argo_user_permissions(args.username, args.role)
    except ValueError as e:
        exit_with_error(logger, f"Validation error: {e}", exc_info=False)
    except KubernetesError as e:
        exit_with_error(logger, f"Kubernetes error: {e}")
    except KeyboardInterrupt:
        exit_with_error(logger, "Permission update cancelled", exc_info=False)
    except Exception as e:  # pylint: disable=broad-exception-caught
        exit_with_error(logger, f"Unexpected error: {e}")
