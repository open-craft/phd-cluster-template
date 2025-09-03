"""
Argo user delete command.
"""

import argparse

from phd.cli.utils import exit_with_error, run_command_with_logging
from phd.exceptions import KubernetesError
from phd.kubeconfig import setup_kubeconfig
from phd.kubernetes import KubernetesClient
from phd.utils import get_logger, log_success

logger = get_logger(__name__)

ARGO_NAMESPACE = "argo"
ARGOCD_NAMESPACE = "argocd"


def _remove_rbac_policy(
    k8s_client: KubernetesClient,
    configmap_name: str,
    namespace: str,
    username: str,
) -> None:
    """
    Remove user from RBAC policy in a ConfigMap.

    Args:
        k8s_client: Kubernetes client
        configmap_name: Name of the ConfigMap containing RBAC policy
        namespace: Namespace of the ConfigMap
        username: Username to remove from policy
    """

    try:
        rbac_cm = run_command_with_logging(
            logger,
            f"read {configmap_name} RBAC config",
            k8s_client.read_config_map,
            name=configmap_name,
            namespace=namespace,
        )
        current_policy = rbac_cm.data.get("policy.csv", "")

        if current_policy:
            new_policy = "\n".join(
                [
                    line
                    for line in current_policy.split("\n")
                    if f"g, {username}, " not in line
                ]
            )

            if new_policy != current_policy:
                run_command_with_logging(
                    logger,
                    f"update {configmap_name} RBAC policy to remove user '{username}'",
                    k8s_client.patch_config_map,
                    name=configmap_name,
                    namespace=namespace,
                    data={"policy.csv": new_policy},
                )
    except Exception as e:  # pylint: disable=broad-exception-caught
        logger.warning("Failed to update %s RBAC policy: %s", configmap_name, e)


def _remove_argocd_user(k8s_client: KubernetesClient, username: str) -> None:
    """
    Remove ArgoCD user from config and secret.

    Args:
        k8s_client: Kubernetes client
        username: Username to remove
    """

    logger.info("Removing ArgoCD user '%s'...", username)

    try:
        argocd_cm = run_command_with_logging(
            logger,
            "read ArgoCD config",
            k8s_client.read_config_map,
            name="argocd-cm",
            namespace=ARGOCD_NAMESPACE,
        )
        if argocd_cm.data and f"accounts.{username}" in argocd_cm.data:
            run_command_with_logging(
                logger,
                f"remove user '{username}' from ArgoCD config",
                k8s_client.patch_config_map,
                name="argocd-cm",
                namespace=ARGOCD_NAMESPACE,
                data={f"accounts.{username}": None},
            )
    except Exception as e:  # pylint: disable=broad-exception-caught
        logger.warning(
            "Failed to remove user from argocd-cm: %s (user may not exist)", e
        )

    try:
        run_command_with_logging(
            logger,
            f"remove user '{username}' from ArgoCD secret",
            k8s_client.patch_secret,
            name="argocd-secret",
            namespace=ARGOCD_NAMESPACE,
            data={f"accounts.{username}.password": None},
        )
    except Exception as e:  # pylint: disable=broad-exception-caught
        logger.warning(
            "Failed to remove user from argocd-secret: %s (user may not exist)", e
        )

    _remove_rbac_policy(k8s_client, "argocd-rbac-cm", ARGOCD_NAMESPACE, username)


def _remove_argo_workflows_user(k8s_client: KubernetesClient, username: str) -> None:
    """
    Remove Argo Workflows user from SSO secret.

    Args:
        k8s_client: Kubernetes client
        username: Username to remove
    """

    logger.info("Removing Argo Workflows user '%s'...", username)

    try:
        run_command_with_logging(
            logger,
            f"remove user '{username}' from Argo Workflows SSO",
            k8s_client.patch_secret,
            name="argo-server-sso",
            namespace=ARGO_NAMESPACE,
            data={
                f"accounts.{username}.enabled": None,
                f"accounts.{username}.password": None,
                f"accounts.{username}.tokens": None,
            },
        )
    except Exception as e:  # pylint: disable=broad-exception-caught
        logger.warning(
            "Failed to remove user from argo-server-sso: %s (user may not exist)", e
        )

    _remove_rbac_policy(k8s_client, "argo-server-rbac-config", ARGO_NAMESPACE, username)


def _remove_kubernetes_resources(k8s_client: KubernetesClient, username: str) -> None:
    """
    Remove Kubernetes resources associated with user.

    Args:
        k8s_client: Kubernetes client
        username: Username to remove resources for
    """

    logger.info("Removing Kubernetes resources for user '%s'...", username)

    resources = [
        ("service account", k8s_client.delete_service_account, username),
        ("token secret", k8s_client.delete_secret, f"{username}-token"),
        ("role", k8s_client.delete_role, f"{username}-workflows"),
        ("role binding", k8s_client.delete_role_binding, f"{username}-binding"),
        (
            "cluster role",
            k8s_client.delete_cluster_role,
            f"{username}-cluster-workflows",
        ),
        (
            "cluster role binding",
            k8s_client.delete_cluster_role_binding,
            f"{username}-cluster-binding",
        ),
    ]

    for resource_type, delete_func, resource_name in resources:
        try:
            kwargs = {"name": resource_name}
            if "cluster" not in resource_type:
                kwargs["namespace"] = ARGO_NAMESPACE

            run_command_with_logging(
                logger,
                f"delete {resource_type} '{resource_name}'",
                delete_func,
                **kwargs,
            )
        except Exception as e:  # pylint: disable=broad-exception-caught
            logger.warning("Failed to delete %s: %s (may not exist)", resource_type, e)


def delete_argo_user(username: str, force: bool = False) -> None:
    """
    Delete an Argo user and all associated resources.

    Removes user from ArgoCD, Argo Workflows, and all Kubernetes resources.

    Args:
        username: Username to delete
        force: Skip confirmation prompt

    Raises:
        KubernetesError: If user deletion fails
    """

    logger.info("Starting deletion of user '%s' and all associated resources", username)
    logger.warning("This will permanently remove the user and all their permissions")

    if not force:
        confirm = input(f"Are you sure you want to delete user '{username}'? (y/N): ")
        if confirm.lower() not in ["y", "yes"]:
            logger.info("User deletion cancelled")
            return

    k8s_client = KubernetesClient()

    _remove_argocd_user(k8s_client, username)
    _remove_argo_workflows_user(k8s_client, username)
    _remove_kubernetes_resources(k8s_client, username)

    log_success(logger, f"User '{username}' deletion process completed")
    logger.warning("Restart the servers to apply all changes:")
    logger.warning(
        "  ArgoCD: kubectl delete pod -n argocd -l app.kubernetes.io/name=argocd-server"
    )
    logger.warning("  Argo Workflows: kubectl delete pod -n argo -l app=argo-server")


def main() -> None:
    """
    Main entry point for argo user delete command.
    """

    parser = argparse.ArgumentParser(
        description="Delete an Argo user and all associated resources"
    )
    parser.add_argument("username", help="Username to delete")
    parser.add_argument(
        "--force",
        "-f",
        action="store_true",
        help="Skip confirmation prompt",
    )

    args = parser.parse_args()

    setup_kubeconfig()

    try:
        delete_argo_user(args.username, args.force)
    except KubernetesError as e:
        exit_with_error(logger, f"Kubernetes error: {e}")
    except KeyboardInterrupt:
        exit_with_error(logger, "User deletion cancelled", exc_info=False)
    except Exception as e:  # pylint: disable=broad-exception-caught
        exit_with_error(logger, f"Unexpected error: {e}")
