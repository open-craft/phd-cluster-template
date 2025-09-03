import os
import secrets
import subprocess

from jinja2.ext import Extension


class EnvVarExtension(Extension):
    """
    Provides access to environment variables in templates.
    """

    def __init__(self, environment):
        super(EnvVarExtension, self).__init__(environment)
        environment.globals["env"] = os.getenv


class GitExtension(Extension):
    """
    Provides Git repository information in templates.
    """

    def __init__(self, environment):
        super(GitExtension, self).__init__(environment)
        environment.globals["git_repo_url"] = self.__get_repo_url
        environment.globals["git_repo_branch"] = self.__get_repo_branch

    def __find_git_directory(self):
        """
        Walk up the directory tree to find the .git directory.
        Returns the path to the git repository root, or None if not found.
        """

        current_dir = os.getcwd()
        check_dir = current_dir

        while check_dir != os.path.dirname(check_dir):
            if os.path.exists(os.path.join(check_dir, '.git')):
                return check_dir
            check_dir = os.path.dirname(check_dir)

        return None

    def __run_git_command(self, git_args):
        """
        Run a git command in the git repository directory.
        Returns stdout as a string, or None on error.
        """

        git_dir = self.__find_git_directory()
        if git_dir:
            command = ["git", "-C", git_dir] + git_args
        else:
            command = ["git", "-C", "."] + git_args

        try:
            result = subprocess.run(command, capture_output=True, text=True, check=True)
            return result.stdout.strip()
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            return None

    def __get_repo_url(self):
        """
        Get the Git repository URL, converting HTTPS to SSH format.
        """

        try:
            url = self.__run_git_command(["config", "--get", "remote.origin.url"])
            if not url:
                print("Error: Could not retrieve Git repository URL.")
                return ""

            if url.startswith("https://github.com/"):
                url = url.replace("https://github.com/", "git@github.com:")

            return url
        except Exception as e:
            print(f"Error getting Git repository URL: {e}")
            return ""

    def __get_repo_branch(self):
        """
        Get the current Git branch.
        """

        try:
            branch = self.__run_git_command(["rev-parse", "--abbrev-ref", "HEAD"])
            if not branch:
                print("Error: Could not retrieve Git branch. Falling back to \"main\".")
                return "main"
            return branch
        except Exception as e:
            print(f"Error getting Git branch: {e}. Falling back to \"main\".")
            return "main"


class PasswordExtension(Extension):
    """
    Provides password generation in templates.
    """

    def __init__(self, environment):
        super(PasswordExtension, self).__init__(environment)
        environment.globals["generate_password"] = lambda: secrets.token_hex(24)


class StorageExtension(Extension):
    """
    Provides storage-related utilities for cloud providers.
    """

    # Mapping of storage types and regions to endpoint URLs
    ENDPOINT_FORMATS = {
        "spaces": "https://{region}.digitaloceanspaces.com",
        "s3": "",  # AWS S3 uses default endpoints
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
