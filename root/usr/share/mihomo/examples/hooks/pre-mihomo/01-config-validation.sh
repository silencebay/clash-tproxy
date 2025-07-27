#!/bin/bash
# HOOK_NAME: Mihomo Configuration Validation
# HOOK_DESCRIPTION: Validate mihomo configuration before starting the service
# HOOK_TIMEOUT: 30
# HOOK_RETRY: 1
# HOOK_CRITICAL: true

set -eu

echo "=== Pre-Mihomo Hook: Configuration Validation ==="

CONFIG_DIR="/config/mihomo"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"

# 检查配置文件是否存在
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ Configuration file not found: $CONFIG_FILE"
    exit 1
fi

echo "✓ Configuration file found: $CONFIG_FILE"

# 验证配置文件语法
echo "Validating configuration syntax..."
if /usr/local/bin/mihomo -t -d "$CONFIG_DIR"; then
    echo "✓ Configuration validation passed"
else
    echo "❌ Configuration validation failed"
    exit 1
fi

# 检查必要的数据文件
echo "Checking required data files..."
for file in "country.mmdb" "geoip.dat" "geosite.dat"; do
    if [[ -f "${CONFIG_DIR}/${file}" ]]; then
        echo "✓ Found: ${file}"
    else
        echo "⚠ Missing: ${file} (will be downloaded automatically)"
    fi
done

# 示例：备份当前配置
echo "Creating configuration backup..."
cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

echo "Pre-mihomo configuration validation completed"
