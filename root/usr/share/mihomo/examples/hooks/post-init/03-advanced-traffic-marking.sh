#!/bin/bash
# HOOK_NAME: Advanced Traffic Marking (nftables)
# HOOK_DESCRIPTION: Mark packets based on complex L2/L3 conditions for QoS classification using nftables
# HOOK_TIMEOUT: 45
# HOOK_RETRY: 2
# HOOK_CRITICAL: false
#
# NOTE: This hook runs in post-init stage, BEFORE init-network sets up TProxy rules.
# This timing ensures that traffic marking rules are established before the container's
# core networking functionality (TProxy/TUN) is configured, preventing conflicts.
# Uses nftables to match the project's architecture.

set -eu

echo "=== Post-Init Hook: Advanced Traffic Marking (nftables) ==="

# 配置变量
ADVANCED_MARK_TABLE="${ADVANCED_MARK_TABLE:-qos_advanced_marking}"
ADVANCED_MARK_CHAIN="${ADVANCED_MARK_CHAIN:-advanced_marking}"

# 高级规则配置
# 支持的匹配条件:
# - dmac: 目标MAC地址
# - smac: 源MAC地址  
# - src: 源IP地址/网段
# - dst: 目标IP地址/网段
# - sport: 源端口
# - dport: 目标端口
# - proto: 协议 (tcp/udp/icmp)
# 
# 格式: "mark:description:condition1=value1,condition2=value2,..."
ADVANCED_RULES="${ADVANCED_RULES:-}"

# 默认示例规则
if [[ -z "$ADVANCED_RULES" ]]; then
    ADVANCED_RULES="
        0x100:Gaming Traffic:dmac=aa:bb:cc:dd:ee:ff,src=192.168.1.0/24,proto=udp
        0x200:Streaming Device:dmac=11:22:33:44:55:66,dport=80,proto=tcp
        0x300:High Priority LAN:smac=77:88:99:aa:bb:cc,src=192.168.1.100
        0x400:VoIP Traffic:src=192.168.1.0/24,dport=5060,proto=udp
        0x500:Video Streaming:dst=192.168.1.200,dport=8080,proto=tcp
    "
fi

log() {
    echo "[advanced-marking] $1"
}

log_error() {
    echo "[advanced-marking] ERROR: $1" >&2
}

# 检查依赖
check_dependencies() {
    local missing_tools=()

    for tool in nft; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please ensure nftables is installed"
        exit 1
    fi
}

# 设置高级标记表和链
setup_advanced_table() {
    log "Setting up advanced marking table: $ADVANCED_MARK_TABLE"

    # 清理现有表
    if nft list table inet "$ADVANCED_MARK_TABLE" >/dev/null 2>&1; then
        log "Cleaning existing table: $ADVANCED_MARK_TABLE"
        nft delete table inet "$ADVANCED_MARK_TABLE" 2>/dev/null || true
    fi

    # 创建新的标记表和链
    nft -f - <<EOF
table inet $ADVANCED_MARK_TABLE {
    chain $ADVANCED_MARK_CHAIN {
        type filter hook prerouting priority mangle; policy accept;
        # Advanced marking rules will be added here
    }

    chain postrouting_mark {
        type filter hook postrouting priority mangle; policy accept;
        # Additional postrouting rules if needed
    }
}
EOF

    if [[ $? -eq 0 ]]; then
        log "✓ Created advanced marking table and chains"
    else
        log_error "Failed to create advanced marking table"
        exit 1
    fi
}

# 构建 nftables 规则
build_nftables_rule() {
    local mark="$1"
    local conditions="$2"
    local description="$3"

    local rule_conditions=()

    # 解析条件
    IFS=',' read -ra condition_array <<< "$conditions"

    for condition in "${condition_array[@]}"; do
        if [[ "$condition" =~ ^([^=]+)=(.+)$ ]]; then
            local key="${BASH_REMATCH[1]// /}"
            local value="${BASH_REMATCH[2]// /}"

            case "$key" in
                "dmac")
                    if [[ "$value" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
                        rule_conditions+=("ether daddr $value")
                    else
                        log_error "Invalid DMAC format: $value"
                        return 1
                    fi
                    ;;
                "smac")
                    if [[ "$value" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
                        rule_conditions+=("ether saddr $value")
                    else
                        log_error "Invalid SMAC format: $value"
                        return 1
                    fi
                    ;;
                "src")
                    rule_conditions+=("ip saddr $value")
                    ;;
                "dst")
                    rule_conditions+=("ip daddr $value")
                    ;;
                "sport")
                    if [[ "$value" =~ ^[0-9]+:[0-9]+$ ]]; then
                        rule_conditions+=("th sport $value")
                    else
                        rule_conditions+=("th sport $value")
                    fi
                    ;;
                "dport")
                    if [[ "$value" =~ ^[0-9]+:[0-9]+$ ]]; then
                        rule_conditions+=("th dport $value")
                    else
                        rule_conditions+=("th dport $value")
                    fi
                    ;;
                "proto")
                    rule_conditions+=("meta l4proto $value")
                    ;;
                *)
                    log_error "Unknown condition: $key"
                    return 1
                    ;;
            esac
        else
            log_error "Invalid condition format: $condition"
            return 1
        fi
    done

    # 构建完整的 nftables 规则字符串
    local rule_string=""
    for condition in "${rule_conditions[@]}"; do
        if [[ -n "$rule_string" ]]; then
            rule_string+=" "
        fi
        rule_string+="$condition"
    done

    # 返回构建的规则
    echo "        $rule_string meta mark set $mark comment \"Advanced: $description\""
    return 0
}

