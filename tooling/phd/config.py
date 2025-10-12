"""
Configuration defined for PHD split across configuration layers.
"""

import json
import tempfile
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class PHDBaseSettings(BaseSettings):
    """
    Base settings for PHD.
    """

    model_config = SettingsConfigDict(
        env_prefix="PHD_",
        extra="forbid",
        frozen=True,
    )


class ClusterConfig(PHDBaseSettings):
    """
    Cluster configuration.
    """

    # Cluster domain
    cluster_domain: str = Field(
        # pylint: disable=unnecessary-lambda
        default_factory=lambda: ClusterConfig._load_cluster_domain_from_context(),
        description="Cluster domain (e.g., example.com)",
    )

    # Environment
    environment: str = Field(
        default="production", description="Environment (production, staging, etc.)"
    )

    # Argo versions
    argocd_version: str = Field(
        default="stable", description="ArgoCD version to install"
    )
    argo_workflows_version: str = Field(
        default="stable", description="Argo Workflows version to install"
    )

    # OpenCraft manifests configuration
    opencraft_manifests_version: str = Field(
        default="main", description="OpenCraft manifests version"
    )

    # Instance configuration
    instances_directory: str = Field(
        default="instances", description="Directory where instances are stored"
    )

    # Admin password configuration (optional - will be generated if not provided)
    argo_admin_password: str = Field(
        default="", description="Argo admin password (plaintext)"
    )

    @staticmethod
    def _load_cluster_domain_from_context() -> str:
        """
        Load cluster domain from context.json file in the current directory.

        Returns:
            Cluster domain from context.json, or empty string if not found
        """
        try:
            context_file = Path.cwd() / "context.json"
            if context_file.exists():
                with open(context_file, "r", encoding="utf-8") as f:
                    context = json.load(f)
                    return context.get("cluster_domain", "")
        except (json.JSONDecodeError, KeyError, OSError):
            pass
        return ""

    @property
    def opencraft_manifests_url(self) -> str:
        """
        Get the OpenCraft manifests URL.
        """

        return f"https://raw.githubusercontent.com/open-craft/phd-cluster-template/{self.opencraft_manifests_version}/manifests"

    @property
    def argocd_install_url(self) -> str:
        """
        Get the ArgoCD installation URL.
        """

        return f"https://raw.githubusercontent.com/argoproj/argo-cd/{self.argocd_version}/manifests/install.yaml"

    @property
    def argo_workflows_install_url(self) -> str:
        """
        Get the Argo Workflows installation URL.
        """

        return f"https://raw.githubusercontent.com/argoproj/argo-workflows/{self.argo_workflows_version}/manifests/install.yaml"


class InstanceConfig(PHDBaseSettings):
    """
    Instance configuration.
    """


class ProviderConfig(PHDBaseSettings):
    """
    Provider configuration.
    """


class StorageConfig(PHDBaseSettings):
    """
    Storage configuration.
    """


class PicassoConfig(PHDBaseSettings):
    """
    Picasso configuration.
    """


class Config(PHDBaseSettings):
    """
    Main configuration class.
    """

    # Global configuration
    log_level: str = Field(default="INFO", description="Log level")
    log_file: str = Field(
        # pylint: disable=unnecessary-lambda
        default_factory=lambda: str(Path(tempfile.gettempdir()) / "phd.log"),
        description="Log file (defaults to temp directory)",
    )
    log_format: str = Field(
        default="%(asctime)s - %(levelname)s - %(message)s",
        description="Log format",
    )

    # Configuration layers
    cluster: ClusterConfig = Field(
        default_factory=ClusterConfig, description="Cluster configuration"
    )
    instance: InstanceConfig = Field(
        default_factory=InstanceConfig, description="Instance configuration"
    )
    provider: ProviderConfig = Field(
        default_factory=ProviderConfig, description="Provider configuration"
    )
    storage: StorageConfig = Field(
        default_factory=StorageConfig, description="Storage configuration"
    )
    picasso: PicassoConfig = Field(
        default_factory=PicassoConfig, description="Picasso configuration"
    )


_CONFIG_INSTANCE = None


def get_config() -> Config:
    """
    Get the global configuration instance (lazy initialization).

    Returns:
        Config: The global configuration
    """

    global _CONFIG_INSTANCE  # pylint: disable=global-statement

    if _CONFIG_INSTANCE is None:
        _CONFIG_INSTANCE = Config()

    return _CONFIG_INSTANCE
