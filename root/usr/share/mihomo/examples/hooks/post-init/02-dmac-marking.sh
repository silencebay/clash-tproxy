#!/bin/bash
# HOOK_NAME: DMAC Traffic Marking (nftables)
# HOOK_DESCRIPTION: Mark packets based on destination MAC address for QoS classification using nftables
# HOOK_TIMEOUT: 30
# HOOK_RETRY: 2
# HOOK_CRITICAL: false
#
# NOTE: This hook runs in post-init stage, BEFORE init-network sets up TProxy rules.
# This ensures traffic marking rules are established before the container's core
# networking functionality is configured. Uses nftables to match the project's architecture.

set -eu

echo "=== Post-Init Hook: DMAC Traffic Marking (nftables) ==="

# 配置变量 - 用户可以通过环境变量覆盖这些默认值
DMAC_MARK_TABLE="${DMAC_MARK_TABLE:-qos_marking}"
DMAC_MARK_CHAIN="${DMAC_MARK_CHAIN:-dmac_marking}"

# 配置文件路径
CONFIG_FILE="/config/hooks/config/traffic-marking.conf"

# 从配置文件或环境变量加载规则
load_dmac_rules() {
    # 优先使用环境变量
    if [[ -n "${DMAC_RULES:-}" ]]; then
        log "Using DMAC rules from environment variable"
        return 0
    fi

    # 尝试从配置文件加载
    if [[ -f "$CONFIG_FILE" ]]; then
        log "Loading DMAC rules from config file: $CONFIG_FILE"
        # 从配置文件中提取 DMAC_RULES
        if DMAC_RULES=$(grep -A 20 '^DMAC_RULES=' "$CONFIG_FILE" | sed -n '/^DMAC_RULES="/,/^"/p' | sed '1d;$d'); then
            if [[ -n "$DMAC_RULES" ]]; then
                log "✓ Loaded DMAC rules from config file"
                return 0
            fi
        fi
    fi

    # 使用默认示例规则
    log "Using default example DMAC rules"
    DMAC_RULES="
        aa:bb:cc:dd:ee:ff:0x10:High Priority Device
        11:22:33:44:55:66:0x20:Gaming Console
        77:88:99:aa:bb:cc:0x30:Streaming Device
    "
}

log() {
    echo "[dmac-marking] $1"
}

log_error() {
    echo "[dmac-marking] ERROR: $1" >&2
}

# 检查必要的工具
check_dependencies() {
    local missing_tools=()

    if ! command -v nft >/dev/null 2>&1; then
        missing_tools+=("nft")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please ensure nftables is installed"
        exit 1
    fi
}

# 创建或清理标记表和链
setup_marking_table() {
    log "Setting up nftables marking table: $DMAC_MARK_TABLE"

    # 删除现有表（如果存在）
    if nft list table inet "$DMAC_MARK_TABLE" >/dev/null 2>&1; then
        log "Cleaning existing table: $DMAC_MARK_TABLE"
        nft delete table inet "$DMAC_MARK_TABLE" 2>/dev/null || true
    fi

    # 创建新的标记表和链
    nft -f - <<EOF
table inet $DMAC_MARK_TABLE {
    chain $DMAC_MARK_CHAIN {
        type filter hook prerouting priority mangle; policy accept;
        # DMAC marking rules will be added here
    }

    chain postrouting_mark {
        type filter hook postrouting priority mangle; policy accept;
        # Additional postrouting rules if needed
    }
}
EOF

    if [[ $? -eq 0 ]]; then
        log "✓ Created nftables marking table and chains"
    else
        log_error "Failed to create nftables marking table"
        exit 1
    fi
}

# 添加 DMAC 标记规则
add_dmac_rules() {
    log "Adding DMAC marking rules to nftables..."

    local rule_count=0
    local nft_rules=""

    # 处理每条规则
    while IFS= read -r rule_line; do
        # 跳过空行和注释
        [[ -z "$rule_line" || "$rule_line" =~ ^[[:space:]]*# ]] && continue

        # 解析规则: MAC:MARK:DESCRIPTION
        if [[ "$rule_line" =~ ^[[:space:]]*([^:]+):([^:]+):(.*)$ ]]; then
            local mac="${BASH_REMATCH[1]// /}"
            local mark="${BASH_REMATCH[2]// /}"
            local desc="${BASH_REMATCH[3]// /}"

            # 验证 MAC 地址格式
            if [[ ! "$mac" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
                log_error "Invalid MAC address format: $mac"
                continue
            fi

            # 验证标记格式
            if [[ ! "$mark" =~ ^0x[0-9a-fA-F]+$ ]]; then
                log_error "Invalid mark format: $mark (should be 0xNN)"
                continue
            fi

            # 构建 nftables 规则
            nft_rules+="        ether daddr $mac meta mark set $mark comment \"DMAC: $desc\"\n"
            log "✓ Prepared rule: $mac -> $mark ($desc)"
            ((rule_count++))

        else
            log_error "Invalid rule format: $rule_line"
            log_error "Expected format: MAC:MARK:DESCRIPTION"
        fi

    done <<< "$DMAC_RULES"

    if [[ $rule_count -eq 0 ]]; then
        log_error "No valid DMAC rules were prepared"
        log "Please check your DMAC_RULES configuration"
        exit 1
    fi

    # 应用所有规则到 nftables
    nft -f - <<EOF
table inet $DMAC_MARK_TABLE {
    delete chain $DMAC_MARK_CHAIN

    chain $DMAC_MARK_CHAIN {
        type filter hook prerouting priority mangle; policy accept;
$(echo -e "$nft_rules")
    }
}
EOF

    if [[ $? -eq 0 ]]; then
        log "✓ Applied $rule_count DMAC marking rules to nftables"
    else
        log_error "Failed to apply DMAC rules to nftables"
        exit 1
    fi
}

# 显示当前规则
show_rules() {
    log "Current DMAC marking rules (nftables):"
    if nft list table inet "$DMAC_MARK_TABLE"; then
        log "✓ Rules displayed successfully"
    else
        log_error "Failed to display rules"
    fi
}

# 主执行流程
main() {
    log "Starting DMAC traffic marking setup (nftables)..."

    # 检查依赖
    check_dependencies

    # 加载规则配置
    load_dmac_rules

    # 设置标记表和链
    setup_marking_table

    # 添加 DMAC 规则
    add_dmac_rules

    # 显示当前规则
    show_rules

    log "DMAC traffic marking setup completed successfully"
    log ""
    log "Usage with FireQOS:"
    log "In your fireqos.conf, you can now match packets by their marks:"
    log "  class high_priority"
    log "    match mark 0x10  # Matches the first example rule"
    log "    commit 10mbit"
    log ""
    log "To customize rules, set the DMAC_RULES environment variable:"
    log "  DMAC_RULES=\"aa:bb:cc:dd:ee:ff:0x10:My Device\""
    log ""
    log "To view current rules: nft list table inet $DMAC_MARK_TABLE"
}

# 执行主函数
main
