"""
Generate the Tutor env directory replicating Picasso's flow:
- Load PICASSO_EXTRA_COMMANDS from config.yml
- Execute the extra commands (or a default tutor config save) with TUTOR_ROOT set
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
from pathlib import Path
from typing import List, Mapping

import yaml


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate Tutor env directory (Picasso-like)"
    )
    parser.add_argument("--config-file", required=True, help="Path to config.yml")
    parser.add_argument(
        "--tutor-root",
        required=True,
        help="Path to Tutor root where env will be generated",
    )
    return parser.parse_args()


def load_config(config_path: Path) -> dict:
    with config_path.open("r", encoding="utf-8") as fp:
        return yaml.safe_load(fp)


def ensure_commands(commands) -> List[str]:
    if commands is None:
        return ["tutor config save"]
    if not isinstance(commands, list):
        raise SystemExit("PICASSO_EXTRA_COMMANDS must be a list")
    if not commands:
        return ["tutor config save"]
    return [str(cmd) for cmd in commands]


def main() -> None:
    args = parse_args()
    config_path = Path(args.config_file)
    tutor_root = Path(args.tutor_root)

    config = load_config(config_path)
    commands = ensure_commands(config.get("PICASSO_EXTRA_COMMANDS"))

    env = os.environ.copy()
    env["TUTOR_ROOT"] = str(tutor_root)

    env_dir = tutor_root / "env"
    shutil.rmtree(env_dir, ignore_errors=True)

    for cmd in commands:
        subprocess.run(cmd, check=True, env=env, shell=True, executable="/bin/bash")


if __name__ == "__main__":
    main()
