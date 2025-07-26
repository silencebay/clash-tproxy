#!/bin/bash
# Traffic Marking Test Tool (nftables)
# This script helps test and debug traffic marking rules using nftables

set -eu

MARK_TABLE_DMAC="qos_marking"
MARK_TABLE_ADVANCED="qos_advanced_marking"
MARK_CHAIN_DMAC="dmac_marking"
MARK_CHAIN_ADVANCED="advanced_marking"

log() {
    echo "[test-marking] $1"
}

log_error() {
    echo "[test-marking] ERROR: $1" >&2
}

# 显示当前标记规则
show_marking_rules() {
    log "=== Current Traffic Marking Rules (nftables) ==="

    # DMAC 标记规则
    if nft list table inet "$MARK_TABLE_DMAC" >/dev/null 2>&1; then
        log ""
        log "DMAC Marking Rules:"
        log "==================="
        nft list table inet "$MARK_TABLE_DMAC"
    else
        log "⚠ DMAC marking table not found: $MARK_TABLE_DMAC"
    fi

    # 高级标记规则
    if nft list table inet "$MARK_TABLE_ADVANCED" >/dev/null 2>&1; then
        log ""
        log "Advanced Marking Rules:"
        log "======================="
        nft list table inet "$MARK_TABLE_ADVANCED"
    else
        log "⚠ Advanced marking table not found: $MARK_TABLE_ADVANCED"
    fi
}

# 显示标记统计
show_marking_stats() {
    log ""
    log "=== Traffic Marking Statistics (nftables) ==="

    # 检查 DMAC 表的统计
    if nft list table inet "$MARK_TABLE_DMAC" >/dev/null 2>&1; then
        log ""
        log "DMAC Marking Statistics:"
        log "========================"
        nft list table inet "$MARK_TABLE_DMAC" | grep -E "counter|packets|bytes"
    fi

    # 检查高级表的统计
    if nft list table inet "$MARK_TABLE_ADVANCED" >/dev/null 2>&1; then
        log ""
        log "Advanced Marking Statistics:"
        log "============================"
        nft list table inet "$MARK_TABLE_ADVANCED" | grep -E "counter|packets|bytes"
    fi
}

# 测试特定标记
test_mark() {
    local mark="$1"
    log ""
    log "=== Testing Mark: $mark ==="

    # 在所有标记表中查找该标记
    local found=false

    for table in "$MARK_TABLE_DMAC" "$MARK_TABLE_ADVANCED"; do
        if nft list table inet "$table" >/dev/null 2>&1; then
            local rules=$(nft list table inet "$table" | grep "meta mark set $mark")
            if [[ -n "$rules" ]]; then
                log "Found in table $table:"
                echo "$rules"
                found=true
            fi
        fi
    done

    if [[ "$found" == "false" ]]; then
        log "⚠ Mark $mark not found in any marking table"
    fi
}

# 清零统计计数器
reset_counters() {
    log "=== Resetting Traffic Marking Counters (nftables) ==="

    for table in "$MARK_TABLE_DMAC" "$MARK_TABLE_ADVANCED"; do
        if nft list table inet "$table" >/dev/null 2>&1; then
            # nftables 没有直接的清零命令，需要重新创建规则
            log "⚠ nftables doesn't support counter reset directly"
            log "To reset counters, you need to recreate the rules"
            log "Consider rerunning the marking hooks to refresh rules"
        fi
    done
}

# 显示 FireQOS 集成建议
show_fireqos_integration() {
    log ""
    log "=== FireQOS Integration Suggestions ==="
    log ""
    log "Based on current marking rules, here's a suggested fireqos.conf structure:"
    log ""
    log "interface eth0 world output"
    
    # 分析现有标记并生成建议
    local marks=()

    for table in "$MARK_TABLE_DMAC" "$MARK_TABLE_ADVANCED"; do
        if nft list table inet "$table" >/dev/null 2>&1; then
            while IFS= read -r line; do
                if [[ "$line" =~ meta[[:space:]]+mark[[:space:]]+set[[:space:]]+([0-9a-fA-Fx]+) ]]; then
                    marks+=("${BASH_REMATCH[1]}")
                fi
            done < <(nft list table inet "$table")
        fi
    done
    
    # 去重并排序
    IFS=$'\n' sorted_marks=($(printf '%s\n' "${marks[@]}" | sort -u))
    
    if [[ ${#sorted_marks[@]} -gt 0 ]]; then
        log "  # High priority class"
        log "  class high_priority"
        log "    match mark ${sorted_marks[0]}"
        log "    commit 50mbit prio 1"
        log ""
        log "  # Medium priority class"
        log "  class medium_priority"
        if [[ ${#sorted_marks[@]} -gt 1 ]]; then
            log "    match mark ${sorted_marks[1]}"
        fi
        log "    commit 30mbit prio 2"
        log ""
        log "  # Add more classes as needed..."
    else
        log "  # No marking rules found - please set up marking first"
    fi
    
    log ""
    log "Customize the above based on your specific requirements."
}

# 主菜单
show_menu() {
    log ""
    log "=== Traffic Marking Test Tool ==="
    log "1. Show marking rules"
    log "2. Show marking statistics"
    log "3. Test specific mark"
    log "4. Reset counters"
    log "5. Show FireQOS integration"
    log "6. Exit"
    log ""
}

# 主函数
main() {
    if [[ $# -gt 0 ]]; then
        case "$1" in
            "rules") show_marking_rules ;;
            "stats") show_marking_stats ;;
            "test") 
                if [[ $# -gt 1 ]]; then
                    test_mark "$2"
                else
                    log_error "Usage: $0 test <mark>"
                fi
                ;;
            "reset") reset_counters ;;
            "fireqos") show_fireqos_integration ;;
            *) 
                log_error "Unknown command: $1"
                log "Usage: $0 [rules|stats|test <mark>|reset|fireqos]"
                exit 1
                ;;
        esac
        exit 0
    fi
    
    # 交互模式
    while true; do
        show_menu
        read -p "[test-marking] Choose an option (1-6): " choice
        
        case "$choice" in
            1) show_marking_rules ;;
            2) show_marking_stats ;;
            3) 
                read -p "Enter mark to test (e.g., 0x10): " mark
                test_mark "$mark"
                ;;
            4) reset_counters ;;
            5) show_fireqos_integration ;;
            6) 
                log "Goodbye!"
                exit 0
                ;;
            *) log_error "Invalid choice. Please select 1-6." ;;
        esac
        
        read -p "Press Enter to continue..."
    done
}

main "$@"
