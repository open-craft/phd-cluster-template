import json
import os
import sys
from pathlib import Path

import requests
from jsonschema import ValidationError, validate

ROOT_DIR = Path(os.path.dirname(__file__))
SCHEMA_FILE_NAME = "cookiecutter.schema.json"

# Look for schema file in the template directory
# When cookiecutter runs, it copies the template to a temp directory
# The hooks directory is in the template, so the schema file should be in the same directory as hooks
TEMPLATE_SCHEMA_FILE = (ROOT_DIR / ".." / SCHEMA_FILE_NAME).absolute()
SCHEMA_FILE = TEMPLATE_SCHEMA_FILE

# If the schema file doesn't exist in the temp directory, try to find it in the original template
if not SCHEMA_FILE.exists():
    # Try to find the original template directory
    # Look for the template directory in common locations
    possible_paths = [
        Path("/Users/gabor/Developer/opencraft/phd-cluster-template") / SCHEMA_FILE_NAME,
        Path.cwd() / "phd-cluster-template" / SCHEMA_FILE_NAME,
        Path.cwd() / SCHEMA_FILE_NAME,
    ]

    for path in possible_paths:
        if path.exists():
            SCHEMA_FILE = path
            break

SCHEMA_URL = f"https://raw.githubusercontent.com/open-craft/phd-cluster-template/main/{SCHEMA_FILE_NAME}"


def download_schema_file():
    """Download the schema file from the repository."""

    response = requests.get(SCHEMA_URL)
    response.raise_for_status()
    return response.json()


def validate_input(context):
    """Validate the input against the schema."""

    schema = (
        json.loads(SCHEMA_FILE.read_text())
        if SCHEMA_FILE.exists()
        else download_schema_file()
    )

    try:
        validate(instance=context, schema=schema)
    except ValidationError as e:
        print(f"\nERROR: Invalid input: {e.message}")
        sys.exit(1)


def persist_context(context):
    """Persist the context to a file."""

    with open(f"{context['cluster_slug']}/context.json", "w") as f:
        json.dump(context, f)


def main():
    """Main function to validate the input."""

    # Gather user input from cookiecutter context. This is necessary to be done manually,
    # because cookiecutter does not support dynamic variables.
    context = {
        "$schema": str(SCHEMA_FILE),
        "cluster_name": "{{ cookiecutter.cluster_name }}",
        "cluster_slug": "{{ cookiecutter.cluster_slug }}",
        "cluster_domain": "{{ cookiecutter.cluster_slug.lower().replace('_', '-') }}.example.com",
        "environment": "{{ cookiecutter.environment }}",
        "short_description": "{{ cookiecutter.short_description }}",
        "cloud_provider": "{{ cookiecutter.cloud_provider }}",
        "harmony_module_version": "{{ cookiecutter.harmony_module_version }}",
        "picasso_version": "{{ cookiecutter.picasso_version }}",
        "buildkit_parallelism": "{{ cookiecutter.buildkit_parallelism }}",
    }

    validate_input(context)
    persist_context(context)


if __name__ == "__main__":
    main()
