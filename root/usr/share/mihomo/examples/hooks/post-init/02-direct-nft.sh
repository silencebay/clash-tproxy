#!/bin/bash
# HOOK_STAGE: post-init
# HOOK_PRIORITY: 30
# HOOK_DESCRIPTION: Direct nftables configuration applier (universal)

# =============================================================================
# Direct nftables Configuration Hook
# =============================================================================
# This hook applies nftables rules directly from configuration files.
# Universal tool for any nftables configuration: marking, filtering, NAT, etc.
# No parsing overhead, full nftables feature support.
#
# USAGE:
# ------
# $0 --config=CONFIG_FILE [OPTIONS]
#
# EXAMPLES:
# ---------
# $0 --config="/config/nft-traffic-marking.conf"
# $0 --config="/config/nft-firewall.conf" --cleanup --debug
# $0 --config="/config/nft-nat.conf" --dry-run
# =============================================================================

set -euo pipefail

# Try to source the environment variable adapter if it exists and no parameters provided
if [[ $# -eq 0 ]]; then
    ADAPTER_PATH="$(dirname "${BASH_SOURCE[0]}")/../lib/direct-nft-adapter.sh"
    if [[ -f "$ADAPTER_PATH" ]]; then
        source "$ADAPTER_PATH"
        if declare -f run_direct_nft >/dev/null 2>&1; then
            run_direct_nft
            exit $?
        fi
    fi
fi

usage() {
    cat << EOF
Usage: $0 --config=CONFIG_FILE [OPTIONS]

Apply nftables configuration directly from files.

REQUIRED PARAMETERS:
  --config=CONFIG_FILE        nftables configuration file path

OPTIONAL PARAMETERS:
  --cleanup                   Clean existing rules before applying new ones
  --debug                     Enable debug logging
  --dry-run                   Show configuration without applying
  --help                      Show help message

CONFIGURATION FILE FORMAT:
  The configuration file should contain valid nftables syntax.

  Examples:

  # Traffic Marking: /config/nft-traffic-marking.conf
  table inet traffic_marking {
      chain prerouting_mark {
          type filter hook prerouting priority mangle; policy accept;
          ether daddr aa:bb:cc:dd:ee:01 meta mark set (meta mark | 0x10000)
      }
  }

  # Firewall Rules: /config/nft-firewall.conf
  table inet firewall {
      chain input {
          type filter hook input priority filter; policy drop;
          ct state established,related accept
          iif lo accept
          tcp dport 22 accept
      }
  }

  # NAT Rules: /config/nft-nat.conf
  table ip nat {
      chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          oifname "eth0" masquerade
      }
  }

ADVANTAGES:
  - Universal nftables configuration tool
  - Full nftables feature support (marking, filtering, NAT, etc.)
  - No parsing overhead
  - Direct control over rules
  - Easy debugging (standard nftables syntax)
  - Support for advanced features (sets, maps, etc.)

EXAMPLES:
  # Traffic marking
  $0 --config="/config/nft-traffic-marking.conf"

  # Firewall rules with cleanup
  $0 --config="/config/nft-firewall.conf" --cleanup --debug

  # NAT configuration preview
  $0 --config="/config/nft-nat.conf" --dry-run

EOF
}

# Default values
CONFIG_FILE=""
CLEANUP="false"
DEBUG="false"
DRY_RUN="false"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config=*)
            CONFIG_FILE="${1#*=}"
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
        --dry-run)
            DRY_RUN="true"
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
if [[ -z "$CONFIG_FILE" ]]; then
    echo "Error: --config parameter is required" >&2
    usage >&2
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Configuration file not found: $CONFIG_FILE" >&2
    exit 1
fi

log() {
    echo "[direct-nft] $1"
}

log_debug() {
    if [[ "$DEBUG" == "true" ]]; then
        echo "[direct-nft] DEBUG: $1" >&2
    fi
}

log_error() {
    echo "[direct-nft] ERROR: $1" >&2
}

# Main execution
main() {
    log "Starting direct nftables configuration setup..."

    if [[ "$DEBUG" == "true" ]]; then
        log_debug "Configuration:"
        log_debug "  Config file: $CONFIG_FILE"
        log_debug "  Cleanup: $CLEANUP"
        log_debug "  Dry run: $DRY_RUN"
    fi

    # Check dependencies (skip in dry-run mode)
    if [[ "$DRY_RUN" != "true" ]] && ! command -v nft >/dev/null 2>&1; then
        log_error "nftables (nft) is not available"
        exit 1
    fi

    # Read configuration file
    log "Loading nftables configuration from: $CONFIG_FILE"
    
    local nft_config
    if ! nft_config=$(cat "$CONFIG_FILE"); then
        log_error "Failed to read configuration file: $CONFIG_FILE"
        exit 1
    fi

    # Validate nftables syntax (basic check)
    if [[ "$DRY_RUN" != "true" ]] && [[ "$DEBUG" == "true" ]]; then
        log_debug "Validating nftables syntax..."
        if ! echo "$nft_config" | nft -c -f -; then
            log_error "Invalid nftables syntax in configuration file"
            exit 1
        fi
        log_debug "✓ nftables syntax validation passed"
    fi

    if [[ "$DEBUG" == "true" ]]; then
        log_debug "Configuration content:"
        echo "$nft_config" >&2
    fi

    # Apply configuration
    if [[ "$DRY_RUN" == "true" ]]; then
        log "=== DRY RUN - nftables configuration ==="
        echo "$nft_config"
        log "=== END DRY RUN ==="
        log "✓ Configuration syntax appears valid"
    else
        # Apply cleanup if requested
        if [[ "$CLEANUP" == "true" ]]; then
            log "Cleaning up existing rules..."
            # Extract table names and delete them
            local tables
            tables=$(echo "$nft_config" | grep -E "^[[:space:]]*table[[:space:]]+" | awk '{print $3}' | sort -u)
            for table in $tables; do
                if nft list table "$table" >/dev/null 2>&1; then
                    log_debug "Deleting existing table: $table"
                    nft delete table "$table" || log_debug "Failed to delete table $table (may not exist)"
                fi
            done
        fi

        # Apply new configuration
        if echo "$nft_config" | nft -f -; then
            log "✓ Successfully applied nftables configuration"
        else
            log_error "Failed to apply nftables configuration"
            exit 1
        fi
    fi

    log "Direct nftables configuration setup completed successfully"

    # Show verification commands
    if [[ "$DRY_RUN" != "true" ]]; then
        log ""
        log "Verification:"
        log "============="
        
        # Extract and show table names
        local tables
        tables=$(echo "$nft_config" | grep -E "^[[:space:]]*table[[:space:]]+" | awk '{print $3}' | sort -u)
        for table in $tables; do
            log "View rules: nft list table $table"
        done
        log "Monitor traffic: nft monitor"
    fi
}

# Execute main function
main "$@"
