#!/bin/bash

# =============================================================================
# Direct nftables Environment Variable Adapter
# =============================================================================
# This adapter bridges environment variables to the universal direct nftables script.

# =============================================================================
# Environment Variable Mapping
# =============================================================================

# Default values
readonly DEFAULT_NFT_CONFIG_FILE="/config/hooks/config/nft-traffic-marking.nft"

# Map environment variables to parameters
get_direct_nft_params() {
    local params=""

    # Required parameters
    local config="${HOOKS_DIRECT_NFT_CONFIG:-${NFT_CONFIG_FILE:-$DEFAULT_NFT_CONFIG_FILE}}"
    params+="--config=\"$config\""

    # Options
    if [[ "${HOOKS_DIRECT_NFT_CLEANUP:-${NFT_CLEANUP:-false}}" == "true" ]]; then
        params+=" --cleanup"
    fi

    if [[ "${HOOKS_DIRECT_NFT_DEBUG:-${HOOK_DEBUG:-false}}" == "true" ]]; then
        params+=" --debug"
    fi

    if [[ "${HOOKS_DIRECT_NFT_DRY_RUN:-${NFT_DRY_RUN:-false}}" == "true" ]]; then
        params+=" --dry-run"
    fi

    echo "$params"
}

# Run the hook script with environment variable mapping
run_direct_nft() {
    local script_dir="$(dirname "${BASH_SOURCE[0]}")/../post-init"
    local script="$script_dir/02-direct-nft.sh"

    if [[ ! -f "$script" ]]; then
        echo "[direct-nft-adapter] ERROR: Hook script not found: $script" >&2
        return 1
    fi

    local params
    params=$(get_direct_nft_params)

    if [[ "${HOOKS_DIRECT_NFT_DEBUG:-${HOOK_DEBUG:-false}}" == "true" ]]; then
        echo "[direct-nft-adapter] Running: $script $params" >&2
    fi

    eval "$script $params"
}

# Show current environment variable mapping (for debugging)
show_direct_nft_config() {
    echo "=== Direct nftables Configuration ==="
    echo "Parameters: $(get_direct_nft_params)"
    echo "======================================"
}

# Validate environment variables and show warnings
validate_direct_nft_env() {
    local warnings=()
    
    # Check for deprecated variables
    if [[ -n "${NFT_CONFIG_FILE:-}" && -z "${HOOKS_DIRECT_NFT_CONFIG:-}" ]]; then
        warnings+=("NFT_CONFIG_FILE is deprecated, use HOOKS_DIRECT_NFT_CONFIG")
    fi

    if [[ -n "${NFT_CLEANUP:-}" && -z "${HOOKS_DIRECT_NFT_CLEANUP:-}" ]]; then
        warnings+=("NFT_CLEANUP is deprecated, use HOOKS_DIRECT_NFT_CLEANUP")
    fi

    if [[ -n "${NFT_DRY_RUN:-}" && -z "${HOOKS_DIRECT_NFT_DRY_RUN:-}" ]]; then
        warnings+=("NFT_DRY_RUN is deprecated, use HOOKS_DIRECT_NFT_DRY_RUN")
    fi
    
    # Show warnings
    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo "[direct-nft-adapter] WARNINGS:" >&2
        for warning in "${warnings[@]}"; do
            echo "  - $warning" >&2
        done
        echo "" >&2
    fi
    
    # Check for required configuration
    local config_file="${HOOKS_DIRECT_NFT_CONFIG:-${NFT_CONFIG_FILE:-$DEFAULT_NFT_CONFIG_FILE}}"
    if [[ ! -f "$config_file" ]]; then
        echo "[direct-nft-adapter] WARNING: Configuration file not found: $config_file" >&2
        echo "[direct-nft-adapter] Direct nftables configuration will fail without proper configuration" >&2
    fi
}

# Auto-validation when sourced
if [[ "${HOOKS_DIRECT_NFT_DEBUG:-${HOOK_DEBUG:-false}}" == "true" ]]; then
    validate_direct_nft_env
    show_direct_nft_config
fi
