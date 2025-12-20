"""
Patch image references inside an existing Tutor env directory without regenerating it.

Usage:
  python update_env_image_refs.py \
    --env-dir instances/<instance>/env \
    --image-name repo/name[:tag|@digest] \
    --image-tag tag_if_missing
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Iterable, List, Tuple


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Patch image references in an existing env directory"
    )
    parser.add_argument(
        "--env-dir", required=True, help="Path to the env directory to patch"
    )
    parser.add_argument(
        "--image-name",
        required=True,
        help="Full image name (registry/namespace/name[:tag|@digest])",
    )
    parser.add_argument(
        "--image-tag",
        required=False,
        default="",
        help="Image tag to append when image-name is not already tagged",
    )
    return parser.parse_args()


def compute_full_image(image_name: str, image_tag: str) -> str:
    """
    Ensure the image has a tag or digest.

    Rules (matching update_config_image.py):
    - If the name already contains '@' (digest), return as-is.
    - If the last segment already contains ':', return as-is (tag present).
    - Otherwise append ':<tag>', requiring image_tag to be non-empty.
    """
    if "@" in image_name:
        return image_name

    last_segment = image_name.split("/")[-1]
    if ":" in last_segment:
        return image_name

    if not image_tag:
        raise SystemExit("--image-tag must be provided when --image-name has no tag")

    return f"{image_name}:{image_tag}"


def strip_tag_or_digest(image_name: str) -> str:
    """
    Remove tag or digest from the last segment of the image name.
    Keeps registry (with port) and path prefixes intact.
    Examples:
    - ghcr.io/org/app:tag -> ghcr.io/org/app
    - registry:5000/app@sha256:abc -> registry:5000/app
    """
    if "@" in image_name:
        base, _digest = image_name.split("@", 1)
        return base

    parts = image_name.split("/")
    last = parts[-1]
    if ":" in last:
        last = last.split(":", 1)[0]
    parts[-1] = last
    return "/".join(parts)


def iter_env_yaml_files(env_dir: Path) -> Iterable[Path]:
    """Yield all .yml/.yaml files under env_dir."""
    return sorted(
        list(env_dir.rglob("*.yml")) + list(env_dir.rglob("*.yaml")),
        key=lambda p: str(p),
    )


def patch_file(path: Path, base_image: str, full_image: str) -> bool:
    """
    Replace image lines that reference base_image (with any tag/digest) with full_image.
    Returns True if the file was modified.
    """
    content = path.read_text(encoding="utf-8").splitlines()
    changed = False

    # Match: [indent]image: <base_image>[:oldtag|@digest][#comment]
    pattern = re.compile(
        rf"^(\s*image:\s*)"
        rf"({re.escape(base_image)}(?:[:@][^\s#]+)?)"
        rf"(\s*(#.*)?)$"
    )

    new_lines: List[str] = []
    for line in content:
        match = pattern.match(line)
        if match:
            prefix, _old_image, suffix, _comment = match.groups()
            new_lines.append(f"{prefix}{full_image}{suffix}")
            changed = True
        else:
            new_lines.append(line)

    if changed:
        path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
    return changed


def patch_env(env_dir: Path, image_name: str, image_tag: str) -> Tuple[int, List[Path]]:
    """
    Patch all YAML files under env_dir.
    Returns (files_changed_count, changed_paths).
    """
    if not env_dir.exists():
        raise SystemExit(f"env directory not found: {env_dir}")
    if not env_dir.is_dir():
        raise SystemExit(f"env path is not a directory: {env_dir}")

    full_image = compute_full_image(image_name, image_tag)
    base_image = strip_tag_or_digest(full_image)

    changed_paths: List[Path] = []
    for path in iter_env_yaml_files(env_dir):
        if patch_file(path, base_image, full_image):
            changed_paths.append(path)

    return len(changed_paths), changed_paths


def main() -> None:
    args = parse_args()
    env_dir = Path(args.env_dir)

    changed_count, changed_paths = patch_env(env_dir, args.image_name, args.image_tag)

    if changed_count == 0:
        print(f"No image references updated under {env_dir}", file=sys.stderr)
    else:
        updated = ", ".join(str(p.relative_to(env_dir)) for p in changed_paths)
        print(f"Updated {changed_count} file(s): {updated}")


if __name__ == "__main__":
    main()
