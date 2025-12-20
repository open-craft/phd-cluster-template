"""
Extract TUTOR_VERSION from config.yml and set it as a GitHub Actions environment variable.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path

import yaml


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract TUTOR_VERSION from config.yml"
    )
    parser.add_argument("--config-file", required=True, help="Path to config.yml")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    config_path = Path(args.config_file)

    with config_path.open("r", encoding="utf-8") as fp:
        config = yaml.safe_load(fp)

    tutor_version = config.get("TUTOR_VERSION")
    if not tutor_version:
        raise SystemExit("TUTOR_VERSION is required in config.yml")

    github_env = os.environ.get("GITHUB_ENV")
    if not github_env:
        raise SystemExit("GITHUB_ENV environment variable is not set")

    with open(github_env, "a", encoding="utf-8") as env_file:
        env_file.write(f"TUTOR_VERSION={tutor_version}\n")


if __name__ == "__main__":
    main()
