"""
Argo install commands for ArgoCD and Argo Workflows.
"""

import argparse
import subprocess

from phd.cli.utils import exit_with_error, run_command_with_logging
from phd.config import ClusterConfig, get_config
from phd.exceptions import (
    CommandNotFoundError,
    ConfigurationError,
    KubernetesError,
    ManifestError,
    PasswordError,
)
from phd.kubeconfig import setup_kubeconfig
from phd.kubernetes import KubernetesClient
from phd.password import bcrypt_password, get_password_mtime, resolve_plaintext_password
from phd.utils import get_logger, log_success

logger = get_logger(__name__)


def _apply_argo_workflows_template(url: str, namespace: str) -> None:
    """
    Apply an Argo Workflows template using kubectl.

    Args:
        url: URL of the template manifest
        namespace: Namespace to apply to

    Raises:
        KubernetesError: If applying the template fails
    """
    try:
        result = subprocess.run(
            ["kubectl", "apply", "-f", url, "-n", namespace],
            capture_output=True,
            text=True,
            check=False,
        )

        if result.returncode != 0:
            if not ("already exists" in result.stderr or "409" in result.stderr):
                raise KubernetesError(
                    f"Failed to apply Argo Workflows template: {result.stderr}"
                )

            logger.warning("Template already exists, skipping creation")

    except subprocess.CalledProcessError as e:
        raise KubernetesError(f"Failed to apply Argo Workflows template: {e}") from e
    except Exception as e:
        raise KubernetesError(
            f"Unexpected error applying Argo Workflows template: {e}"
        ) from e


def _install_argo_workflows_templates(cluster_config: ClusterConfig) -> None:
    """
    Install Argo Workflows templates for provisioning/deprovisioning.

    Args:
        cluster_config: Cluster configuration
    """
    manifests_url = cluster_config.opencraft_manifests_url

    templates = [
        "phd-mysql-provision-template.yml",
        "phd-mongodb-provision-template.yml",
        "phd-storage-provision-template.yml",
        "phd-mysql-deprovision-template.yml",
        "phd-mongodb-deprovision-template.yml",
        "phd-storage-deprovision-template.yml",
    ]

    for template in templates:
        template_name = template.replace(".yml", "").replace("-template", "")
        run_command_with_logging(
            logger,
            f"install {template_name} template",
            _apply_argo_workflows_template,
            f"{manifests_url}/{template}",
            "argo",
        )

    log_success(logger, "Argo Workflows templates installed successfully")


def install_argo_workflows(cluster_config: ClusterConfig) -> None:
    """
    Install Argo Workflows in the Kubernetes cluster.

    Args:
        cluster_config: Cluster configuration with Argo Workflows settings

    Raises:
        CommandNotFoundError: If required commands are not installed
        ConfigurationError: If required configuration is missing
        KubernetesError: If Kubernetes operations fail
        ManifestError: If manifest operations fail
    """

    k8s = KubernetesClient()

    run_command_with_logging(
        logger,
        "create Argo Workflows namespace",
        k8s.create_namespace,
        "argo",
    )

    run_command_with_logging(
        logger,
        "install Argo Workflows core components",
        k8s.apply_manifest_from_url,
        cluster_config.argo_workflows_install_url,
        "argo",
    )

    run_command_with_logging(
        logger,
        "create workflow-executor token in argo namespace",
        k8s.apply_manifest,
        """apiVersion: v1
kind: Secret
metadata:
  name: workflow-executor-token
  namespace: argo
  annotations:
    kubernetes.io/service-account.name: workflow-executor
type: kubernetes.io/service-account-token""",
        "argo",
    )

    _install_argo_workflows_templates(cluster_config)

    log_success(logger, "Argo Workflows installed successfully")


def install_argocd(cluster_config: ClusterConfig) -> None:
    """
    Install ArgoCD in the Kubernetes cluster.

    Args:
        cluster_config: Cluster configuration with ArgoCD settings

    Raises:
        CommandNotFoundError: If required commands are not installed
        ConfigurationError: If required configuration is missing
        KubernetesError: If Kubernetes operations fail
        ManifestError: If manifest operations fail
        PasswordError: If password operations fail
    """

    k8s = KubernetesClient()

    generated_password = not cluster_config.argo_admin_password
    plaintext_password = resolve_plaintext_password(cluster_config.argo_admin_password)

    run_command_with_logging(
        logger,
        "create ArgoCD namespace",
        k8s.create_namespace,
        "argocd",
    )

    run_command_with_logging(
        logger,
        "install ArgoCD core components",
        k8s.apply_manifest_from_url,
        cluster_config.argocd_install_url,
        "argocd",
    )

    run_command_with_logging(
        logger,
        "ensure base ArgoCD configmap",
        k8s.apply_manifest_from_url,
        f"{cluster_config.opencraft_manifests_url}/argocd-base-config.yml",
        "argocd",
    )

    run_command_with_logging(
        logger,
        "configure ArgoCD RBAC roles",
        k8s.apply_manifest_from_url,
        f"{cluster_config.opencraft_manifests_url}/argocd-rbac-config.yml",
        "argocd",
    )

    run_command_with_logging(
        logger,
        "configure ArgoCD ingress",
        k8s.apply_manifest_from_url,
        f"{cluster_config.opencraft_manifests_url}/argocd-ingress.yml",
        "argocd",
        {
            "PHD_CLUSTER_DOMAIN": cluster_config.cluster_domain,
        },
    )

    run_command_with_logging(
        logger,
        "configure ArgoCD admin password",
        k8s.apply_manifest_from_url,
        f"{cluster_config.opencraft_manifests_url}/argocd-admin-password.yml",
        "argocd",
        {
            "PHD_CLUSTER_DOMAIN": cluster_config.cluster_domain,
            "PHD_ARGO_ADMIN_PASSWORD_BCRYPT": bcrypt_password(plaintext_password),
            "PHD_ARGOCD_ADMIN_PASSWORD_MTIME": get_password_mtime(),
        },
    )

    if generated_password:
        logger.warning(
            "Generated Argo admin password (store securely): %s", plaintext_password
        )

    log_success(logger, "ArgoCD installed successfully")


def main():
    """
    Main entry point for argo install command.
    """

    parser = argparse.ArgumentParser(
        description="Install ArgoCD and Argo Workflows in a Kubernetes cluster"
    )
    parser.add_argument(
        "--argocd-only",
        action="store_true",
        help="Install only ArgoCD",
    )
    parser.add_argument(
        "--workflows-only",
        action="store_true",
        help="Install only Argo Workflows",
    )

    args = parser.parse_args()

    setup_kubeconfig()

    try:
        config = get_config()
        install_both = not args.argocd_only and not args.workflows_only

        if install_both or args.argocd_only:
            logger.info("Installing ArgoCD...")
            install_argocd(config.cluster)

        if install_both or args.workflows_only:
            logger.info("Installing Argo Workflows...")
            install_argo_workflows(config.cluster)
    except (
        CommandNotFoundError,
        ConfigurationError,
        KubernetesError,
        ManifestError,
        PasswordError,
    ) as e:
        exit_with_error(logger, f"Installation failed: {e}")
    except Exception as e:  # pylint: disable=broad-exception-caught
        exit_with_error(logger, f"Unexpected error: {e}", exc_info=False)
