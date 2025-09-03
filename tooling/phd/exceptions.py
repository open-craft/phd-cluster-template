"""
Custom exceptions for PHD.
"""


class PHDException(Exception):
    """Base exception for all PHD errors."""


class ConfigurationError(PHDException):
    """Raised when configuration is invalid or missing."""


class KubernetesError(PHDException):
    """Raised when Kubernetes operations fail."""


class CommandNotFoundError(PHDException):
    """Raised when a required command is not found."""


class PasswordError(PHDException):
    """Raised when password operations fail."""


class ManifestError(PHDException):
    """Raised when manifest operations fail."""
