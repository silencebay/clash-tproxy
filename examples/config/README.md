# Configuration Examples

This directory contains example configuration files for the Mihomo container's traffic marking and QoS system.

## Directory Structure

```
examples/config/
├── hooks/
│   └── traffic-marking.conf     # Traffic marking configuration
├── fireqos/
│   └── fireqos.conf             # FireQOS configuration example
└── README.md                    # This file
```

## Quick Setup

### 1. Copy Configuration Files

```bash
# Create config directories in your container volume
mkdir -p /path/to/your/config/{hooks/config,fireqos}

# Copy traffic marking configuration
cp examples/config/hooks/traffic-marking.conf /path/to/your/config/hooks/config/

# Copy FireQOS configuration (optional)
cp examples/config/fireqos/fireqos.conf /path/to/your/config/fireqos/
```

### 2. Customize for Your Network

Edit `/path/to/your/config/hooks/config/traffic-marking.conf`:

```bash
# Replace example MAC addresses with your actual device MACs
# Find device MACs with:
ip neighbor show
# or check your router's DHCP client list

# Update IP ranges to match your network
# Common ranges: 192.168.1.0/24, 192.168.0.0/24, 10.0.0.0/24
```

### 3. Docker Compose Example

```yaml
version: '3.8'
services:
  mihomo:
    image: your-mihomo-image
    volumes:
      - ./config:/config
    # ... other configuration
```

Your local directory structure should be:
```
./config/
├── hooks/
│   └── config/
│       └── traffic-marking.conf
├── fireqos/
│   └── fireqos.conf
└── mihomo/
    └── config.yaml
```

## Configuration Files

### traffic-marking.conf

This file configures nftables-based traffic marking rules that run during container startup.

**Key sections:**
- `DMAC_RULES`: Mark packets based on destination MAC addresses
- `ADVANCED_RULES`: Complex multi-layer matching (MAC + IP + port + protocol)

**Priority scheme:**
- `0x10-0x1F`: Gaming devices (highest priority)
- `0x20-0x2F`: Streaming devices (high priority)
- `0x30-0x3F`: Work devices (medium-high priority)
- `0x40-0x4F`: Mobile devices (medium priority)
- `0x50-0x5F`: IoT devices (low priority)
- `0x100+`: Advanced rules with specific conditions

### fireqos.conf

Example FireQOS configuration that uses the traffic marks set by the hooks.

**Features:**
- Separate upload/download bandwidth management
- 8-tier priority system
- Guaranteed minimum bandwidth with burst capability
- Optimized for different traffic types

## Finding Device Information

### MAC Addresses

```bash
# Method 1: ARP table
ip neighbor show

# Method 2: Network scan
nmap -sn 192.168.1.0/24

# Method 3: Router interface
# Check your router's DHCP client list or connected devices page
```

### Network Ranges

```bash
# Find your network range
ip route | grep -E "192\.168|10\.|172\."

# Common home network ranges:
192.168.1.0/24    # 192.168.1.1 - 192.168.1.254
192.168.0.0/24    # 192.168.0.1 - 192.168.0.254
10.0.0.0/24       # 10.0.0.1 - 10.0.0.254
```

## Testing and Debugging

### Verify Traffic Marking

```bash
# Check if rules are loaded
docker exec mihomo nft list tables

# View specific marking table
docker exec mihomo nft list table inet qos_marking

# Test specific mark
docker exec mihomo /usr/share/mihomo/examples/hooks/tools/test-traffic-marking.sh test 0x10
```

### Monitor Traffic

```bash
# Real-time nftables monitoring
docker exec mihomo nft monitor

# FireQOS status (if configured)
docker exec mihomo fireqos status
```

### Common Issues

1. **Rules not applying**: Check MAC address format and container logs
2. **Wrong network range**: Verify your actual network subnet
3. **Port conflicts**: Ensure port ranges don't conflict with system services
4. **Marks not working in FireQOS**: Verify mark values match between configs

## Advanced Usage

### Custom Mark Schemes

You can create your own marking schemes:

```bash
# Department-based
0x100-0x1FF: Engineering
0x200-0x2FF: Marketing
0x300-0x3FF: Management

# VLAN-based
0x10: VLAN 10 devices
0x20: VLAN 20 devices
0x30: Guest network
```

### Dynamic Configuration

For environments with changing devices:
- Use IP ranges instead of specific MAC addresses
- Create rules based on subnets or VLANs
- Use application ports rather than device-specific rules

### Integration

The traffic marks work with:
- **FireQOS** (primary use case)
- **tc** (Linux traffic control)
- **nftables** (for additional processing)
- **Monitoring tools** (for traffic analysis)

## Support

For issues:
1. Check container logs: `docker logs mihomo`
2. Verify hook execution: Look for traffic marking messages in logs
3. Test rules: Use the provided debugging tools
4. Check nftables: Ensure rules are correctly applied
