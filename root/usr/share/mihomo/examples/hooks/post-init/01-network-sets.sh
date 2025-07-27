#!/bin/bash
# HOOK_STAGE: post-init
# HOOK_PRIORITY: 10
# HOOK_DESCRIPTION: Create nftables sets for network classification

# =============================================================================
# Network Sets Hook (Parameterized with Optional Environment Variable Support)
# =============================================================================
# This hook creates nftables sets for network classification.
#
# USAGE:
# ------
# $0 --tables=TABLES --local-networks=NETWORKS [OPTIONS]
#
# ENVIRONMENT VARIABLE SUPPORT:
# ------------------------------
# If no parameters are provided and environment variables are set,
# the script will automatically use them via the adapter.
#
# EXAMPLES:
# ---------
# # Direct parameterized usage
# $0 --tables="network_sets" --local-networks="192.168.1.0/24,10.0.0.0/8"
#
# # Environment variable usage (if adapter exists)
# export HOOKS_NETWORK_SETS_LOCAL_NETWORKS="192.168.1.0/24,10.0.0.0/8"
# $0
# =============================================================================

set -euo pipefail

# Try to source the environment variable adapter if it exists and no parameters provided
if [[ $# -eq 0 ]]; then
    ADAPTER_PATH="$(dirname "${BASH_SOURCE[0]}")/../lib/network-sets-adapter.sh"
    if [[ -f "$ADAPTER_PATH" ]]; then
        source "$ADAPTER_PATH"
        # If adapter provides a function to run with env vars, use it
        if declare -f run_network_sets >/dev/null 2>&1; then
            run_network_sets
            exit $?
        fi
    fi
fi

# If we reach here, proceed with parameterized execution

usage() {
    cat << EOF
Usage: $0 --tables=TABLES --local-networks=NETWORKS [OPTIONS]

Deploy network sets to specified nftables tables.

REQUIRED PARAMETERS:
  --tables=TABLES             Comma-separated list of target tables
  --local-networks=NETWORKS   Local network ranges (comma-separated CIDR)

OPTIONAL PARAMETERS:
  --public-networks=NETWORKS  Public service networks (comma-separated CIDR)
  --device-networks=NETWORKS  Device-specific networks (comma-separated CIDR)
  --local-set-name=NAME       Name for local networks set (default: local_networks)
  --public-set-name=NAME      Name for public networks set (default: public_networks)
  --device-set-name=NAME      Name for device networks set (default: device_networks)
  --enable-local=BOOL         Create local networks set (default: true)
  --enable-public=BOOL        Create public networks set (default: false)
  --enable-device=BOOL        Create device networks set (default: false)
  --cleanup                   Clean existing sets before creating new ones
  --debug                     Enable debug logging
  --help                      Show this help message

EXAMPLES:
  # Basic usage
  $0 --tables="network_sets" --local-networks="192.168.1.0/24,10.0.0.0/8"

  # Multiple tables with all sets
  $0 --tables="network_sets,traffic_marking" \\
     --local-networks="192.168.0.0/16,10.0.0.0/8" \\
     --enable-public=true --enable-device=true

  # Environment variable usage (automatic)
  export HOOKS_NETWORK_SETS_LOCAL_NETWORKS="192.168.1.0/24"
  $0

EOF
}

# Default values
TABLES=""
LOCAL_NETWORKS=""
PUBLIC_NETWORKS="8.8.8.0/24,1.1.1.0/24,208.67.222.0/24,23.246.0.0/18,172.217.0.0/16,151.101.0.0/16"
DEVICE_NETWORKS="192.168.1.0/24,192.168.10.0/24,192.168.20.0/24,192.168.30.0/24"
LOCAL_SET_NAME="local_networks"
PUBLIC_SET_NAME="public_networks"
DEVICE_SET_NAME="device_networks"
ENABLE_LOCAL="true"
ENABLE_PUBLIC="false"
ENABLE_DEVICE="false"
CLEANUP="false"
DEBUG="false"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --tables=*)
            TABLES="${1#*=}"
            shift
            ;;
        --local-networks=*)
            LOCAL_NETWORKS="${1#*=}"
            shift
            ;;
        --public-networks=*)
            PUBLIC_NETWORKS="${1#*=}"
            shift
            ;;
        --device-networks=*)
            DEVICE_NETWORKS="${1#*=}"
            shift
            ;;
        --local-set-name=*)
            LOCAL_SET_NAME="${1#*=}"
            shift
            ;;
        --public-set-name=*)
            PUBLIC_SET_NAME="${1#*=}"
            shift
            ;;
        --device-set-name=*)
            DEVICE_SET_NAME="${1#*=}"
            shift
            ;;
        --enable-local=*)
            ENABLE_LOCAL="${1#*=}"
            shift
            ;;
        --enable-public=*)
            ENABLE_PUBLIC="${1#*=}"
            shift
            ;;
        --enable-device=*)
            ENABLE_DEVICE="${1#*=}"
            shift
            ;;
        --cleanup)
            CLEANUP="true"
            shift
            ;;
        --debug)
            DEBUG="true"
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$TABLES" ]]; then
    echo "Error: --tables parameter is required" >&2
    usage >&2
    exit 1
