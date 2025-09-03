#!/usr/bin/env bash
#
# Template rendering script. This script provides functions to generate and
# validate configuration files from templates.

set -uo pipefail

function __phd_generate_config() {
    local template_file="$1"
    local output_file="$2"
    local config_file="${3:-}"

    # Check if template file exists
    if [[ ! -f "$template_file" ]]; then
        __log_error "Template file not found: $template_file"
        return 1
    fi

    # Load configuration if provided
    if [[ -n "$config_file" && -f "$config_file" ]]; then
        __log_info "Loading configuration from: $config_file"
        set -a
        # shellcheck disable=SC1090
        source "$config_file" || {
            __log_error "Failed to load configuration file: $config_file"
            return 1
        }
        set +a
    fi

    # Create output directory if it doesn't exist
    local output_dir
    output_dir=$(dirname "$output_file")
    if [[ ! -d "$output_dir" ]]; then
        __phd_run_command "create output directory" mkdir -p "$output_dir" || return 1
    fi

    # Generate config using envsubst if available
    if command -v envsubst &> /dev/null; then
        __phd_run_command "generate config using envsubst" \
            envsubst < "$template_file" > "$output_file" || return 1
    else
        __log_warning "envsubst not found, using basic substitution"
        
        # Basic substitution fallback
        __phd_run_command "copy template file" cp "$template_file" "$output_file" || return 1
        
        # Replace ${VAR} patterns
        while IFS= read -r line; do
            if [[ "$line" =~ \$\{([^}]+)\} ]]; then
                local var_name="${BASH_REMATCH[1]}"
                local var_value
                eval "var_value=\$${var_name}"
                if [[ -n "$var_value" ]]; then
                    __phd_run_command "substitute variable $var_name" \
                        sed -i "s/\${$var_name}/$var_value/g" "$output_file" || return 1
                else
                    __log_warning "Variable $var_name not set, leaving placeholder"
                fi
            fi
        done < "$template_file"
    fi

    __log_success "Generated config: $output_file"
}

function __phd_validate_config() {
    local config_file="$1"

    # Check if config file exists
    if [[ ! -f "$config_file" ]]; then
        __log_error "Config file not found: $config_file"
        return 1
    fi

    __log_info "Validating config file: $config_file"

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
    fi

    __log_success "Config file is valid (no unsubstituted variables)"
    return 0
}