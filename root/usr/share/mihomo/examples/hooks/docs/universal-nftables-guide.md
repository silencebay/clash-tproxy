# Universal nftables Configuration Guide

## Overview

The `02-direct-nft.sh` script provides a universal tool for applying any nftables configuration directly from files. This approach eliminates parsing overhead and provides full access to nftables features.

## Capabilities

The script can handle any nftables configuration:

- **Traffic Marking**: QoS and bandwidth management
- **Firewall Rules**: Input/output/forward filtering
- **NAT Configuration**: Port forwarding, masquerading
- **Load Balancing**: Traffic distribution
- **Rate Limiting**: DDoS protection
- **Logging**: Traffic monitoring
- **Any nftables feature**: Sets, maps, counters, etc.

## Architecture

### Direct nftables Approach
```
nftables Config (.nft) → Direct Apply
   (~200 lines, full nftables support)
```

**Benefits:**
- Zero parsing overhead
- Full nftables feature access
- Easy debugging with standard tools
- Minimal code to maintain

## Usage Examples

### 1. Traffic Marking
```bash
# Apply traffic marking rules
./02-direct-nft.sh --config=/config/nft-traffic-marking.nft

# Preview first
./02-direct-nft.sh --config=/config/nft-traffic-marking.nft --dry-run
```

### 2. Firewall Configuration
```bash
# Apply firewall rules with cleanup
./02-direct-nft.sh --config=/config/nft-firewall.nft --cleanup --debug

# Environment variable approach
export HOOKS_DIRECT_NFT_CONFIG="/config/nft-firewall.nft"
export HOOKS_DIRECT_NFT_CLEANUP=true
./02-direct-nft.sh
```

### 3. NAT Setup
```bash
# Apply NAT rules
./02-direct-nft.sh --config=/config/nft-nat.nft

# Combined with other configurations
./02-direct-nft.sh --config=/config/nft-firewall.nft
./02-direct-nft.sh --config=/config/nft-nat.nft
./02-direct-nft.sh --config=/config/nft-traffic-marking.nft
```

## Configuration Examples

### Traffic Marking (nft-traffic-marking.nft)
```nftables
table inet traffic_marking {
    set gaming_devices {
        type ether_addr
        elements = { aa:bb:cc:dd:ee:01, aa:bb:cc:dd:ee:02 }
    }
    
    chain prerouting_mark {
        type filter hook prerouting priority mangle; policy accept;
        ether daddr @gaming_devices meta mark set (meta mark | 0x100000)
    }
}
```

### Firewall Rules (nft-firewall.nft)
```nftables
table inet firewall {
    set trusted_networks {
        type ipv4_addr
        flags interval
        elements = { 192.168.0.0/16, 10.0.0.0/8 }
    }
    
    chain input {
        type filter hook input priority filter; policy drop;
        ct state established,related accept
        ip saddr @trusted_networks accept
        tcp dport { 22, 80, 443 } accept
    }
}
```

### NAT Configuration (nft-nat.nft)
```nftables
table ip nat {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        tcp dport 80 dnat to 192.168.1.100:80
    }
    
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "eth0" masquerade
    }
}
```

## Advanced Features

### 1. Sets and Maps
```nftables
table inet advanced {
    set blocked_ips {
        type ipv4_addr
        flags interval, timeout
        elements = { 1.2.3.0/24 timeout 1h }
    }
    
    map port_redirect {
        type inet_service : ipv4_addr . inet_service
        elements = { 80 : 192.168.1.100 . 8080 }
    }
}
```

### 2. Counters and Statistics
```nftables
table inet monitoring {
    counter web_traffic
    counter gaming_traffic
    
    chain input {
        type filter hook input priority filter; policy accept;
        tcp dport 80 counter name web_traffic accept
        udp dport 27015-27030 counter name gaming_traffic accept
    }
}
```

### 3. Rate Limiting
```nftables
table inet protection {
    chain input {
        type filter hook input priority filter; policy drop;
        tcp dport 22 ct state new limit rate 3/minute burst 3 packets accept
        tcp dport 80 limit rate 100/second burst 200 packets accept
    }
}
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `HOOKS_DIRECT_NFT_CONFIG` | Configuration file path | `/config/hooks/config/nft-traffic-marking.nft` |
| `HOOKS_DIRECT_NFT_CLEANUP` | Clean existing rules | `false` |
| `HOOKS_DIRECT_NFT_DEBUG` | Enable debug logging | `false` |
| `HOOKS_DIRECT_NFT_DRY_RUN` | Preview without applying | `false` |

## Best Practices

### 1. Configuration Organization
```
/config/hooks/config/
├── nft-firewall.nft       # Security rules
├── nft-nat.nft            # NAT configuration
├── nft-traffic-marking.nft # QoS rules
└── nft-monitoring.nft     # Logging and stats
```

### 2. Testing Workflow
```bash
# 1. Always preview first
./02-direct-nft.sh --config=config.nft --dry-run

# 2. Test with debug
./02-direct-nft.sh --config=config.nft --debug

# 3. Apply with cleanup if needed
./02-direct-nft.sh --config=config.nft --cleanup
```

### 3. Error Handling
- Use `--dry-run` to validate syntax
- Enable `--debug` for troubleshooting
- Check logs: `journalctl -f` or `dmesg`
- Verify rules: `nft list tables`

## Configuration Best Practices

### 1. TProxy Compatibility
When creating traffic marking rules, always use OR operations to preserve TProxy marks:

```nftables
# Correct: Preserves TProxy marks
ether daddr aa:bb:cc:dd:ee:01 meta mark set (meta mark | 0x10000) comment "Gaming PC"

# Wrong: Overwrites TProxy marks
ether daddr aa:bb:cc:dd:ee:01 meta mark set 0x10000 comment "Gaming PC"
```

### 2. Mark Allocation
Use high 16 bits for custom marks to avoid TProxy conflicts:
- Low 16 bits (0x0000FFFF): Reserved for TProxy
- High 16 bits (0xFFFF0000): Available for custom marking

## Advantages

1. **Universal**: Handles any nftables configuration
2. **Performance**: Zero parsing overhead
3. **Features**: Full nftables capability
4. **Debugging**: Standard tools work
5. **Maintenance**: Minimal code to maintain
6. **Flexibility**: Easy to extend and customize
7. **Standards**: Uses official nftables syntax

## Conclusion

The universal nftables approach provides maximum flexibility while minimizing complexity. Instead of maintaining multiple specialized scripts, we have one powerful tool that handles all nftables scenarios efficiently.
