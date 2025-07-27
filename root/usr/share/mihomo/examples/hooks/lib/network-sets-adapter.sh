#!/bin/bash

# =============================================================================
# Network Sets Environment Variable Adapter
# =============================================================================
# This adapter bridges environment variables to the parameterized network sets script.
# It allows automated hooks to use environment variables while maintaining
# the clean parameterized interface of the core script.

# =============================================================================
# Environment Variable Mapping
# =============================================================================

# Default values
readonly DEFAULT_TARGET_TABLES="network_sets"
readonly DEFAULT_LOCAL_NETWORKS="192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,127.0.0.0/8"
readonly DEFAULT_PUBLIC_NETWORKS="8.8.8.0/24,1.1.1.0/24,208.67.222.0/24"
readonly DEFAULT_DEVICE_NETWORKS="192.168.1.0/24,192.168.10.0/24,192.168.20.0/24"

# Map environment variables to parameters
get_network_sets_params() {
    local params=""

    # Required parameters
    local tables="${HOOKS_NETWORK_SETS_TABLES:-${TARGET_TABLES:-$DEFAULT_TARGET_TABLES}}"
    local local_networks="${HOOKS_NETWORK_SETS_LOCAL_NETWORKS:-${LOCAL_AREA_IPS:-$DEFAULT_LOCAL_NETWORKS}}"

    params+="--tables=\"$tables\" --local-networks=\"$local_networks\""

    # Optional network ranges
    local public_networks="${HOOKS_NETWORK_SETS_PUBLIC_NETWORKS:-${PUBLIC_SERVICE_IPS:-$DEFAULT_PUBLIC_NETWORKS}}"
    local device_networks="${HOOKS_NETWORK_SETS_DEVICE_NETWORKS:-${DEVICE_NETWORK_IPS:-$DEFAULT_DEVICE_NETWORKS}}"

    params+=" --public-networks=\"$public_networks\""
    params+=" --device-networks=\"$device_networks\""

    # Set names (optional)
    if [[ -n "${HOOKS_NETWORK_SETS_LOCAL_SET_NAME:-${LOCAL_NETWORKS_SET:-}}" ]]; then
        params+=" --local-set-name=\"${HOOKS_NETWORK_SETS_LOCAL_SET_NAME:-${LOCAL_NETWORKS_SET}}\""
    fi

    if [[ -n "${HOOKS_NETWORK_SETS_PUBLIC_SET_NAME:-${PUBLIC_NETWORKS_SET:-}}" ]]; then
        params+=" --public-set-name=\"${HOOKS_NETWORK_SETS_PUBLIC_SET_NAME:-${PUBLIC_NETWORKS_SET}}\""
    fi

    if [[ -n "${HOOKS_NETWORK_SETS_DEVICE_SET_NAME:-${DEVICE_NETWORKS_SET:-}}" ]]; then
        params+=" --device-set-name=\"${HOOKS_NETWORK_SETS_DEVICE_SET_NAME:-${DEVICE_NETWORKS_SET}}\""
    fi

    # Feature toggles
    local enable_local="${HOOKS_NETWORK_SETS_ENABLE_LOCAL:-${CREATE_LOCAL_SET:-true}}"
    local enable_public="${HOOKS_NETWORK_SETS_ENABLE_PUBLIC:-${CREATE_PUBLIC_SET:-false}}"
    local enable_device="${HOOKS_NETWORK_SETS_ENABLE_DEVICE:-${CREATE_DEVICE_SET:-false}}"

    params+=" --enable-local=\"$enable_local\""
    params+=" --enable-public=\"$enable_public\""
    params+=" --enable-device=\"$enable_device\""

    # Options
    if [[ "${HOOKS_NETWORK_SETS_CLEANUP:-${CLEANUP_EXISTING:-false}}" == "true" ]]; then
        params+=" --cleanup"
    fi

    if [[ "${HOOKS_NETWORK_SETS_DEBUG:-${HOOK_DEBUG:-false}}" == "true" ]]; then
        params+=" --debug"
    fi

    echo "$params"
}

