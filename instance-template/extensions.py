import os
import secrets
import subprocess

from jinja2.ext import Extension


class EnvVarExtension(Extension):
    """Provides access to environment variables in templates."""

    def __init__(self, environment):
        super(EnvVarExtension, self).__init__(environment)
        environment.globals["env"] = os.getenv


class GitExtension(Extension):
    """Provides Git repository information in templates."""

    def __init__(self, environment):
        super(GitExtension, self).__init__(environment)
        environment.globals["git_repo_url"] = self.__get_repo_url
        environment.globals["git_repo_branch"] = self.__get_repo_branch

    def __get_repo_url(self):
        try:
            command = ["git", "-C", ".", "config", "--get", "remote.origin.url"]
            result = subprocess.run(command, capture_output=True, text=True, check=True)
            return result.stdout.strip()
        except subprocess.CalledProcessError as e:
            print(f"Error executing Git command: {e.stderr.strip()}")
            return None
        except FileNotFoundError:
            print("Git command not found. Ensure Git is installed and in your PATH.")
            return None

    def __get_repo_branch(self):
        try:
            command = ["git", "-C", ".", "rev-parse", "--abbrev-ref", "HEAD"]
            result = subprocess.run(command, capture_output=True, text=True, check=True)
            return result.stdout.strip()
        except subprocess.CalledProcessError as e:
            print(f"Error executing Git command: {e.stderr.strip()}")
            print("Falling back to \"main\" branch.")
            return "main"
        except FileNotFoundError:
            print("Git command not found. Ensure Git is installed and in your PATH.")
            return "main"


class PasswordExtension(Extension):
    """Provides password generation in templates."""

    def __init__(self, environment):
        super(PasswordExtension, self).__init__(environment)
        environment.globals["generate_password"] = lambda: secrets.token_hex(24)


class StorageExtension(Extension):
    """Provides storage-related utilities for cloud providers."""

    # Mapping of storage types and regions to endpoint URLs
    ENDPOINT_FORMATS = {
        "spaces": "https://{region}.digitaloceanspaces.com",
        "s3": "",  # AWS S3 uses default endpoints (no custom URL needed)
    }

    def __init__(self, environment):
        super(StorageExtension, self).__init__(environment)
        environment.globals["storage_endpoint_url"] = self.__get_endpoint_url

    def __get_endpoint_url(self, storage_type, region):
        """
        Compute the storage endpoint URL based on storage type and region.
        """

        storage_type = storage_type.lower() if storage_type else "spaces"
        region = region if region else "nyc3"

        endpoint_format = self.ENDPOINT_FORMATS.get(storage_type)

        if endpoint_format is None:
            raise ValueError(f"Unknown storage type: {storage_type}")

        return endpoint_format.format(region=region)
