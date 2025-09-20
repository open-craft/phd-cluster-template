#!/bin/env bash

set -uo pipefail

# shellcheck disable=SC2155
function __phd_generate_config() {
    local template_file="$1"
    local output_file="$2"
    local config_file="${3:-}"

    __log_info "Generating config from template: $template_file"

    if [[ -n "$config_file" && -f "$config_file" ]]; then
        __log_info "Loading configuration from: $config_file"
        set -a
        # shellcheck disable=SC1090
        source "$config_file"
        set +a
    fi

    # Check if template file exists
    if [[ ! -f "$template_file" ]]; then
        __log_error "Template file not found: $template_file"
        return 1
    fi

    # Create output directory if it doesn't exist
    local output_dir=$(dirname "$output_file")
    if [[ ! -d "$output_dir" ]]; then
        mkdir -p "$output_dir"
    fi

    # Generate config using envsubst
    if command -v envsubst &> /dev/null; then
        envsubst < "$template_file" > "$output_file"
    else
        __log_warning "envsubst not found, using basic substitution"
        # Basic substitution fallback
        cp "$template_file" "$output_file"
        # Replace ${VAR} patterns
        while IFS= read -r line; do
            if [[ "$line" =~ \$\{([^}]+)\} ]]; then
                local var_name="${BASH_REMATCH[1]}"
                if [[ -n "${!var_name:-}" ]]; then
                    sed -i "s/\${$var_name}/${!var_name}/g" "$output_file"
                else
                    __log_warning "Variable $var_name not set, leaving placeholder"
                fi
            fi
        done < "$template_file"
    fi

    __log_success "Generated config: $output_file"
}

# shellcheck disable=SC2155
function __phd_validate_config() {
    local config_file="$1"

    __log_info "Validating config file: $config_file"

    if [[ ! -f "$config_file" ]]; then
        __log_error "Config file not found: $config_file"
        return 1
    fi

    # Check for unsubstituted variables
    local unsubstituted_vars=()
    while IFS= read -r line; do
        if [[ "$line" =~ \$\{([^}]+)\} ]]; then
            unsubstituted_vars+=("${BASH_REMATCH[1]}")
        fi
    done < "$config_file"

    if [[ ${#unsubstituted_vars[@]} -gt 0 ]]; then
        __log_warning "Found unsubstituted variables:"
        for var in "${unsubstituted_vars[@]}"; do
            __log_warning "  - $var"
        done
        return 1
    else
        __log_success "Config file is valid (no unsubstituted variables)"
        return 0
    fi
}
