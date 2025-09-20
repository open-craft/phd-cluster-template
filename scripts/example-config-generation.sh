#!/bin/env bash

# Example script demonstrating config generation usage

set -uo pipefail

# Source the phd-commands.sh for the config generation functions
source "$(dirname "${BASH_SOURCE[0]}")/phd-commands.sh"

echo "=== PHD Config Generation Example ==="
echo

# Example 1: Generate a single config from template with config file
echo "1. Generating instance config from template with production config..."
phd_generate_config \
    "templates/instance-config.yml.template" \
    "generated/instance-config.yml" \
    "configs/production.env"

echo

# Example 2: Generate ArgoCD application config
echo "2. Generating ArgoCD application config..."
phd_generate_config \
    "templates/argocd-application.yml.template" \
    "generated/argocd-application.yml" \
    "configs/production.env"

echo

# Example 3: Generate all configs in batch
echo "3. Generating all configs in batch..."
phd_generate_configs_batch \
    "templates/" \
    "generated/" \
    "configs/production.env"

echo

# Example 4: Validate generated configs
echo "4. Validating generated configs..."
phd_validate_config "generated/instance-config.yml"
phd_validate_config "generated/argocd-application.yml"

echo
echo "=== Example completed ==="
echo "Generated files are in the 'generated/' directory"
