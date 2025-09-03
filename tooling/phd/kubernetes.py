"""
Utility functions to support working with Kubernetes.
"""

import io
import subprocess
from typing import Dict, Optional

import requests
import yaml
from jinja2 import Template
from kubernetes import client, config

from phd.exceptions import KubernetesError, ManifestError
from phd.utils import get_logger


class KubernetesClient:
    """
    Kubernetes client with encapsulated API access.
    """

    def __init__(self):
        """
        Initialize the Kubernetes client.
        """

        config.load_kube_config()

        self._api_client = client.ApiClient()
        self._core_v1 = client.CoreV1Api()
        self._apps_v1 = client.AppsV1Api()
        self._rbac_v1 = client.RbacAuthorizationV1Api()
        self._logger = get_logger(__name__)

    def __get_manifest_from_url(self, url: str) -> str:
        """
        Get a Kubernetes manifest from a URL.

        Args:
            url: The URL to the manifest.

        Returns:
            Manifest content as string

        Raises:
            ManifestError: If fetching the manifest fails
        """

        self._logger.debug("Fetching manifest from %s", url)

        try:
            res = requests.get(url, timeout=30)
            res.raise_for_status()
            return res.text
        except Exception as e:
            raise ManifestError(f"Failed to fetch manifest from {url}: {e}") from e

    def render_manifest(self, manifest: str, variables: Dict[str, str]) -> str:
        """
        Render a manifest template with Jinja2.

        Replaces {{ VAR }} placeholders with values from variables dict.

        Args:
            manifest: Manifest template string
            variables: Dictionary of variable name -> value mappings

        Returns:
            Rendered manifest string

        Raises:
            ManifestError: If rendering fails
        """

        self._logger.debug("Rendering manifest with variables: %s", variables)

        try:
            return Template(manifest).render(**variables)
        except Exception as e:
            raise ManifestError(f"Failed to render manifest: {e}") from e

    def apply_manifest(
        self,
        yaml_manifest: str,
        namespace: Optional[str] = "default",
        variables: Optional[Dict[str, str]] = None,
    ) -> None:
        """
        Apply a Kubernetes manifest to the cluster using the Python API.

        Args:
            yaml_manifest: The manifest YAML to apply
            namespace: The namespace to apply the manifest to
            variables: Optional dictionary of variables for Jinja2 template rendering

        Raises:
            KubernetesError: If applying the manifest fails
            ManifestError: If rendering the manifest fails
        """

        if variables:
            yaml_manifest = self.render_manifest(yaml_manifest, variables)

        documents = yaml.safe_load_all(io.StringIO(yaml_manifest))
        for doc in filter(lambda x: x, documents):
            self._logger.debug("Applying document: %s", doc)

            doc["metadata"] = doc.get("metadata", {})
            doc["metadata"]["namespace"] = namespace

            api_version = doc.get("apiVersion", "")
            self._logger.debug("Processing resource with apiVersion: %s", api_version)

            self._logger.debug("Using kubectl apply for resource")
            self._apply_resource_with_kubectl(doc, namespace)

    def _apply_resource_with_kubectl(self, doc: dict, namespace: str) -> None:
        """
        Apply Kubernetes resources using kubectl apply.

        This method uses kubectl apply which properly handles both creating
        and updating resources, ensuring manifests are applied idempotently.

        Args:
            doc: The resource document to apply
            namespace: The namespace to apply to

        Raises:
            KubernetesError: If applying the resource fails
        """
        try:
            yaml_content = yaml.dump(doc, default_flow_style=False)
            result = subprocess.run(
                ["kubectl", "apply", "-f", "-", "-n", namespace],
                input=yaml_content,
                text=True,
                capture_output=True,
                check=True,
            )

            resource_name = doc.get("metadata", {}).get("name", "unknown")
            resource_kind = doc.get("kind", "unknown")

            if "configured" in result.stdout:
                self._logger.info(
                    "%s '%s' updated successfully",
                    resource_kind,
                    resource_name,
                )
            elif "created" in result.stdout:
                self._logger.info(
                    "%s '%s' created successfully",
                    resource_kind,
                    resource_name,
                )
            elif "unchanged" in result.stdout:
                self._logger.debug(
                    "%s '%s' unchanged",
                    resource_kind,
                    resource_name,
                )

        except subprocess.CalledProcessError as e:
            resource_name = doc.get("metadata", {}).get("name", "unknown")
            resource_kind = doc.get("kind", "unknown")
            raise KubernetesError(
                f"Failed to apply {resource_kind} '{resource_name}': {e.stderr}"
            ) from e
        except Exception as e:
            raise KubernetesError(f"Unexpected error applying resource: {e}") from e

    def apply_manifest_from_url(
        self,
        url: str,
        namespace: Optional[str] = "default",
        variables: Optional[Dict[str, str]] = None,
    ) -> None:
        """
        Apply a Kubernetes manifest from a URL to the cluster.

        Args:
            url: The URL to the manifest
            namespace: The namespace to apply the manifest to
            variables: Optional dictionary of variables for Jinja2 template rendering

        Raises:
            ManifestError: If fetching the manifest fails
            KubernetesError: If applying the manifest fails
        """

        manifest = self.__get_manifest_from_url(url)
        self.apply_manifest(manifest, namespace, variables)

    def create_namespace(self, namespace: str) -> None:
        """
        Create a Kubernetes namespace using the API.

        Args:
            namespace: The namespace name to create

        Raises:
            KubernetesError: If creating the namespace fails
        """

        self._logger.debug("Creating namespace %s", namespace)

        metadata = client.V1ObjectMeta(name=namespace)
        namespace_obj = client.V1Namespace(metadata=metadata)

        try:
            self._core_v1.create_namespace(body=namespace_obj)
        except client.exceptions.ApiException as e:
            if e.status != 409:
                raise KubernetesError(f"Failed to create namespace: {e}") from e
            self._logger.warning("Namespace %s already exists", namespace)
        except Exception as e:
            raise KubernetesError(f"Failed to create namespace: {e}") from e

    def patch_secret(
        self,
        name: str,
        namespace: str,
        data: Optional[Dict] = None,
        string_data: Optional[Dict] = None,
    ) -> None:
        """
        Patch a Kubernetes secret.

        Args:
            name: Secret name
            namespace: Namespace containing the secret
            data: Base64-encoded data to patch
            string_data: Plain text string data to patch

        Raises:
            KubernetesError: If patching fails
        """

        self._logger.debug("Patching secret '%s' in namespace '%s'", name, namespace)

        body = {}
        if data:
            body["data"] = data
        if string_data:
            body["stringData"] = string_data

        try:
            self._core_v1.patch_namespaced_secret(
                name=name, namespace=namespace, body=body
            )
        except Exception as e:
            raise KubernetesError(
                f"Failed to patch secret '{name}' in namespace '{namespace}': {e}"
            ) from e

    def patch_config_map(self, name: str, namespace: str, data: Dict) -> None:
        """
        Patch a Kubernetes config map.

        Args:
            name: ConfigMap name
            namespace: Namespace containing the config map
            data: Data to patch

        Raises:
            KubernetesError: If patching fails
        """

        self._logger.debug(
            "Patching config map '%s' in namespace '%s'", name, namespace
        )

        try:
            self._core_v1.patch_namespaced_config_map(
                name=name, namespace=namespace, body={"data": data}
            )
        except Exception as e:
            raise KubernetesError(
                f"Failed to patch config map '{name}' in namespace '{namespace}': {e}"
            ) from e

    def read_config_map(self, name: str, namespace: str) -> client.V1ConfigMap:
        """
        Read a Kubernetes config map.

        Args:
            name: ConfigMap name
            namespace: Namespace containing the config map

        Returns:
            ConfigMap object

        Raises:
            KubernetesError: If reading fails
        """

        self._logger.debug(
            "Reading config map '%s' from namespace '%s'", name, namespace
        )

        try:
            return self._core_v1.read_namespaced_config_map(
                name=name, namespace=namespace
            )
        except Exception as e:
            raise KubernetesError(
                f"Failed to read config map '{name}' from namespace '{namespace}': {e}"
            ) from e

    def read_secret(self, name: str, namespace: str) -> client.V1Secret:
        """
        Read a Kubernetes secret.

        Args:
            name: Secret name
            namespace: Namespace containing the secret

        Returns:
            Secret object

        Raises:
            KubernetesError: If reading fails
        """

        self._logger.debug("Reading secret '%s' from namespace '%s'", name, namespace)

        try:
            return self._core_v1.read_namespaced_secret(name=name, namespace=namespace)
        except Exception as e:
            raise KubernetesError(
                f"Failed to read secret '{name}' from namespace '{namespace}': {e}"
            ) from e

    def delete_service_account(self, name: str, namespace: str) -> None:
        """
        Delete a Kubernetes service account.

        Args:
            name: Service account name
            namespace: Namespace containing the service account

        Raises:
            KubernetesError: If deletion fails (except 404)
        """

        self._logger.debug(
            "Deleting service account '%s' in namespace '%s'", name, namespace
        )

        try:
            self._core_v1.delete_namespaced_service_account(
                name=name, namespace=namespace
            )
        except client.exceptions.ApiException as e:
            if e.status != 404:
                raise KubernetesError(
                    f"Failed to delete service account '{name}' in namespace '{namespace}': {e}"
                ) from e

            self._logger.debug(
                "Service account '%s' not found in namespace '%s'", name, namespace
            )
        except Exception as e:
            raise KubernetesError(
                f"Failed to delete service account '{name}' in namespace '{namespace}': {e}"
            ) from e

    def delete_secret(self, name: str, namespace: str) -> None:
        """
        Delete a Kubernetes secret.

        Args:
            name: Secret name
            namespace: Namespace containing the secret

        Raises:
            KubernetesError: If deletion fails (except 404)
        """

        self._logger.debug("Deleting secret '%s' in namespace '%s'", name, namespace)

        try:
            self._core_v1.delete_namespaced_secret(name=name, namespace=namespace)
        except client.exceptions.ApiException as e:
            if e.status != 404:
                raise KubernetesError(
                    f"Failed to delete secret '{name}' in namespace '{namespace}': {e}"
                ) from e

            self._logger.debug(
                "Secret '%s' not found in namespace '%s'", name, namespace
            )
        except Exception as e:
            raise KubernetesError(
                f"Failed to delete secret '{name}' in namespace '{namespace}': {e}"
            ) from e

    def delete_role(self, name: str, namespace: str) -> None:
        """
        Delete a Kubernetes role.

        Args:
            name: Role name
            namespace: Namespace containing the role

        Raises:
            KubernetesError: If deletion fails (except 404)
        """

        self._logger.debug("Deleting role '%s' in namespace '%s'", name, namespace)

        try:
            self._rbac_v1.delete_namespaced_role(name=name, namespace=namespace)
        except client.exceptions.ApiException as e:
            if e.status != 404:
                raise KubernetesError(
                    f"Failed to delete role '{name}' in namespace '{namespace}': {e}"
                ) from e

            self._logger.debug("Role '%s' not found in namespace '%s'", name, namespace)
        except Exception as e:
            raise KubernetesError(
                f"Failed to delete role '{name}' in namespace '{namespace}': {e}"
            ) from e

    def delete_role_binding(self, name: str, namespace: str) -> None:
        """
        Delete a Kubernetes role binding.

        Args:
            name: Role binding name
            namespace: Namespace containing the role binding

        Raises:
            KubernetesError: If deletion fails (except 404)
        """

        self._logger.debug(
            "Deleting role binding '%s' in namespace '%s'", name, namespace
        )

        try:
            self._rbac_v1.delete_namespaced_role_binding(name=name, namespace=namespace)
        except client.exceptions.ApiException as e:
            if e.status != 404:
                raise KubernetesError(
                    f"Failed to delete role binding '{name}' in namespace '{namespace}': {e}"
                ) from e

            self._logger.debug(
                "Role binding '%s' not found in namespace '%s'", name, namespace
            )
        except Exception as e:
            raise KubernetesError(
                f"Failed to delete role binding '{name}' in namespace '{namespace}': {e}"
            ) from e

    def delete_cluster_role(self, name: str) -> None:
        """
        Delete a Kubernetes cluster role.

        Args:
            name: Cluster role name

        Raises:
            KubernetesError: If deletion fails (except 404)
        """

        self._logger.debug("Deleting cluster role '%s'", name)

        try:
            self._rbac_v1.delete_cluster_role(name=name)
        except client.exceptions.ApiException as e:
            if e.status != 404:
                raise KubernetesError(
                    f"Failed to delete cluster role '{name}': {e}"
                ) from e

            self._logger.debug("Cluster role '%s' not found", name)
        except Exception as e:
            raise KubernetesError(f"Failed to delete cluster role '{name}': {e}") from e

    def delete_cluster_role_binding(self, name: str) -> None:
        """
        Delete a Kubernetes cluster role binding.

        Args:
            name: Cluster role binding name

        Raises:
            KubernetesError: If deletion fails (except 404)
        """

        self._logger.debug("Deleting cluster role binding '%s'", name)

        try:
            self._rbac_v1.delete_cluster_role_binding(name=name)
        except client.exceptions.ApiException as e:
            if e.status != 404:
                raise KubernetesError(
                    f"Failed to delete cluster role binding '{name}': {e}"
                ) from e

            self._logger.debug("Cluster role binding '%s' not found", name)
        except Exception as e:
            raise KubernetesError(
                f"Failed to delete cluster role binding '{name}': {e}"
            ) from e
