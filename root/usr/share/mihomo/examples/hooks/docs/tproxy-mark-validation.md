# TProxy Mark Validation System

## Overview

The clash-tproxy system includes built-in validation to ensure TProxy marks stay within the correct bit allocation and don't conflict with custom marking systems.

## Validation Rules

### 1. Low 16 Bits Constraint
TProxy marks must use only the low 16 bits (0x0000-0xFFFF):

```bash
# ✅ Valid TProxy marks
PROXY_FWMARK=0x1        # Default
PROXY_ROUTING_MARK=0x2  # Default
PROXY_ROUTING_MARK=0xFFFF  # Maximum valid value

# ❌ Invalid TProxy marks
PROXY_ROUTING_MARK=0x10000  # Exceeds 16-bit limit
PROXY_ROUTING_MARK=0x10001  # Uses high bits
```

### 2. High Bits Conflict Check
TProxy marks cannot use high 16 bits reserved for custom marking:

```bash
# ❌ These would conflict with custom marking
PROXY_ROUTING_MARK=0x10000  # Uses bit 16
PROXY_ROUTING_MARK=0x20000  # Uses bit 17
```

## Automatic Validation

### When Validation Occurs
- **Script Load**: Every time `common.sh` is sourced
- **Early Detection**: Catches configuration errors before deployment
- **Fail-Fast**: Prevents system startup with invalid configuration

### Validation Process
```bash
# Automatic validation on common.sh load
source /usr/lib/mihomo/common.sh
# If validation fails, script exits with error code 1
```

### Error Messages
```bash
ERROR: TProxy mark PROXY_ROUTING_MARK (0x10001) exceeds low 16 bits limit (0xFFFF)
TProxy marks must stay within 0x0000-0xFFFF range to avoid conflicts
FATAL: TProxy mark validation failed. Please fix the configuration.
```

## Configuration Examples

### Valid Configurations
```bash
# Default configuration (recommended)
ROUTING_MARK=0x2

# Alternative valid values
ROUTING_MARK=0x3
ROUTING_MARK=0x100
ROUTING_MARK=0x1000
ROUTING_MARK=0xFFFF  # Maximum valid value
```

### Invalid Configurations
```bash
# These will cause validation failure
ROUTING_MARK=0x10000   # Exceeds 16-bit limit
ROUTING_MARK=0x10001   # Uses high bits + conflicts with custom marks
ROUTING_MARK=0x20000   # Uses high bits reserved for custom marking
ROUTING_MARK=65536     # Decimal equivalent of 0x10000
```

## Bit Allocation Reference

```
32-bit Mark Field (0xFFFFFFFF):
┌─────────────────┬─────────────────┐
│  High 16 bits   │  Low 16 bits    │
│  (0xFFFF0000)   │  (0x0000FFFF)   │
│  Custom Marking │  TProxy System  │
│  Available      │  Reserved       │
└─────────────────┴─────────────────┘
```

### TProxy System (Low 16 bits)
- **Range**: 0x0000 - 0xFFFF (0 - 65535)
- **PROXY_FWMARK**: 0x1 (fixed)
- **PROXY_ROUTING_MARK**: 0x2 (configurable via ROUTING_MARK)

### Custom Marking (High 16 bits)
- **Range**: 0x10000 - 0xFFFF0000
- **Usage**: QoS, firewall rules, load balancing, etc.
- **Requirement**: Must use OR operations to preserve TProxy marks

## Troubleshooting

### Validation Failure
If you encounter validation errors:

1. **Check Environment Variables**:
   ```bash
   echo $ROUTING_MARK
   ```

2. **Use Valid Range**:
   ```bash
   # Fix invalid configuration
   export ROUTING_MARK=0x2  # or any value 0x1-0xFFFF
   ```

3. **Verify Configuration**:
   ```bash
   source /usr/lib/mihomo/common.sh
   echo "Validation passed!"
   ```

### Common Mistakes
- Using decimal values > 65535
- Using hex values > 0xFFFF
- Copying values from custom marking examples
- Misunderstanding bit allocation

## Integration with Custom Marking

### Correct Approach
```bash
# TProxy marks (low 16 bits)
PROXY_FWMARK=0x1
PROXY_ROUTING_MARK=0x2

# Custom marks (high 16 bits) - separate system
meta mark set (meta mark | 0x10000)  # Gaming
meta mark set (meta mark | 0x20000)  # Streaming
```

### Why Validation Matters
- **Prevents Conflicts**: Ensures TProxy and custom systems don't interfere
- **Maintains Compatibility**: Preserves transparent proxy functionality
- **Early Detection**: Catches errors before they cause routing issues
- **System Reliability**: Ensures consistent behavior across deployments

## Best Practices

1. **Use Default Values**: Stick with PROXY_ROUTING_MARK=0x2 unless necessary
2. **Test Changes**: Always test configuration changes in development first
3. **Document Overrides**: If using custom ROUTING_MARK, document the reason
4. **Monitor Validation**: Check logs for validation messages during deployment
5. **Stay Within Limits**: Never exceed 0xFFFF for TProxy marks

## Validation Tools

### Built-in Validation
- Automatic validation in `common.sh`
- Fail-fast error handling
- Clear error messages

### External Validation
- `validate-tproxy-marks.sh`: Validates nftables configurations
- Checks custom marks for TProxy compatibility
- Ensures proper OR operation usage

This validation system ensures that the TProxy system remains robust and conflict-free while allowing full flexibility for custom marking systems.
