"""
Cluster create command.
"""

import argparse
from pathlib import Path

from cookiecutter.main import cookiecutter

from phd.cli.utils import exit_with_error
from phd.utils import get_logger, log_success

logger = get_logger(__name__)

DEFAULT_ENVIRONMENT = "production"
DEFAULT_SHORT_DESCRIPTION = "Kubernetes cluster to host Open edX instances"
DEFAULT_CLOUD_PROVIDER = "aws"
DEFAULT_HARMONY_MODULE_VERSION = "bfdcca60d62801acbf61e77f49de25889647b5ef"
DEFAULT_OPENCRAFT_MODULE_VERSION = "v1.0.1"
DEFAULT_PICASSO_VERSION = "main"
DEFAULT_TEMPLATE_VERSION = "main"
DEFAULT_GIT_ORGANIZATION = "open-craft"
DEFAULT_TEMPLATE_REPOSITORY = "https://github.com/open-craft/phd-cluster-template.git"


def create_cluster(  # pylint: disable=too-many-arguments,too-many-positional-arguments,too-many-locals
    cluster_name: str,
    cluster_domain: str,
    environment: str = DEFAULT_ENVIRONMENT,
    short_description: str = DEFAULT_SHORT_DESCRIPTION,
    cloud_provider: str = DEFAULT_CLOUD_PROVIDER,
    harmony_module_version: str = DEFAULT_HARMONY_MODULE_VERSION,
    opencraft_module_version: str = DEFAULT_OPENCRAFT_MODULE_VERSION,
    picasso_version: str = DEFAULT_PICASSO_VERSION,
    template_version: str = DEFAULT_TEMPLATE_VERSION,
    git_organization: str = DEFAULT_GIT_ORGANIZATION,
    git_repository: str = "",
    template_repository: str = DEFAULT_TEMPLATE_REPOSITORY,
    output_dir: str = ".",
) -> None:
    """
    Create a new cluster configuration using cookiecutter.

    Args:
        cluster_name: Name of the cluster (e.g., "PHD Production Cluster")
        cluster_domain: Domain for the cluster (e.g., "cluster.example.com")
        environment: Environment name (default: "production")
        short_description: Short description of the cluster
        cloud_provider: Cloud provider (aws or digitalocean)
        harmony_module_version: Harmony module version/commit hash
        opencraft_module_version: OpenCraft module version
        picasso_version: Picasso version
        template_version: PHD cluster template version
        git_organization: Git organization name
        git_repository: Git repository URL (if not provided, will be auto-generated)
        template_repository: Git URL of the cluster template repository
        output_dir: Directory where cluster config will be created

    Raises:
        Exception: If cookiecutter fails
    """

    logger.info("Creating cluster configuration for '%s'", cluster_name)

    cluster_slug = cluster_name.lower().replace(" ", "-").replace("_", "-")

    if not git_repository:
        git_repository = f"https://github.com/{git_organization}/phd-{cluster_slug}.git"

    output_path = Path(output_dir).resolve()
    output_path.mkdir(parents=True, exist_ok=True)

    # Use absolute path for local templates
    if template_repository.startswith((".", "/")):
        template_path = Path(template_repository).resolve()
        if template_path.is_dir():
            template_repository = str(template_path)
        elif template_path.name == "phd-cluster-template":
            cluster_template_path = template_path / "cluster-template"
            if cluster_template_path.is_dir():
                template_repository = str(cluster_template_path)

    logger.info("generate cluster configuration")
    logger.info("Using template repository: %s", template_repository)

    extra_context = {
        "environment": environment,
        "cluster_name": cluster_name,
        "cluster_slug": cluster_slug,
        "cluster_domain": cluster_domain,
        "short_description": short_description,
        "cloud_provider": cloud_provider,
        "harmony_module_version": harmony_module_version,
        "opencraft_module_version": opencraft_module_version,
        "picasso_version": picasso_version,
        "phd_cluster_template_version": template_version,
        "git_organization": git_organization,
        "git_repository": git_repository,
    }

    logger.debug("Template repository: %s", template_repository)
    logger.debug("Extra context: %s", extra_context)

    try:
        cookiecutter(
            template_repository,
            directory="cluster-template",
            output_dir=str(output_path),
            overwrite_if_exists=False,
            no_input=True,
            extra_context=extra_context,
        )
    except Exception as e:
        logger.error("Failed to generate cluster configuration: %s", e)
        raise

    log_success(
        logger, f"Cluster configuration created successfully for '{cluster_name}'"
    )
    logger.info("Cluster directory: %s/%s", output_path, cluster_slug)


