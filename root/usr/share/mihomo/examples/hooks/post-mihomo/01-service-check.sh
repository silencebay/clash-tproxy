#!/bin/bash
# HOOK_NAME: Mihomo Service Health Check
# HOOK_DESCRIPTION: Verify mihomo service is running correctly after startup
# HOOK_TIMEOUT: 60
# HOOK_RETRY: 3
# HOOK_CRITICAL: false

set -eu

echo "=== Post-Mihomo Hook: Service Health Check ==="

# 等待服务启动
echo "Waiting for mihomo service to start..."
sleep 5

# 检查进程是否运行
echo "Checking mihomo process..."
if pgrep -f "mihomo" >/dev/null; then
    echo "✓ Mihomo process is running"
else
    echo "❌ Mihomo process not found"
    exit 1
fi

# 检查 API 端点
echo "Checking mihomo API endpoint..."
API_PORT="${EXTERNAL_CONTROLLER_PORT:-80}"
if curl -s "http://localhost:${API_PORT}/version" >/dev/null; then
    echo "✓ Mihomo API is responding"
    
    # 获取版本信息
    VERSION=$(curl -s "http://localhost:${API_PORT}/version" | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
    echo "✓ Mihomo version: $VERSION"
else
    echo "⚠ Mihomo API not responding (this might be normal if external-controller is disabled)"
fi

# 检查代理端口
echo "Checking proxy ports..."
MIXED_PORT="${MIXED_PORT:-10801}"
if netstat -ln | grep ":${MIXED_PORT}" >/dev/null 2>&1; then
    echo "✓ Mixed port ${MIXED_PORT} is listening"
else
    echo "⚠ Mixed port ${MIXED_PORT} not found"
fi

TPROXY_PORT="${TPROXY_PORT:-7893}"
if netstat -ln | grep ":${TPROXY_PORT}" >/dev/null 2>&1; then
    echo "✓ TProxy port ${TPROXY_PORT} is listening"
else
    echo "⚠ TProxy port ${TPROXY_PORT} not found"
fi

# 示例：发送通知
echo "Sending startup notification..."
# 这里可以添加发送通知的逻辑，比如 webhook、邮件等
# curl -X POST "https://your-webhook-url" -d "Mihomo started successfully"

echo "Post-mihomo service check completed"