fi

if [[ -z "$LOCAL_NETWORKS" ]]; then
    echo "Error: --local-networks parameter is required" >&2
    usage >&2
    exit 1
fi

log() {
    echo "[network-sets] $1"
}

log_debug() {
    if [[ "$DEBUG" == "true" ]]; then
        echo "[network-sets] DEBUG: $1" >&2
    fi
}

log_error() {
    echo "[network-sets] ERROR: $1" >&2
}

parse_network_list() {
    local network_string="$1"
    local -n result_array=$2

    IFS=',' read -ra result_array <<< "$network_string"

    # Clean up whitespace
    for i in "${!result_array[@]}"; do
        result_array[i]="${result_array[i]// /}"
    done
}

deploy_set_to_table() {
    local table="$1"
    local set_name="$2"
    local networks_string="$3"

    log_debug "Deploying set $set_name to table $table"

    # Parse networks
    local networks=()
    parse_network_list "$networks_string" networks

    if [[ ${#networks[@]} -eq 0 ]]; then
        log_debug "No networks configured for set: $set_name"
        return 0
    fi

    # Ensure table exists
    nft add table inet "$table" 2>/dev/null || true

    # Create set
    nft add set inet "$table" "$set_name" { type ipv4_addr\; flags interval\; } 2>/dev/null || true

    # Clean existing elements if requested
    if [[ "$CLEANUP" == "true" ]]; then
        nft flush set inet "$table" "$set_name" 2>/dev/null || true
    fi

    # Add networks to set
    for network in "${networks[@]}"; do
        if [[ -n "$network" ]]; then
            nft add element inet "$table" "$set_name" { "$network" } 2>/dev/null || true
            log_debug "  Added $network to $set_name"
        fi
    done

    log "✓ Deployed set $set_name with ${#networks[@]} networks to table $table"
}

# Main execution
main() {
    log "Starting network sets deployment..."

    # Show configuration if debug enabled
    if [[ "$DEBUG" == "true" ]]; then
        log_debug "Configuration:"
        log_debug "  Tables: $TABLES"
        log_debug "  Local networks: $LOCAL_NETWORKS"
        log_debug "  Public networks: $PUBLIC_NETWORKS"
        log_debug "  Device networks: $DEVICE_NETWORKS"
        log_debug "  Local set name: $LOCAL_SET_NAME"
        log_debug "  Public set name: $PUBLIC_SET_NAME"
        log_debug "  Device set name: $DEVICE_SET_NAME"
        log_debug "  Enable local: $ENABLE_LOCAL"
        log_debug "  Enable public: $ENABLE_PUBLIC"
        log_debug "  Enable device: $ENABLE_DEVICE"
        log_debug "  Cleanup: $CLEANUP"
    fi

    # Check dependencies
    if ! command -v nft >/dev/null 2>&1; then
        log_error "nftables (nft) is not available"
        exit 1
    fi

    # Parse target tables
    IFS=',' read -ra tables <<< "$TABLES"

    # Deploy to each table
    for table in "${tables[@]}"; do
        table="${table// /}"  # Remove whitespace
        if [[ -n "$table" ]]; then
            log "Deploying to table: $table"

            if [[ "$ENABLE_LOCAL" == "true" ]]; then
                deploy_set_to_table "$table" "$LOCAL_SET_NAME" "$LOCAL_NETWORKS"
            fi

            if [[ "$ENABLE_PUBLIC" == "true" ]]; then
                deploy_set_to_table "$table" "$PUBLIC_SET_NAME" "$PUBLIC_NETWORKS"
            fi

            if [[ "$ENABLE_DEVICE" == "true" ]]; then
                deploy_set_to_table "$table" "$DEVICE_SET_NAME" "$DEVICE_NETWORKS"
            fi
        fi
    done

    log "Network sets deployment completed successfully"

    # Show usage examples
    log ""
    log "Usage examples for deployed sets:"
    log "================================="
    for table in "${tables[@]}"; do
        table="${table// /}"
        if [[ -n "$table" ]]; then
            if [[ "$ENABLE_LOCAL" == "true" ]]; then
                log "  ip saddr @$LOCAL_SET_NAME  # in table $table"
            fi
            if [[ "$ENABLE_PUBLIC" == "true" ]]; then
                log "  ip daddr @$PUBLIC_SET_NAME  # in table $table"
            fi
            if [[ "$ENABLE_DEVICE" == "true" ]]; then
                log "  ip saddr @$DEVICE_SET_NAME  # in table $table"
            fi
        fi
    done
}

# Execute main function
main "$@"