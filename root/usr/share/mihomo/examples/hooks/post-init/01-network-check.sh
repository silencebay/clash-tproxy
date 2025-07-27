#!/bin/bash
# HOOK_NAME: System Setup and Network Check
# HOOK_DESCRIPTION: Configure system settings and verify network connectivity after initialization
# HOOK_TIMEOUT: 60
# HOOK_RETRY: 2
# HOOK_CRITICAL: false

set -eu

echo "=== Post-Init Hook: System Setup and Network Check ==="

# System setup (previously in pre-init)
echo "Setting up system parameters..."

# Create required directories
echo "Creating required directories..."
mkdir -p /config/mihomo/logs
mkdir -p /config/hooks/{post-init,pre-mihomo,post-mihomo}

# Set up permissions
echo "Setting up permissions..."
chown -R abc:users /config/mihomo/logs

# Environment checks
echo "Checking environment..."
if [[ -z "${TZ:-}" ]]; then
    echo "Warning: TZ environment variable not set, using UTC"
fi

# 示例：检查网络连接
echo "Checking network connectivity..."

# 检查基本网络接口
if ip link show eth0 >/dev/null 2>&1; then
    echo "✓ Network interface eth0 is available"
else
    echo "⚠ Network interface eth0 not found"
fi

# 检查 DNS 解析
echo "Testing DNS resolution..."
if nslookup google.com >/dev/null 2>&1; then
    echo "✓ DNS resolution working"
else
    echo "⚠ DNS resolution failed"
fi

# 示例：设置自定义路由规则
echo "Setting up custom routing rules..."
# ip route add ... (示例，根据需要修改)

echo "Post-init system setup and network check completed"
