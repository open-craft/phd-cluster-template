"""
Apply IMAGE_OVERRIDES to both config.yml and an existing env directory.

Expected override format (one per line):
    service=image_name:image_tag
"""

from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path
from typing import Iterable, Tuple


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Apply image overrides to config.yml and env directory"
    )
    parser.add_argument("--config-file", required=True, help="Path to config.yml")
    parser.add_argument("--env-dir", required=True, help="Path to env directory")
    parser.add_argument(
        "--image-overrides",
        required=True,
        help="Newline-separated overrides in format service=image_name:image_tag",
    )
    return parser.parse_args()


def _load_module(module_path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


def split_image_spec(image_spec: str) -> Tuple[str, str]:
    """
    Split image_spec on the last ':' to get image_name and image_tag.
    Mirrors the previous shell logic (may require image_spec to include a tag).
    """
    if ":" not in image_spec:
        raise SystemExit(f"image override must include a tag: {image_spec}")
    image_name, image_tag = image_spec.rsplit(":", 1)
    return image_name, image_tag


def iter_overrides(image_overrides: str) -> Iterable[Tuple[str, str, str]]:
    """
    Yield tuples of (service, image_name, image_tag) for each non-empty line.
    """
    for raw_line in image_overrides.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if "=" not in line:
            raise SystemExit(f"invalid IMAGE_OVERRIDES entry (missing '='): {line}")
        service, image_spec = line.split("=", 1)
        service = service.strip()
        image_spec = image_spec.strip()
        image_name, image_tag = split_image_spec(image_spec)
        yield service, image_name, image_tag


def main() -> None:
    args = parse_args()
    config_path = Path(args.config_file)
    env_dir = Path(args.env_dir)

    root = Path(__file__).resolve().parent
    update_config_path = root / "update_config_image.py"
    update_env_path = root / "update_env_image_refs.py"

    update_config = _load_module(update_config_path, "update_config_image")
    update_env = _load_module(update_env_path, "update_env_image_refs")

    for service, image_name, image_tag in iter_overrides(args.image_overrides):
        # Update config.yml
        update_config.main = getattr(update_config, "main", None)  # type: ignore[attr-defined]
        update_config.compute_full_image = getattr(  # type: ignore[attr-defined]
            update_config, "compute_full_image", None
        )
        update_config_key = getattr(update_config, "resolve_config_key", None)
        if not update_config_key:
            raise SystemExit("update_config_image.py missing resolve_config_key")
        config_data = update_config.load_yaml(config_path)  # type: ignore[attr-defined]
        key = update_config_key(service)
        full_image = update_config.compute_full_image(image_name, image_tag)  # type: ignore[attr-defined]
        config_data[key] = full_image
        update_config.save_yaml(config_path, config_data)  # type: ignore[attr-defined]

        # Patch env directory
        update_env.patch_env(env_dir, image_name, image_tag)


if __name__ == "__main__":
    main()
