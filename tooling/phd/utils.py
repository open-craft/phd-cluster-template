"""
Utility functions for PHD.
"""

import logging
import os
import shutil
import tempfile
from pathlib import Path

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
