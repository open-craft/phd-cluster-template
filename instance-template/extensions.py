import os
import subprocess

from jinja2.ext import Extension


class EnvVarExtension(Extension):
    def __init__(self, environment):
        super(EnvVarExtension, self).__init__(environment)
        environment.globals["env"] = os.getenv


class GitExtension(Extension):
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
