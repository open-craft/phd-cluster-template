#!/usr/bin/env python3
"""
Post-generation hook for cookiecutter template.
Checks for tofu or terraform installation and runs fmt on the infrastructure directory.
"""

import json
import shutil
import subprocess
from pathlib import Path


def check_command_exists(command):
    """Check if a command exists in the system PATH."""

    try:
        subprocess.run(
            [command, "--version"], capture_output=True, check=True, timeout=10
        )
        return True
    except (
        subprocess.CalledProcessError,
        FileNotFoundError,
        subprocess.TimeoutExpired,
    ):
        return False


def create_git_repo():
    """Create a git repository in the current directory."""

    try:
        subprocess.run(["git", "init"], check=True)
        subprocess.run(["git", "branch", "-M", "main"], check=True)
        subprocess.run(["git", "remote", "add", "origin", "{{ cookiecutter.git_repository }}"], check=True)
        subprocess.run(["git", "add", "."], check=True)
        subprocess.run(["git", "commit", "-m", "Initial commit"], check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error creating git repository: {e}")
        return False
    return True


def cleanup_infrastructure_directories(cloud_provider):
    """Remove all infrastructure-* directories except the selected one, then rename it to infrastructure."""

    project_dir = Path.cwd()

    infra_dir = project_dir / "infrastructure"
    cloud_provider_dir = project_dir / f"infrastructure-{cloud_provider}"

    # Find all infrastructure-* directories
    for item in project_dir.iterdir():
        if (
            item.is_dir()
            and item.name.startswith("infrastructure-")
            and item != cloud_provider_dir
        ):
            print(f"Removing {item.name} directory")
            shutil.rmtree(item)

    # Move the selected cloud provider directory to infrastructure
    if cloud_provider_dir.exists():
        if infra_dir.exists():
            shutil.rmtree(infra_dir)
        shutil.move(cloud_provider_dir, infra_dir)
        print(f"Moved {cloud_provider_dir.name} to infrastructure")


def cleanup_install_directory():
    """Keep .install/.gitkeep but remove all other files in .install directory."""

    project_dir = Path.cwd()
    install_dir = project_dir / ".install"

    if install_dir.exists():
        # Keep .gitkeep file, remove everything else
        gitkeep_file = install_dir / ".gitkeep"
        for item in install_dir.iterdir():
            if item != gitkeep_file:
                if item.is_file():
                    print(f"Removing {item.name} from .install directory")
                    item.unlink()
                elif item.is_dir():
                    print(f"Removing {item.name} directory from .install")
                    shutil.rmtree(item)


def run_fmt_command(command, infrastructure_dir):
    """Run the fmt command for the given infrastructure directory."""

    try:
        print(f"Running {command} fmt on {infrastructure_dir}...")
        result = subprocess.run(
            [command, "fmt"],
            cwd=infrastructure_dir,
            capture_output=True,
            text=True,
            timeout=60,
        )

        if result.returncode == 0:
            print(f"{command} fmt completed successfully")
            if result.stdout:
                print(f"Output: {result.stdout}")
        else:
            print(f"{command} fmt completed with warnings/errors")
            if result.stderr:
                print(f"Errors: {result.stderr}")
            if result.stdout:
                print(f"Output: {result.stdout}")

    except subprocess.TimeoutExpired:
        print(f"{command} fmt timed out after 60 seconds")
    except Exception as e:
        print(f"Error running {command} fmt: {e}")


def main():
    """Main function to clean up infrastructure directories and run fmt."""

    project_dir = Path.cwd()
    cloud_provider = "{{ cookiecutter.cloud_provider }}"

    # Clean up the irrelevant infrastructure directory first
    cleanup_infrastructure_directories(cloud_provider)

    # Clean up .install directory (keep .gitkeep, remove other files)
    cleanup_install_directory()

    infrastructure_dir = project_dir / "infrastructure"

    if not infrastructure_dir.exists():
        print(
            f"Infrastructure directory {infrastructure_dir} not found, skipping formatting"
        )
        return

    print("Checking for infrastructure formatting tools...")

    if check_command_exists("tofu"):
        print("Found tofu, using tofu fmt")
        run_fmt_command("tofu", infrastructure_dir)
    elif check_command_exists("terraform"):
        print("Found terraform, using terraform fmt")
        run_fmt_command("terraform", infrastructure_dir)
    else:
        print("Neither tofu nor terraform found in PATH")
        print("Skipping automatic code formatting...")
        print("Please install one of these tools to format your infrastructure code:")
        print("  - tofu: https://opentofu.org/docs/intro/install/")
        print("  - terraform: https://developer.hashicorp.com/terraform/downloads")

    # We only gather the context that may be important after generation for
    # other scripts to run.
    Path(Path.cwd() / "context.json").write_text(
        json.dumps(
            {
                "cluster_domain": "{{ cookiecutter.cluster_domain }}",
                "environment": "{{ cookiecutter.environment }}",
            },
            indent=2,
        )
    )

    create_git_repo()

if __name__ == "__main__":
    main()