# 添加高级规则
add_advanced_rules() {
    log "Adding advanced marking rules to nftables..."

    local rule_count=0
    local nft_rules=""

    while IFS= read -r rule_line; do
        # 跳过空行和注释
        [[ -z "$rule_line" || "$rule_line" =~ ^[[:space:]]*# ]] && continue

        # 解析规则: MARK:DESCRIPTION:CONDITIONS
        if [[ "$rule_line" =~ ^[[:space:]]*([^:]+):([^:]+):(.+)$ ]]; then
            local mark="${BASH_REMATCH[1]// /}"
            local desc="${BASH_REMATCH[2]// /}"
            local conditions="${BASH_REMATCH[3]// /}"

            # 验证标记格式
            if [[ ! "$mark" =~ ^0x[0-9a-fA-F]+$ ]]; then
                log_error "Invalid mark format: $mark (should be 0xNN)"
                continue
            fi

            # 构建 nftables 规则
            if rule_string=$(build_nftables_rule "$mark" "$conditions" "$desc"); then
                nft_rules+="$rule_string\n"
                log "✓ Prepared rule: $desc -> $mark"
                ((rule_count++))
            else
                log_error "Failed to build rule: $desc"
            fi

        else
            log_error "Invalid rule format: $rule_line"
            log_error "Expected format: MARK:DESCRIPTION:CONDITIONS"
        fi

    done <<< "$ADVANCED_RULES"

    if [[ $rule_count -eq 0 ]]; then
        log_error "No valid advanced rules were prepared"
        exit 1
    fi

    # 应用所有规则到 nftables
    nft -f - <<EOF
table inet $ADVANCED_MARK_TABLE {
    delete chain $ADVANCED_MARK_CHAIN

    chain $ADVANCED_MARK_CHAIN {
        type filter hook prerouting priority mangle; policy accept;
$(echo -e "$nft_rules")
    }
}
EOF

    if [[ $? -eq 0 ]]; then
        log "✓ Applied $rule_count advanced marking rules to nftables"
    else
        log_error "Failed to apply advanced rules to nftables"
        exit 1
    fi
}

# 显示规则和使用说明
show_usage() {
    log "Current advanced marking rules (nftables):"
    nft list table inet "$ADVANCED_MARK_TABLE"
    
    log ""
    log "FireQOS Integration Example:"
    log "================================"
    log "interface eth0 world output"
    log "  class gaming"
    log "    match mark 0x100  # Gaming Traffic"
    log "    commit 50mbit"
    log ""
    log "  class streaming"  
    log "    match mark 0x200  # Streaming Device"
    log "    commit 30mbit"
    log ""
    log "  class voip"
    log "    match mark 0x400  # VoIP Traffic"
    log "    commit 5mbit prio 1"
    log ""
    log "Configuration Examples:"
    log "======================"
    log "ADVANCED_RULES=\""
    log "  0x100:Gaming:dmac=aa:bb:cc:dd:ee:ff,src=192.168.1.0/24,proto=udp"
    log "  0x200:Streaming:dmac=11:22:33:44:55:66,dport=80,proto=tcp"
    log "  0x300:VoIP:src=192.168.1.0/24,dport=5060,proto=udp"
    log "\""
}

# 主执行流程
main() {
    log "Starting advanced traffic marking setup (nftables)..."

    check_dependencies
    setup_advanced_table
    add_advanced_rules
    show_usage

    log "Advanced traffic marking setup completed successfully"
    log ""
    log "To view current rules: nft list table inet $ADVANCED_MARK_TABLE"
}

main
