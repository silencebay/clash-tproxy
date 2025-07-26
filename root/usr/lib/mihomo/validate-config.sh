#!/bin/bash
# Built-in configuration validation script
# This script is automatically executed during pre-mihomo stage if no user hooks are present

set -eu

CONFIG_DIR="/config/mihomo"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"

log() {
    echo "[config-validator] $1"
}

log_error() {
    echo "[config-validator] ERROR: $1" >&2
}

log "Starting mihomo configuration validation..."

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    log "Please ensure your mihomo configuration is mounted to /config/mihomo/"
    exit 1
fi

log "Configuration file found: $CONFIG_FILE"

# Validate configuration syntax
log "Validating configuration syntax..."
if /usr/local/bin/mihomo -t -d "$CONFIG_DIR" 2>/dev/null; then
    log "✓ Configuration validation passed"
else
    log_error "Configuration validation failed"
    log "Please check your mihomo configuration file for syntax errors"
    
    # Try to provide more detailed error information
    log "Running detailed validation..."
    /usr/local/bin/mihomo -t -d "$CONFIG_DIR" || true
    exit 1
fi

# Check for required data files and download if missing
log "Checking required data files..."

declare -A data_files=(
    ["country.mmdb"]="https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/release/country.mmdb"
    ["geoip.dat"]="https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/release/geoip.dat"
    ["geosite.dat"]="https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/release/geosite.dat"
)

for file in "${!data_files[@]}"; do
    file_path="${CONFIG_DIR}/${file}"
    if [[ -f "$file_path" ]]; then
        log "✓ Found: ${file}"
        
        # Check if file is older than 7 days
        if [[ $(find "$file_path" -mtime +7 2>/dev/null | wc -l) -gt 0 ]]; then
            log "⚠ ${file} is older than 7 days, consider updating"
        fi
    else
        log "⚠ Missing: ${file}, downloading..."
        if curl -fsSL "${data_files[$file]}" -o "$file_path"; then
            log "✓ Downloaded: ${file}"
        else
            log_error "Failed to download: ${file}"
            log "You may need to download this file manually"
        fi
    fi
done

# Validate critical configuration sections
log "Validating critical configuration sections..."

# Check if required ports are configured
if grep -q "mixed-port\|port\|socks-port" "$CONFIG_FILE"; then
    log "✓ Proxy ports configured"
else
    log_error "No proxy ports configured (mixed-port, port, or socks-port)"
    exit 1
fi

# Check if mode is set
if grep -q "mode:" "$CONFIG_FILE"; then
    mode=$(grep "mode:" "$CONFIG_FILE" | head -1 | sed 's/.*mode:[[:space:]]*//' | tr -d '"'"'"' ')
    log "✓ Mode configured: $mode"
else
    log "⚠ No mode specified, will use default"
fi

# Check for external controller if API access is needed
if grep -q "external-controller:" "$CONFIG_FILE"; then
    log "✓ External controller configured"
else
    log "⚠ External controller not configured (API access will be disabled)"
fi

log "Configuration validation completed successfully"
