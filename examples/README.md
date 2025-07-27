# Mihomo Container Examples

This directory contains example configurations and documentation for the Mihomo container.

## Directory Structure

```
examples/
├── config/                          # Configuration examples
│   ├── hooks/
│   │   └── traffic-marking.conf     # Traffic marking configuration
│   ├── fireqos/
│   │   └── fireqos.conf             # FireQOS configuration
│   └── README.md                    # Configuration guide
├── docker-compose/                  # Docker Compose examples (if any)
└── README.md                        # This file
```

## Quick Start

### 1. Basic Setup

```bash
# Clone or download the project
git clone <repository-url>
cd clash-tproxy

# Create your configuration directory
mkdir -p ./config/{hooks/config,fireqos,mihomo}

# Copy example configurations
cp examples/config/hooks/traffic-marking.conf ./config/hooks/config/
cp examples/config/fireqos/fireqos.conf ./config/fireqos/
```

### 2. Docker Compose Setup

```yaml
version: '3.8'
services:
  mihomo:
    build: .
    # or use: image: your-registry/mihomo:latest
    container_name: mihomo
    restart: unless-stopped
    network_mode: host
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    volumes:
      - ./config:/config
    environment:
      - TZ=Asia/Shanghai
      - EN_MODE=tproxy
      # Add other environment variables as needed
```

### 3. Configuration

1. **Edit Mihomo configuration**: `./config/mihomo/config.yaml`
2. **Customize traffic marking**: `./config/hooks/config/traffic-marking.conf`
3. **Configure QoS (optional)**: `./config/fireqos/fireqos.conf`

## Features

### Hook System

The container includes a comprehensive hook system for customization:

- **post-init**: System configuration and traffic marking
- **pre-mihomo**: Configuration validation before service start
- **post-mihomo**: Health checks and notifications after service start

### Traffic Marking

Advanced nftables-based traffic marking for QoS:

- **DMAC-based marking**: Mark packets by destination MAC address
- **Multi-layer marking**: Complex L2/L3 conditions (MAC + IP + port + protocol)
- **FireQOS integration**: Seamless integration with FireQOS for bandwidth management
- **Solves limitations**: Enables mixing L2/L3 conditions that FireQOS can't handle directly

### Built-in Tools

- Configuration validation
- Traffic marking test tools
- Health check scripts
- Example configurations

## Usage Examples

### Traffic Marking for Gaming

```bash
# In traffic-marking.conf
DMAC_RULES="
    aa:bb:cc:dd:ee:01:0x10:PlayStation 5
    aa:bb:cc:dd:ee:02:0x11:Xbox Series X
"

ADVANCED_RULES="
    0x100:Gaming UDP:dmac=aa:bb:cc:dd:ee:01,proto=udp
    0x101:Steam Gaming:src=192.168.1.0/24,dport=27015:27030,proto=udp
"
```

```bash
# In fireqos.conf
class gaming commit 100mbit prio 1 ceil 300mbit
    match mark 0x10 0x11 0x100 0x101
```

### Work Traffic Prioritization

```bash
# Mark work devices and applications
ADVANCED_RULES="
    0x400:Work HTTPS:smac=cc:dd:ee:ff:00:01,dport=443,proto=tcp
    0x401:SSH Access:smac=cc:dd:ee:ff:00:01,dport=22,proto=tcp
    0x402:VPN Traffic:src=192.168.1.0/24,dport=1194,proto=udp
"
```

### IoT Device Management

```bash
# Limit IoT device bandwidth
DMAC_RULES="
    ee:ff:00:11:22:01:0x50:Security Camera
    ee:ff:00:11:22:02:0x51:Smart Doorbell
"

# In FireQOS
class iot commit 5mbit prio 7 ceil 15mbit
    match mark 0x50 0x51
```

## Debugging and Monitoring

### Check Traffic Marking

```bash
# View nftables rules
docker exec mihomo nft list tables
docker exec mihomo nft list table inet qos_marking

# Test specific marks
docker exec mihomo /usr/share/mihomo/examples/hooks/tools/test-traffic-marking.sh test 0x10

# Monitor traffic in real-time
docker exec mihomo nft monitor
```

### Verify Hook Execution

```bash
# Check container logs for hook execution
docker logs mihomo | grep "user-hooks"

# Manually run hooks for testing
docker exec mihomo /config/hooks/post-init/02-direct-nft.sh --config=/config/hooks/config/nft-traffic-marking.nft
```

### FireQOS Status

```bash
# Check FireQOS status (if configured)
docker exec mihomo fireqos status

# View traffic classes
docker exec mihomo fireqos show
```

## Customization

### Adding Custom Hooks

1. Create your script in `/config/hooks/{stage}/`
2. Make it executable: `chmod +x your-script.sh`
3. Use numeric prefixes for execution order: `01-`, `02-`, etc.

### Custom Traffic Marking

1. Edit `/config/hooks/config/traffic-marking.conf`
2. Add your device MAC addresses and IP ranges
3. Define custom mark values and priorities
4. Update FireQOS configuration to use the marks

### Environment Variables

Common environment variables:

```bash
# Hook system
HOOK_DEBUG=true              # Enable debug logging
HOOK_MAX_RETRIES=3          # Global retry count
HOOK_TIMEOUT=300            # Global timeout

# Traffic marking
DMAC_RULES="..."            # Override DMAC rules
ADVANCED_RULES="..."        # Override advanced rules
```

## Troubleshooting

### Common Issues

1. **Hooks not executing**: Check file permissions and container logs
2. **Traffic marking not working**: Verify MAC addresses and network ranges
3. **FireQOS not applying**: Check mark values match between configs
4. **Permission errors**: Ensure container has NET_ADMIN capability

### Getting Help

1. Check container logs: `docker logs mihomo`
2. Review hook execution: Look for traffic marking messages
3. Test configurations: Use provided debugging tools
4. Verify network setup: Check nftables rules and FireQOS status

## Contributing

When contributing examples:

1. Place configuration examples in `examples/config/`
2. Include comprehensive documentation
3. Test configurations in realistic scenarios
4. Follow the existing naming conventions

## License

Same as the main project.
