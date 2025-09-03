"""
PHD CLI.
"""

from .argo_install import main as argo_install_main
from .argo_user_create import main as argo_user_create_main
from .argo_user_delete import main as argo_user_delete_main
from .argo_user_update import main as argo_user_update_main
from .cluster_create import main as cluster_create_main
from .instance_create import main as instance_create_main
from .instance_delete import main as instance_delete_main

__all__ = [
    "argo_install_main",
    "cluster_create_main",
    "instance_create_main",
    "instance_delete_main",
    "argo_user_create_main",
    "argo_user_delete_main",
    "argo_user_update_main",
]
