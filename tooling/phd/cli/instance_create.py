"""
Instance create command.
"""

import argparse
import os
import subprocess
from pathlib import Path

import yaml
from cookiecutter.main import cookiecutter

from phd.cli.argo_install import install_argo_workflows
from phd.cli.utils import exit_with_error, run_command_with_logging
from phd.config import get_config
from phd.exceptions import KubernetesError
from phd.kubeconfig import setup_kubeconfig
from phd.kubernetes import KubernetesClient
from phd.utils import detect_local_template, get_logger, log_success

logger = get_logger(__name__)

ARGO_NAMESPACE = "argo"
WORKFLOW_TIMEOUT = 300
WORKFLOW_CHECK_INTERVAL = 5
DEFAULT_PLATFORM_NAME = None
DEFAULT_TUTOR_VERSION = None
DEFAULT_EDX_PLATFORM_VERSION = None
DEFAULT_EDX_PLATFORM_REPOSITORY = None
DEFAULT_TEMPLATE_REPOSITORY = "https://github.com/open-craft/phd-cluster-template.git"
DEFAULT_TEMPLATE_VERSION = None


def _ensure_argo_workflows_installed() -> None:
    """
    Ensure Argo Workflows is installed before creating workflows.

    Raises:
        KubernetesError: If Argo Workflows installation fails
    """
    logger.info("Ensuring Argo Workflows is installed...")

    try:
        config = get_config()
        install_argo_workflows(config.cluster)
        logger.info("Argo Workflows is ready")
    except Exception as e:
        logger.error("Failed to ensure Argo Workflows is installed: %s", e)
        raise KubernetesError(f"Argo Workflows installation failed: {e}") from e


def _generate_instance_config(  # pylint: disable=too-many-positional-arguments,too-many-branches
    instance_name: str,
    template_repository: str | None,
    template_version: str | None,
    platform_name: str | None,
    edx_platform_repository: str | None,
    edx_platform_version: str | None,
    tutor_version: str | None,
    instances_dir: Path,
    cluster_domain: str,
    environment: str,
) -> None:
    """
    Generate instance configuration using cookiecutter.

    Args:
        instance_name: Name of the instance to create
        template_repository: Git URL of the instance template repository
        template_version: Version of the instance template to use
        platform_name: Display name for the platform
        edx_platform_repository: Git URL of the edx-platform repository
        edx_platform_version: Version/branch of edx-platform to use
        tutor_version: Version of Tutor to use
        instances_dir: Directory where instances are stored
        cluster_domain: Cluster domain name
        environment: Environment name (production, staging, etc.)

    Raises:
        Exception: If cookiecutter fails
    """

    # Detect local template if using default GitHub repository
    if template_repository == DEFAULT_TEMPLATE_REPOSITORY:
        potential_local_template = detect_local_template("instance-template", logger)
        if potential_local_template:
            logger.info(
                "Detected local template repository, using: %s",
                potential_local_template,
            )
            template_repository = str(potential_local_template)

    if template_repository and template_repository.startswith((".", "/")):
        template_path = Path(template_repository).resolve()
        if template_path.is_dir():
            template_repository = str(template_path)
        elif template_path.name == "phd-cluster-template":
            instance_template_path = template_path / "instance-template"
            if instance_template_path.is_dir():
                template_repository = str(instance_template_path)

    logger.info(
        "Bootstrapping instance '%s' from template '%s'",
        instance_name,
        template_repository,
    )

    # Set environment variables for cookiecutter template
    # The template uses env() function which reads from os.environ
    os.environ["PHD_CLUSTER_DOMAIN"] = cluster_domain
    os.environ["PHD_ENVIRONMENT"] = environment

    extra_context = {
        "instance_name": instance_name,
        "platform_repository": edx_platform_repository,
        "platform_name": platform_name,
        "platform_version": edx_platform_version,
        "tutor_version": tutor_version,
    }

    if template_repository:
        extra_context["template_repository"] = template_repository

    if template_version:
        extra_context["template_version"] = template_version

    if platform_name:
        extra_context["platform_name"] = platform_name

    if edx_platform_repository:
        extra_context["platform_repository"] = edx_platform_repository

    if edx_platform_version:
        extra_context["platform_version"] = edx_platform_version

    if tutor_version:
        extra_context["tutor_version"] = tutor_version

    cookiecutter_kwargs = {
        "checkout": template_version,
        "output_dir": str(instances_dir),
        "overwrite_if_exists": False,
        "no_input": True,
        "extra_context": {
            "instance_name": instance_name,
            "platform_repository": edx_platform_repository,
            "platform_name": platform_name,
            "platform_version": edx_platform_version,
            "tutor_version": tutor_version,
        },
    }

    if not template_repository.startswith("/"):
        cookiecutter_kwargs["directory"] = "instance-template"

    run_command_with_logging(
        logger,
        "generate instance configuration",
        cookiecutter,
        template_repository,
        **cookiecutter_kwargs,
    )

    log_success(logger, f"Instance '{instance_name}' configuration generated")


