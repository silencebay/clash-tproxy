#!/bin/bash
# Script to install example hooks for users

set -eu

EXAMPLES_DIR="/usr/share/mihomo/examples/hooks"
CONFIG_HOOKS_DIR="/config/hooks"

log() {
    echo "[install-hooks] $1"
}

log_error() {
    echo "[install-hooks] ERROR: $1" >&2
}

if [[ ! -d "$EXAMPLES_DIR" ]]; then
    log_error "Examples directory not found: $EXAMPLES_DIR"
    exit 1
fi

log "Installing example hooks to $CONFIG_HOOKS_DIR"

# Create hooks directories
for stage in post-init pre-mihomo post-mihomo; do
    mkdir -p "${CONFIG_HOOKS_DIR}/${stage}"
    log "Created directory: ${CONFIG_HOOKS_DIR}/${stage}"
done

# Copy example scripts
if cp -r "${EXAMPLES_DIR}"/* "${CONFIG_HOOKS_DIR}/"; then
    log "Example hooks copied successfully"
else
    log_error "Failed to copy example hooks"
    exit 1
fi

# Make scripts executable
find "${CONFIG_HOOKS_DIR}" -name "*.sh" -exec chmod +x {} \;
log "Made hook scripts executable"

# Set proper ownership
chown -R abc:users "${CONFIG_HOOKS_DIR}"
log "Set proper ownership for hook scripts"

log "Example hooks installation completed!"
log ""
log "You can now customize the hooks in ${CONFIG_HOOKS_DIR}"
log "Remember to:"
log "1. Review and modify the example scripts according to your needs"
log "2. Remove or rename scripts you don't want to execute"
log "3. Use numeric prefixes (01-, 02-, etc.) to control execution order"
log ""
log "For more information, see: ${CONFIG_HOOKS_DIR}/README.md"
