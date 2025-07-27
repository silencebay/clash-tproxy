#!/bin/bash
# TProxy Mark Validation Tool
# This script validates that traffic marking configurations are compatible with TProxy

set -euo pipefail

log() {
    echo "[tproxy-mark-validator] $1"
}

log_error() {
    echo "[tproxy-mark-validator] ERROR: $1" >&2
}

log_warning() {
    echo "[tproxy-mark-validator] WARNING: $1" >&2
}

# TProxy reserved marks (from common.sh)
readonly PROXY_FWMARK=0x1
readonly PROXY_ROUTING_MARK=0x2
readonly TPROXY_RESERVED_MASK=0x0000FFFF
readonly QOS_AVAILABLE_MASK=0xFFFF0000

usage() {
    cat << EOF
Usage: $0 [CONFIG_FILE]

Validate nftables traffic marking configuration for TProxy compatibility.

PARAMETERS:
  CONFIG_FILE    nftables configuration file to validate (optional)
                 If not provided, validates current nftables rules

EXAMPLES:
  # Validate configuration file
  $0 /config/nft-traffic-marking.conf
  
  # Validate current active rules
  $0

VALIDATION CHECKS:
  1. Marks use high 16 bits only (0xFFFF0000 range)
  2. OR operations preserve TProxy marks
  3. No conflicts with reserved TProxy marks (0x1, 0x2)
  4. Proper bit allocation follows TProxy compatibility design

EOF
}

# Extract marks from nftables configuration
extract_marks_from_config() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    # Extract mark values from meta mark set operations
    grep -E "meta mark set.*0x[0-9a-fA-F]+" "$config_file" | \
        sed -E 's/.*meta mark set \(meta mark \| (0x[0-9a-fA-F]+)\).*/\1/' | \
        sort -u
}

# Extract marks from active nftables rules
extract_marks_from_active() {
    if ! command -v nft >/dev/null 2>&1; then
        log_error "nftables (nft) is not available"
        return 1
    fi
    
    # Get all active rules with mark operations
    nft list tables 2>/dev/null | while read -r line; do
        if [[ "$line" =~ table[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+) ]]; then
            local family="${BASH_REMATCH[1]}"
            local table="${BASH_REMATCH[2]}"
            nft list table "$family" "$table" 2>/dev/null | \
                grep -E "meta mark set.*0x[0-9a-fA-F]+" | \
                sed -E 's/.*meta mark set \(meta mark \| (0x[0-9a-fA-F]+)\).*/\1/' || true
        fi
    done | sort -u
}

# Validate a single mark value
validate_mark() {
    local mark="$1"
    local issues=0
    
    # Convert hex to decimal
    local mark_dec=$((mark))
    
    # Check if mark uses only high 16 bits
    local low_bits=$((mark_dec & TPROXY_RESERVED_MASK))
    if [[ $low_bits -ne 0 ]]; then
        log_error "Mark $mark uses reserved TProxy bits (low 16 bits): 0x$(printf '%04x' $low_bits)"
        issues=$((issues + 1))
    fi
    
    # Check for specific conflicts
    if [[ $mark_dec -eq $PROXY_FWMARK ]]; then
        log_error "Mark $mark conflicts with PROXY_FWMARK (0x1)"
        issues=$((issues + 1))
    fi
    
    if [[ $mark_dec -eq $PROXY_ROUTING_MARK ]]; then
        log_error "Mark $mark conflicts with PROXY_ROUTING_MARK (0x2)"
        issues=$((issues + 1))
    fi
    
    # Check if mark is in valid custom range
    local high_bits=$((mark_dec & QOS_AVAILABLE_MASK))
    if [[ $high_bits -eq 0 ]]; then
        log_warning "Mark $mark is too small, consider using high 16 bits (0x10000+)"
    fi
    
    return $issues
}

# Validate OR operation usage in config file
validate_or_operations() {
    local config_file="$1"
    local issues=0
    
    # Check for direct mark assignments (bad)
    local direct_assignments
    direct_assignments=$(grep -n "meta mark set 0x" "$config_file" | grep -v "meta mark |" || true)
    
    if [[ -n "$direct_assignments" ]]; then
        log_error "Found direct mark assignments (should use OR operation):"
        echo "$direct_assignments" | while read -r line; do
            log_error "  Line: $line"
        done
        issues=$((issues + 1))
    fi
    
    # Check for proper OR operations (good)
    local or_operations
    or_operations=$(grep -c "meta mark set (meta mark |" "$config_file" || true)
    
    if [[ $or_operations -gt 0 ]]; then
        log "✓ Found $or_operations proper OR operations"
    else
        log_warning "No OR operations found - ensure TProxy compatibility"
    fi
    
    return $issues
}

# Main validation function
validate_marks() {
    local config_file="$1"
    local total_issues=0
    local marks
    
    log "Starting TProxy mark validation..."
    
    if [[ -n "$config_file" ]]; then
        log "Validating configuration file: $config_file"
        marks=$(extract_marks_from_config "$config_file")
        
        # Validate OR operations
        if ! validate_or_operations "$config_file"; then
            total_issues=$((total_issues + 1))
        fi
    else
        log "Validating active nftables rules..."
        marks=$(extract_marks_from_active)
    fi
    
    if [[ -z "$marks" ]]; then
        log_warning "No traffic marks found"
        return 0
    fi
    
    log "Found marks: $(echo "$marks" | tr '\n' ' ')"
    
    # Validate each mark
    while IFS= read -r mark; do
        [[ -n "$mark" ]] || continue
        log "Validating mark: $mark"
        
        if ! validate_mark "$mark"; then
            total_issues=$((total_issues + 1))
        else
            log "✓ Mark $mark is TProxy compatible"
        fi
    done <<< "$marks"
    
    # Summary
    log ""
    log "=== Validation Summary ==="
    if [[ $total_issues -eq 0 ]]; then
        log "✓ All marks are TProxy compatible!"
        log "✓ Configuration follows proper bit allocation"
        log "✓ No conflicts with reserved TProxy marks"
    else
        log_error "Found $total_issues compatibility issues"
        log_error "Please fix the issues above before deploying"
        return 1
    fi
    
    # Show bit allocation info
    log ""
    log "=== TProxy System Design ==="
    log "Low 16 bits (0x0000FFFF): Reserved for TProxy"
    log "  - PROXY_FWMARK: 0x$(printf '%x' $PROXY_FWMARK)"
    log "  - PROXY_ROUTING_MARK: 0x$(printf '%x' $PROXY_ROUTING_MARK)"
    log "High 16 bits (0xFFFF0000): Available for custom marking"
    log "  - Use OR operations: meta mark set (meta mark | CUSTOM_MARK)"
    
    return 0
}

# Main execution
main() {
    local config_file=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                usage >&2
                exit 1
                ;;
            *)
                config_file="$1"
                shift
                ;;
        esac
    done
    
    validate_marks "$config_file"
}

main "$@"