def _setup_instance_rbac(
    k8s_client: KubernetesClient,
    instance_name: str,
    manifests_url: str,
) -> None:
    """
    Configure RBAC for instance namespace.

    Args:
        k8s_client: Kubernetes client
        instance_name: Name of the instance (used as namespace)
        manifests_url: Base URL for manifest files
    """

    run_command_with_logging(
        logger,
        f"configure instance RBAC for namespace '{instance_name}'",
        k8s_client.apply_manifest_from_url,
        f"{manifests_url}/openedx-instance-rbac.yml",
        instance_name,
        {"PHD_INSTANCE_NAME": instance_name},
    )

    log_success(logger, f"Instance RBAC configured for namespace '{instance_name}'")


def _wait_for_workflow_completion(  # pylint: disable=duplicate-code
    instance_name: str,
    workflow_name: str,
    timeout: int = WORKFLOW_TIMEOUT,
) -> bool:
    """
    Wait for an Argo Workflow to complete and check its status.

    Args:
        instance_name: Namespace where the workflow runs
        workflow_name: Name of the workflow to wait for
        timeout: Maximum time to wait in seconds

    Returns:
        True if workflow succeeded, False otherwise
    """

    logger.debug("Waiting for workflow '%s' to complete...", workflow_name)

    try:
        subprocess.run(
            [
                "kubectl",
                "wait",
                "--for=condition=Completed",
                f"workflow/{workflow_name}",
                "-n",
                instance_name,
                f"--timeout={timeout}s",
            ],
            check=True,
            capture_output=True,
            text=True,
        )

        result = subprocess.run(
            [
                "kubectl",
                "get",
                f"workflow/{workflow_name}",
                "-n",
                instance_name,
                "-o",
                "jsonpath={.status.phase}",
            ],
            check=True,
            capture_output=True,
            text=True,
        )

        status = result.stdout.strip()

        if status == "Succeeded":
            logger.debug("Workflow '%s' succeeded", workflow_name)
            return True

        logger.warning("Workflow '%s' failed with status: %s", workflow_name, status)
        return False

    except subprocess.CalledProcessError:
        logger.warning("Workflow '%s' timed out or failed", workflow_name)
        return False


def _create_provision_workflows(  # pylint: disable=duplicate-code
    k8s_client: KubernetesClient,
    instance_name: str,
    manifests_url: str,
    instance_config: dict,
) -> None:
    """
    Create and execute provision workflows for MySQL, MongoDB, and Storage.

    Args:
        k8s_client: Kubernetes client
        instance_name: Name of the instance
        manifests_url: Base URL for manifest files
        instance_config: Configuration dictionary for the instance

    Raises:
        KubernetesError: If workflows fail
    """

    logger.info("Creating parameterized workflows for instance '%s'", instance_name)

    workflows = [
        (
            "MySQL",
            "phd-mysql-provision-workflow.yml",
            f"mysql-provision-{instance_name}",
        ),
        (
            "MongoDB",
            "phd-mongodb-provision-workflow.yml",
            f"mongodb-provision-{instance_name}",
        ),
        (
            "Storage",
            "phd-storage-provision-workflow.yml",
            f"storage-provision-{instance_name}",
        ),
    ]

    for workflow_type, manifest_file, workflow_name in workflows:
        run_command_with_logging(
            logger,
            f"apply {workflow_type} provision workflow",
            k8s_client.apply_manifest_from_url,
            f"{manifests_url}/{manifest_file}",
            instance_name,
            instance_config,
        )

    logger.info("Waiting for provision workflows to complete...")
    all_succeeded = True

    for workflow_type, _, workflow_name in workflows:
        if not _wait_for_workflow_completion(instance_name, workflow_name):
            all_succeeded = False

    subprocess.run(
        ["kubectl", "get", "workflows", "-n", instance_name],
        check=False,
    )

    if not all_succeeded:
        raise KubernetesError(
            f"Workflows may have failed for instance '{instance_name}'"
        )

    logger.warning("Cleaning up workflows to save resources...")
    for _, _, workflow_name in workflows:
        subprocess.run(
            ["kubectl", "delete", "workflow", workflow_name, "-n", instance_name],
            check=False,
            capture_output=True,
        )

    log_success(
        logger,
        f"Workflows created and completed successfully for instance '{instance_name}'",
    )


