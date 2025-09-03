"""
Utility functions for PHD.
"""

import json
import logging
import os
import re
import shutil
import tempfile
from pathlib import Path

import phd
from phd.config import get_config
from phd.exceptions import CommandNotFoundError, ConfigurationError


class ColoredFormatter(logging.Formatter):
    """Custom formatter with colored output matching shell script format."""

    COLORS = {
        "DEBUG": "\033[30m",  # Grey
        "INFO": "\033[34m",  # Blue
        "WARNING": "\033[33m",  # Yellow
        "ERROR": "\033[31m",  # Red
        "CRITICAL": "\033[31m",  # Red
        "SUCCESS": "\033[32m",  # Green
        "RESET": "\033[0m",  # Reset
    }

    def format(self, record: logging.LogRecord) -> str:
        """Format log record with colors."""
        color = self.COLORS.get(record.levelname, self.COLORS["RESET"])
        reset = self.COLORS["RESET"]

        level_str = f"{color}[{record.levelname}]{reset}"
        level_padding = " " * (9 - len(record.levelname))

        return f"{level_str}{level_padding}{record.getMessage()}"


def get_logger(name: str) -> logging.Logger:
    """
    Get a configured logger instance with common configuration.

    Args:
        name: Logger name

    Returns:
        Configured logger
    """

    logger = logging.getLogger(name)

    if logger.handlers:
        return logger

    try:
        config = get_config()
        log_level = str(config.log_level).upper()
        log_file = str(config.log_file)
    except Exception:  # pylint: disable=broad-exception-caught
        log_level = "INFO"
        log_file = str(Path(tempfile.gettempdir()) / "phd.log")

    logger.setLevel(log_level)

    console_handler = logging.StreamHandler()
    console_handler.setFormatter(ColoredFormatter())
    logger.addHandler(console_handler)

    file_handler = logging.FileHandler(log_file)
    file_handler.setFormatter(
        logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
    )
    logger.addHandler(file_handler)

    return logger


def log_success(logger: logging.Logger, message: str) -> None:
    """
    Log a success message.

    Args:
        logger: Logger instance
        message: Success message
    """

    record = logger.makeRecord(
        logger.name,
        logging.INFO,
        "(success)",
        0,
        message,
        (),
        None,
    )

    record.levelname = "SUCCESS"
    logger.handle(record)


def check_env_var_set(var_name: str) -> None:
    """
    Check if an environment variable is set.

    Args:
        var_name: Environment variable name

    Raises:
        ConfigurationError: If the environment variable is not set
    """

    if not os.environ.get(var_name):
        raise ConfigurationError(f"Environment variable {var_name} is not set")


def check_command_installed(command: str) -> None:
    """
    Check if a command is installed and available.

    Args:
        command: Command name to check

    Raises:
        CommandNotFoundError: If the command is not found
    """

    if not shutil.which(command):
        raise CommandNotFoundError(f"{command} command is not installed")


def sanitize_username(username: str) -> str:
    """
    Sanitize a username to a single canonical form suitable for:
    - Kubernetes resource names (DNS-1123 subdomain)
    - Kubernetes secret/config keys (stricter subset also allowed)

    Rules:
    - Lowercase
    - Replace any character not in [a-z0-9.-] with '-'
    - Collapse multiple '-' into single '-', and multiple '.' into single '.'
    - Trim leading/trailing '-' or '.'
    - Raise ValueError if result is empty
    """

    lowered = username.lower()
    sanitized = re.sub(r"[^a-z0-9.-]", "-", lowered)
    sanitized = re.sub(r"-+", "-", sanitized)
    sanitized = re.sub(r"\.+", ".", sanitized)
    sanitized = sanitized.strip("-.")

    if not sanitized:
        raise ValueError("Username cannot be sanitized to a non-empty string")

    return sanitized


def detect_local_template(  # pylint: disable=too-many-locals,too-many-nested-blocks
    template_dir_name: str, logger: logging.Logger
) -> Path | None:
    """
    Detect if a local template directory exists.

    This function checks for local templates in two ways:
    1. Via package metadata (direct_url.json) for uvx --from /path/to/tooling installs
    2. Via current working directory traversal

    Args:
        template_dir_name: Name of the template directory (e.g., "cluster-template")
        logger: Logger instance for debug messages

    Returns:
        Path to the template directory if found, None otherwise
    """
    current_dir = Path.cwd()
    potential_local_template = None

    # First, check if the package is installed from a local directory
    # This handles the case where uvx --from /path/to/tooling is used
    try:
        phd_module_path = Path(phd.__file__).resolve().parent
        logger.debug("PHD module file: %s", phd.__file__)

        site_packages = phd_module_path.parent
        logger.debug("Site packages: %s", site_packages)

        for dist_info in site_packages.glob("phd-*.dist-info"):
            direct_url_file = dist_info / "direct_url.json"
            logger.debug("Checking for direct_url.json: %s", direct_url_file)
            if direct_url_file.exists():
                try:
                    with open(direct_url_file, "r", encoding="utf-8") as f:
                        direct_url_data = json.load(f)
                    url = direct_url_data.get("url", "")
                    logger.debug("Found direct_url: %s", url)

                    if url.startswith("file://"):
                        source_path = Path(url.replace("file://", ""))
                        logger.debug("Source path from direct_url: %s", source_path)

                        repo_root = source_path.parent
                        template_path = repo_root / template_dir_name
                        logger.debug("Checking template path: %s", template_path)

                        if (template_path / "cookiecutter.json").exists():
                            potential_local_template = template_path
                            logger.debug(
                                "Detected local template from package metadata: %s",
                                potential_local_template,
                            )
                            break
                except (json.JSONDecodeError, OSError) as e:
                    logger.debug("Failed to read direct_url.json: %s", e)
    except (AttributeError, OSError) as e:
        logger.debug("Failed to detect local template from package location: %s", e)

    # If not found via package path, check if we're in the repository directory
    if not potential_local_template:
        for parent in [current_dir] + list(current_dir.parents):
            template_path = parent / template_dir_name
            if (template_path / "cookiecutter.json").exists():
                potential_local_template = template_path
                logger.debug(
                    "Detected local template from working directory: %s",
                    potential_local_template,
                )
                break

    return potential_local_template
