"""
Update a Tutor instance config.yml with the built image reference.

Usage:
  python update_config_image.py \
    --config-file instances/<instance>/config.yml \
    --service <openedx|mfe> \
    --image-name <repo/name or repo/name:tag> \
    --image-tag <tag>

Behavior:
  - If image-name already contains a ':', it is used as-is.
  - Otherwise, ':<image-tag>' is appended (image-tag must be provided).
  - The service name is mapped to the config key to update.
"""

import argparse
from pathlib import Path

import yaml

SERVICE_TO_CONFIG_KEY = {
    "openedx": "DOCKER_IMAGE_OPENEDX",
    "mfe": "MFE_DOCKER_IMAGE",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Update config.yml image reference based on service"
    )
    parser.add_argument(
        "--config-file", required=True, help="Path to instance config.yml"
    )
    parser.add_argument(
        "--service", required=True, help="Service name, e.g. 'openedx' or 'mfe'"
    )
    parser.add_argument(
        "--image-name", required=True, help="Image repository/name, optionally with tag"
    )
    parser.add_argument(
        "--image-tag",
        required=False,
        default="",
        help="Image tag (used if name has no tag)",
    )
    return parser.parse_args()


def compute_full_image(image_name: str, image_tag: str) -> str:
    """
    Compute the full image reference with tag.

    An image is considered already tagged if:
    - It contains '@' (digest), e.g., 'repo/image@sha256:...'
    - The last path segment (after the last '/') contains ':', e.g., 'repo/image:tag'

    This correctly handles registry ports like 'registry:5000/repo/image' which should
    still get a tag appended.
    """
    # Check for digest (e.g., repo/image@sha256:...)
    if "@" in image_name:
        return image_name

    # Check if the last segment (image name) contains a tag
    # Split by '/' and check the last part
    parts = image_name.split("/")
    last_segment = parts[-1]

    # If the last segment contains ':', it's already tagged
    if ":" in last_segment:
        return image_name

    if not image_tag:
        raise SystemExit("--image-tag must be provided when --image-name has no tag")

    return f"{image_name}:{image_tag}"


def resolve_config_key(service: str) -> str:
    key = SERVICE_TO_CONFIG_KEY.get(service)

    if not key:
        supported = ", ".join(sorted(SERVICE_TO_CONFIG_KEY))
        raise SystemExit(f"Unsupported service '{service}'. Supported: {supported}")

    return key


def load_yaml(path: Path) -> dict:
    if not path.exists():
        return {}

    with path.open("r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}

        if not isinstance(data, dict):
            raise SystemExit("Root of YAML must be a mapping (object)")

        return data


def save_yaml(path: Path, data: dict) -> None:
    with path.open("w", encoding="utf-8") as f:
        yaml.safe_dump(data, f, sort_keys=False)


def main() -> None:
    args = parse_args()
    config_path = Path(args.config_file)
    full_image = compute_full_image(args.image_name, args.image_tag)
    key = resolve_config_key(args.service)

    data = load_yaml(config_path)
    data[key] = full_image
    save_yaml(config_path, data)


if __name__ == "__main__":
    main()
