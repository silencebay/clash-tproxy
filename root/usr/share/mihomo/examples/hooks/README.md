# Mihomo Container Hooks

This directory contains example hook scripts that demonstrate how to use the hook system in the Mihomo container.

## Hook Stages

The container supports the following hook stages:

1. **post-init** - Executed after basic initialization (non-critical)
2. **pre-mihomo** - Executed before starting mihomo service (critical)
3. **post-mihomo** - Executed after mihomo service starts (non-critical)

## Hook Directory Structure

Place your hook scripts in `/config/hooks/`:

```
/config/hooks/
├── post-init/
│   └── 01-system-network-setup.sh
├── pre-mihomo/
│   └── 01-config-validation.sh
└── post-mihomo/
    └── 01-service-check.sh
```

## Hook Script Requirements

1. **Executable**: Scripts must have execute permissions (`chmod +x`)
2. **Naming**: Use numeric prefixes for execution order (e.g., `01-`, `02-`, `10-`)
3. **Exit codes**: Return 0 for success, non-zero for failure

## Hook Metadata

You can add metadata to your hook scripts using comments at the beginning:

```bash
#!/bin/bash
# HOOK_NAME: My Custom Hook
# HOOK_DESCRIPTION: Description of what this hook does
# HOOK_TIMEOUT: 60        # Timeout in seconds (default: 300)
# HOOK_RETRY: 3           # Number of retries (default: 1)
# HOOK_CRITICAL: true     # Whether failure should stop container (default: depends on stage)
```

## Environment Variables

Hook scripts have access to all container environment variables, including:

- `TZ` - Timezone
- `EN_MODE` - Mihomo mode
- `TPROXY_PORT` - TProxy port
- `MIXED_PORT` - Mixed port
- And all other container environment variables

## Error Handling

- **Critical stages** (pre-init, pre-mihomo): Hook failures stop the container
- **Non-critical stages** (post-init, post-mihomo): Hook failures are logged but don't stop the container
- Failed hooks are automatically retried based on the retry configuration

## Debugging

Enable debug logging by setting the environment variable:

```bash
HOOK_DEBUG=true
```

## Examples

Copy the example scripts to your `/config/hooks/` directory and modify them as needed:

```bash
# Copy examples to your config directory
cp -r /usr/share/mihomo/examples/hooks/* /config/hooks/

# Make scripts executable
find /config/hooks -name "*.sh" -exec chmod +x {} \;
```

## Common Use Cases

### Post-Init Hooks
- System configuration and directory setup
- Permission configuration
- Environment validation
- Network connectivity checks
- Custom routing rules
- External service registration

### Pre-Mihomo Hooks
- Configuration validation
- Configuration backup
- Dependency checks
- Custom configuration generation

### Post-Mihomo Hooks
- Service health checks
- Monitoring setup
- Notification sending
- Integration with external systems

## Traffic Marking for QoS

The hook system includes advanced traffic marking capabilities that work seamlessly with FireQOS using **nftables** (matching the project's TProxy implementation):

### DMAC-based Marking
Mark packets based on destination MAC addresses:
```bash
# Simple DMAC marking
/config/hooks/post-init/02-dmac-marking.sh
```

### Advanced Multi-layer Marking
Mark packets based on complex L2/L3 conditions:
```bash
# Advanced marking with mixed conditions
/config/hooks/post-init/03-advanced-traffic-marking.sh
```

### Configuration
1. Copy the example config: `cp /usr/share/mihomo/examples/hooks/config/traffic-marking.conf.example /config/hooks/config/traffic-marking.conf`
2. Edit the config file with your network's MAC addresses and IP ranges
3. The hooks will automatically apply the rules on container startup

### FireQOS Integration
After marking packets, use them in your `fireqos.conf`:
```
interface eth0 world output
  class gaming
    match mark 0x10 0x11 0x100  # Gaming devices
    commit 50mbit prio 1

  class streaming
    match mark 0x20 0x200       # Streaming devices
    commit 30mbit prio 2
```

This approach solves the limitation where FireQOS cannot directly mix DMAC and IP address matching in a single rule.

### Debugging Traffic Marking

To debug and monitor traffic marking:
```bash
# View current marking rules
nft list tables
nft list table inet qos_marking

# Monitor traffic in real-time
nft monitor

# Test marking with the provided tool
/usr/share/mihomo/examples/hooks/tools/test-traffic-marking.sh
```
