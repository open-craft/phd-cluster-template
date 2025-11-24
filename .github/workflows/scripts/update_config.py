"""
Update a Tutor instance config.yml with the given config.

Usage:
  python update_config.py \
    --config-file instances/<instance>/config.yml \
    --new-config <new_config_json_string>
"""

import argparse
import json
from pathlib import Path

import yaml


def merge_dicts(dict1, dict2):
    """Given two dict, merge the second dict into the first.

    The dicts can have arbitrary nesting.
    """
    for key in dict2:
        if isinstance(dict2[key], dict):
            if key in dict1 and key in dict2:
                merge_dicts(dict1[key], dict2[key])
            else:
                dict1[key] = dict2[key]
        else:
            # At scalar types, we iterate and merge the
            # current dict that we're on.
            dict1[key] = dict2[key]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Update config.yml file with given config"
    )
    parser.add_argument(
        "--config-file", required=True, help="Path to instance config.yml"
    )
    parser.add_argument(
        "--new-config",
        required=True,
        help="New config to me merged with existing instance config",
    )
    return parser.parse_args()


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

    data = load_yaml(config_path)
    merge_dicts(data, json.loads(args.new_config))
    save_yaml(config_path, data)


if __name__ == "__main__":
    main()