# Run the hook script with environment variable mapping
run_network_sets() {
    local script_dir="$(dirname "${BASH_SOURCE[0]}")/../post-init"
    local script="$script_dir/01-network-sets.sh"

    if [[ ! -f "$script" ]]; then
        echo "[network-sets-adapter] ERROR: Hook script not found: $script" >&2
        return 1
    fi

    local params
    params=$(get_network_sets_params)

    if [[ "${HOOKS_NETWORK_SETS_DEBUG:-${HOOK_DEBUG:-false}}" == "true" ]]; then
        echo "[network-sets-adapter] Running: $script $params" >&2
    fi

    eval "$script $params"
}

# Show current environment variable mapping (for debugging)
show_network_sets_config() {
    echo "=== Network Sets Configuration ==="
    echo "Parameters: $(get_network_sets_params)"
    echo "=================================="
}

# Validate environment variables and show warnings
validate_network_sets_env() {
    local warnings=()
    
    # Check for deprecated variables
    if [[ -n "${TARGET_TABLES:-}" && -z "${HOOKS_NETWORK_SETS_TABLES:-}" ]]; then
        warnings+=("TARGET_TABLES is deprecated, use HOOKS_NETWORK_SETS_TABLES")
    fi

    if [[ -n "${LOCAL_AREA_IPS:-}" && -z "${HOOKS_NETWORK_SETS_LOCAL_NETWORKS:-}" ]]; then
        warnings+=("LOCAL_AREA_IPS is deprecated, use HOOKS_NETWORK_SETS_LOCAL_NETWORKS")
    fi

    if [[ -n "${CREATE_LOCAL_SET:-}" && -z "${HOOKS_NETWORK_SETS_ENABLE_LOCAL:-}" ]]; then
        warnings+=("CREATE_LOCAL_SET is deprecated, use HOOKS_NETWORK_SETS_ENABLE_LOCAL")
    fi

    if [[ -n "${CREATE_PUBLIC_SET:-}" && -z "${HOOKS_NETWORK_SETS_ENABLE_PUBLIC:-}" ]]; then
        warnings+=("CREATE_PUBLIC_SET is deprecated, use HOOKS_NETWORK_SETS_ENABLE_PUBLIC")
    fi

    if [[ -n "${CREATE_DEVICE_SET:-}" && -z "${HOOKS_NETWORK_SETS_ENABLE_DEVICE:-}" ]]; then
        warnings+=("CREATE_DEVICE_SET is deprecated, use HOOKS_NETWORK_SETS_ENABLE_DEVICE")
    fi

    if [[ -n "${CLEANUP_EXISTING:-}" && -z "${HOOKS_NETWORK_SETS_CLEANUP:-}" ]]; then
        warnings+=("CLEANUP_EXISTING is deprecated, use HOOKS_NETWORK_SETS_CLEANUP")
    fi
    
    # Show warnings
    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo "[network-sets-adapter] WARNINGS:" >&2
        for warning in "${warnings[@]}"; do
            echo "  - $warning" >&2
        done
        echo "" >&2
    fi
    
    # Check for required configuration
    local local_networks="${HOOKS_NETWORK_SETS_LOCAL_NETWORKS:-${LOCAL_AREA_IPS:-}}"
    if [[ -z "$local_networks" ]]; then
        echo "[network-sets-adapter] WARNING: No local networks configured" >&2
        echo "[network-sets-adapter] Set HOOKS_NETWORK_SETS_LOCAL_NETWORKS for meaningful operation" >&2
    fi
}

# Auto-validation when sourced
if [[ "${HOOKS_NETWORK_SETS_DEBUG:-${HOOK_DEBUG:-false}}" == "true" ]]; then
    validate_network_sets_env
    show_network_sets_config
fi