def _create_argocd_application(instance_name: str, instances_dir: Path) -> None:
    """
    Create ArgoCD Application for the instance.

    Args:
        instance_name: Name of the instance
        instances_dir: Directory where instances are stored

    Raises:
        FileNotFoundError: If application.yml not found
        subprocess.CalledProcessError: If kubectl apply fails
    """

    logger.info("Creating ArgoCD Application for instance '%s'", instance_name)

    application_file = instances_dir / instance_name / "application.yml"

    if not application_file.exists():
        raise FileNotFoundError(
            f"ArgoCD Application file not found: {application_file}"
        )

    run_command_with_logging(
        logger,
        f"create ArgoCD Application for instance '{instance_name}'",
        subprocess.run,
        ["kubectl", "apply", "-f", str(application_file)],
        check=True,
    )

    log_success(
        logger,
        f"ArgoCD Application created successfully for instance '{instance_name}'",
    )


def create_instance(  # pylint: disable=too-many-positional-arguments
    instance_name: str,
    template_repository: str | None = DEFAULT_TEMPLATE_REPOSITORY,
    template_version: str | None = DEFAULT_TEMPLATE_VERSION,
    platform_name: str | None = DEFAULT_PLATFORM_NAME,
    edx_platform_repository: str | None = DEFAULT_EDX_PLATFORM_REPOSITORY,
    edx_platform_version: str | None = DEFAULT_EDX_PLATFORM_VERSION,
    tutor_version: str | None = DEFAULT_TUTOR_VERSION,
) -> None:
    """
    Create a new OpenEdX instance with all required resources.

    This orchestrates:
    - Generating instance configuration from template
    - Creating namespace
    - Setting up RBAC
    - Running provision workflows
    - Creating ArgoCD application

    Args:
        instance_name: Name of the instance to create
        template_repository: Git URL of the instance template repository
        template_version: Version of the instance template to use
        platform_name: Display name for the platform
        edx_platform_repository: Git URL of the edx-platform repository
        edx_platform_version: Version/branch of edx-platform to use
        tutor_version: Version of Tutor to use

    Raises:
        KubernetesError: If instance creation fails
        FileNotFoundError: If required files not found
        subprocess.CalledProcessError: If external commands fail
    """

    config = get_config()
    k8s_client = KubernetesClient()
    instances_dir = Path(
        # pylint: disable=no-member
        config.cluster.instances_directory
    )

    instances_dir.mkdir(parents=True, exist_ok=True)

    _generate_instance_config(
        instance_name,
        template_repository,
        template_version,
        platform_name,
        edx_platform_repository,
        edx_platform_version,
        tutor_version,
        instances_dir,
        config.cluster.cluster_domain,  # pylint: disable=no-member
        config.cluster.environment,  # pylint: disable=no-member
    )

    run_command_with_logging(
        logger,
        f"create namespace '{instance_name}'",
        k8s_client.create_namespace,
        instance_name,
    )

    manifests_url = config.cluster.opencraft_manifests_url  # pylint: disable=no-member

    _setup_instance_rbac(k8s_client, instance_name, manifests_url)
    _ensure_argo_workflows_installed()

    config_file = instances_dir / instance_name / "config.yml"
    if not config_file.exists():
        raise FileNotFoundError(f"Instance config file not found: {config_file}")

    with open(config_file, "r", encoding="utf-8") as f:
        config_data = yaml.safe_load(f)

    instance_config = {
        "PHD_INSTANCE_NAME": instance_name,
        "PHD_PLATFORM_NAME": platform_name,
        "PHD_EDX_PLATFORM_REPOSITORY": edx_platform_repository,
        "PHD_EDX_PLATFORM_VERSION": edx_platform_version,
        "PHD_TUTOR_VERSION": tutor_version,
        # MySQL parameters
        "PHD_INSTANCE_MYSQL_DATABASE": config_data.get("MYSQL_DATABASE", ""),
        "PHD_INSTANCE_MYSQL_USERNAME": config_data.get("MYSQL_USERNAME", ""),
        "PHD_INSTANCE_MYSQL_PASSWORD": config_data.get("MYSQL_PASSWORD", ""),
        "PHD_INSTANCE_MYSQL_HOST": config_data.get("MYSQL_HOST"),
        "PHD_INSTANCE_MYSQL_PORT": config_data.get("MYSQL_PORT"),
        "PHD_INSTANCE_MYSQL_ROOT_USER": os.getenv("PHD_MYSQL_ROOT_USER", "root"),
        "PHD_INSTANCE_MYSQL_ROOT_PASSWORD": os.getenv(
            "PHD_MYSQL_ROOT_PASSWORD", config_data.get("MYSQL_PASSWORD", "")
        ),
        # MongoDB DigitalOcean parameters
        "PHD_INSTANCE_MONGODB_DATABASE": config_data.get("MONGODB_DATABASE", ""),
        "PHD_INSTANCE_MONGODB_USERNAME": config_data.get("MONGODB_USERNAME", ""),
        "PHD_INSTANCE_MONGODB_PASSWORD": config_data.get("MONGODB_PASSWORD", ""),
        "PHD_INSTANCE_MONGODB_PROVIDER": os.getenv("PHD_MONGODB_PROVIDER", ""),
        "PHD_INSTANCE_MONGODB_CLUSTER_ID": os.getenv("PHD_MONGODB_CLUSTER_ID", ""),
        "PHD_INSTANCE_DIGITALOCEAN_TOKEN": os.getenv("PHD_DIGITALOCEAN_TOKEN", ""),
        # MongoDB Atlas parameters
        "PHD_INSTANCE_ATLAS_PUBLIC_KEY": os.getenv("PHD_ATLAS_PUBLIC_KEY", ""),
        "PHD_INSTANCE_ATLAS_PRIVATE_KEY": os.getenv("PHD_ATLAS_PRIVATE_KEY", ""),
        "PHD_INSTANCE_ATLAS_PROJECT_ID": os.getenv("PHD_ATLAS_PROJECT_ID", ""),
        "PHD_INSTANCE_ATLAS_CLUSTER_NAME": os.getenv("PHD_ATLAS_CLUSTER_NAME", ""),
        # Storage parameters
        "PHD_INSTANCE_STORAGE_BUCKET_NAME": config_data.get("STORAGE_BUCKET_NAME", ""),
        "PHD_INSTANCE_STORAGE_TYPE": config_data.get("STORAGE_TYPE"),
        "PHD_INSTANCE_STORAGE_REGION": config_data.get("STORAGE_REGION"),
        "PHD_INSTANCE_STORAGE_ENDPOINT_URL": config_data.get(
            "STORAGE_ENDPOINT_URL", ""
        ),
        "PHD_INSTANCE_STORAGE_ACCESS_KEY_ID": os.getenv(
            "PHD_STORAGE_ACCESS_KEY_ID", ""
        ),
        "PHD_INSTANCE_STORAGE_SECRET_ACCESS_KEY": os.getenv(
            "PHD_STORAGE_SECRET_ACCESS_KEY", ""
        ),
        "PHD_INSTANCE_STORAGE_MAKE_PUBLIC": os.getenv(
            "PHD_STORAGE_MAKE_PUBLIC", "false"
        ),
    }

    _create_provision_workflows(
        k8s_client, instance_name, manifests_url, instance_config
    )

    _create_argocd_application(instance_name, instances_dir)

    log_success(logger, f"Instance '{instance_name}' created successfully")