def main() -> None:
    """
    Main entry point for cluster create command.
    """

    parser = argparse.ArgumentParser(description="Create a new cluster configuration")
    parser.add_argument(
        "cluster_name", help="Name of the cluster (e.g., 'PHD Production Cluster')"
    )
    parser.add_argument(
        "cluster_domain", help="Domain for the cluster (e.g., 'cluster.example.com')"
    )
    parser.add_argument(
        "--environment",
        default=DEFAULT_ENVIRONMENT,
        help=f"Environment name (default: {DEFAULT_ENVIRONMENT})",
    )
    parser.add_argument(
        "--short-description",
        default=DEFAULT_SHORT_DESCRIPTION,
        help=f"Short description of the cluster (default: '{DEFAULT_SHORT_DESCRIPTION}')",
    )
    parser.add_argument(
        "--cloud-provider",
        default=DEFAULT_CLOUD_PROVIDER,
        choices=["aws", "digitalocean"],
        help=f"Cloud provider (default: {DEFAULT_CLOUD_PROVIDER})",
    )
    parser.add_argument(
        "--harmony-module-version",
        default=DEFAULT_HARMONY_MODULE_VERSION,
        help=f"Harmony module version/commit hash (default: {DEFAULT_HARMONY_MODULE_VERSION})",
    )
    parser.add_argument(
        "--opencraft-module-version",
        default=DEFAULT_OPENCRAFT_MODULE_VERSION,
        help=f"OpenCraft module version (default: {DEFAULT_OPENCRAFT_MODULE_VERSION})",
    )
    parser.add_argument(
        "--picasso-version",
        default=DEFAULT_PICASSO_VERSION,
        help=f"Picasso version (default: {DEFAULT_PICASSO_VERSION})",
    )
    parser.add_argument(
        "--template-version",
        default=DEFAULT_TEMPLATE_VERSION,
        help=f"PHD cluster template version (default: {DEFAULT_TEMPLATE_VERSION})",
    )
    parser.add_argument(
        "--git-organization",
        default=DEFAULT_GIT_ORGANIZATION,
        help=f"Git organization name (default: {DEFAULT_GIT_ORGANIZATION})",
    )
    parser.add_argument(
        "--git-repository",
        default="",
        help="Git repository URL (if not provided, will be auto-generated)",
    )
    parser.add_argument(
        "--template-repository",
        default=DEFAULT_TEMPLATE_REPOSITORY,
        help=f"Git URL of the cluster template repository (default: {DEFAULT_TEMPLATE_REPOSITORY})",
    )
    parser.add_argument(
        "--output-dir",
        default=".",
        help="Directory where cluster config will be created (default: current directory)",
    )

    args = parser.parse_args()

    try:
        create_cluster(
            args.cluster_name,
            args.cluster_domain,
            args.environment,
            args.short_description,
            args.cloud_provider,
            args.harmony_module_version,
            args.opencraft_module_version,
            args.picasso_version,
            args.template_version,
            args.git_organization,
            args.git_repository,
            args.template_repository,
            args.output_dir,
        )
    except KeyboardInterrupt:
        exit_with_error(logger, "Cluster creation cancelled", exc_info=False)
    except Exception as e:  # pylint: disable=broad-exception-caught
        exit_with_error(logger, f"Unexpected error: {e}")