def main() -> None:
    """
    Main entry point for instance create command.
    """

    parser = argparse.ArgumentParser(description="Create a new OpenEdX instance")
    parser.add_argument("instance_name", help="Name of the instance to create")
    parser.add_argument(
        "--template-repository",
        default=DEFAULT_TEMPLATE_REPOSITORY,
        help=f"Git URL of the instance template repository (default: {DEFAULT_TEMPLATE_REPOSITORY})",
    )
    parser.add_argument(
        "--template-version",
        default=DEFAULT_TEMPLATE_VERSION,
        help=f"Version of the instance template to use (default: {DEFAULT_TEMPLATE_VERSION})",
    )
    parser.add_argument(
        "--platform-name",
        default="My Open edX Instance",
        help="Display name for the platform (default: 'My Open edX Instance')",
    )
    parser.add_argument(
        "--edx-platform-repository",
        default=DEFAULT_EDX_PLATFORM_REPOSITORY,
        help=f"Git URL of the edx-platform repository (default: {DEFAULT_EDX_PLATFORM_REPOSITORY})",
    )
    parser.add_argument(
        "--edx-platform-version",
        default=DEFAULT_EDX_PLATFORM_VERSION,
        help=f"Version/branch of edx-platform to use (default: {DEFAULT_EDX_PLATFORM_VERSION})",
    )
    parser.add_argument(
        "--tutor-version",
        default=DEFAULT_TUTOR_VERSION,
        help=f"Version of Tutor to use (default: {DEFAULT_TUTOR_VERSION})",
    )

    args = parser.parse_args()

    setup_kubeconfig()

    try:
        create_instance(
            args.instance_name,
            args.template_repository,
            args.platform_name,
            args.edx_platform_repository,
            args.edx_platform_version,
            args.tutor_version,
        )
    except FileNotFoundError as e:
        exit_with_error(logger, f"File not found: {e}", exc_info=False)
    except subprocess.CalledProcessError as e:
        exit_with_error(logger, f"Command failed: {e}")
    except KubernetesError as e:
        exit_with_error(logger, f"Kubernetes error: {e}")
    except KeyboardInterrupt:
        exit_with_error(logger, "Instance creation cancelled", exc_info=False)
    except Exception as e:  # pylint: disable=broad-exception-caught
        exit_with_error(logger, f"Unexpected error: {e}")
