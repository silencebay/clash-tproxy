#!/bin/bash
# Traffic Marking Test Tool (nftables)
# This script helps test and debug traffic marking rules using nftables
# Works with 02-direct-nft.sh generated configurations

set -eu

# Default table name (can be overridden)
DEFAULT_MARK_TABLE="traffic_marking"

log() {
    echo "[test-marking] $1"
}

log_error() {
    echo "[test-marking] ERROR: $1" >&2
}

# 显示当前标记规则
show_marking_rules() {
    local table_name="${1:-$DEFAULT_MARK_TABLE}"

    log "=== Current Traffic Marking Rules (nftables) ==="
    log "Table: $table_name"

    if nft list table inet "$table_name" >/dev/null 2>&1; then
        log ""
        log "Traffic Marking Rules:"
        log "====================="
        nft list table inet "$table_name"
    else
        log "⚠ Traffic marking table not found: $table_name"
        log ""
        log "Available tables:"
        nft list tables | grep -E "table.*inet" || log "No inet tables found"
    fi
}

# 显示标记统计
show_marking_stats() {
    local table_name="${1:-$DEFAULT_MARK_TABLE}"

    log ""
    log "=== Traffic Marking Statistics (nftables) ==="
    log "Table: $table_name"

    if nft list table inet "$table_name" >/dev/null 2>&1; then
        log ""
        log "Marking Statistics:"
        log "=================="
        nft list table inet "$table_name" | grep -E "counter|packets|bytes" || log "No statistics available"
    else
        log "⚠ Table not found: $table_name"
    fi
}

# 测试特定标记
test_mark() {
    local mark="$1"
    local table_name="${2:-$DEFAULT_MARK_TABLE}"

    log ""
    log "=== Testing Mark: $mark ==="
    log "Table: $table_name"

    if nft list table inet "$table_name" >/dev/null 2>&1; then
        local rules=$(nft list table inet "$table_name" | grep -E "meta mark set.*$mark")
        if [[ -n "$rules" ]]; then
            log "Found rules with mark $mark:"
            echo "$rules"
        else
            log "⚠ Mark $mark not found in table $table_name"
        fi
    else
        log "⚠ Table not found: $table_name"
    fi
}

# 清零统计计数器
reset_counters() {
    local table_name="${1:-$DEFAULT_MARK_TABLE}"

    log "=== Resetting Traffic Marking Counters (nftables) ==="
    log "Table: $table_name"

    if nft list table inet "$table_name" >/dev/null 2>&1; then
        log "⚠ nftables doesn't support counter reset directly"
        log "To reset counters, you need to recreate the rules"
        log "Consider rerunning: 02-direct-nft.sh --config=nft-traffic-marking.nft --cleanup"
    else
        log "⚠ Table not found: $table_name"
    fi
}

# 显示 FireQOS 集成建议
show_fireqos_integration() {
    local table_name="${1:-$DEFAULT_MARK_TABLE}"

    log ""
    log "=== FireQOS Integration Suggestions ==="
    log "Table: $table_name"
    log ""
    log "Based on current marking rules, here's a suggested fireqos.conf structure:"
    log ""
    log "interface eth0 world output"

    # 分析现有标记并生成建议
    local marks=()

    if nft list table inet "$table_name" >/dev/null 2>&1; then
        while IFS= read -r line; do
            if [[ "$line" =~ meta[[:space:]]+mark[[:space:]]+set[[:space:]]+\(meta[[:space:]]+mark[[:space:]]+\|[[:space:]]+([0-9a-fA-Fx]+)\) ]]; then
                marks+=("${BASH_REMATCH[1]}")
            fi
        done < <(nft list table inet "$table_name")
    else
        log "⚠ Table not found: $table_name"
        return 1
    fi
    
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
    local table_name="$DEFAULT_MARK_TABLE"

    # Parse table name option
    if [[ $# -gt 0 && "$1" == "--table" ]]; then
        if [[ $# -gt 1 ]]; then
            table_name="$2"
            shift 2
        else
            log_error "Usage: $0 --table <table_name> [command]"
            exit 1
        fi
    fi

    if [[ $# -gt 0 ]]; then
        case "$1" in
            "rules") show_marking_rules "$table_name" ;;
            "stats") show_marking_stats "$table_name" ;;
            "test")
                if [[ $# -gt 1 ]]; then
                    test_mark "$2" "$table_name"
                else
                    log_error "Usage: $0 [--table <table>] test <mark>"
                fi
                ;;
            "reset") reset_counters "$table_name" ;;
            "fireqos") show_fireqos_integration "$table_name" ;;
            *)
                log_error "Unknown command: $1"
                log "Usage: $0 [--table <table>] [rules|stats|test <mark>|reset|fireqos]"
                exit 1
                ;;
        esac
        exit 0
    fi
    
    # 交互模式
    log "Using table: $table_name"
    log ""

    while true; do
        show_menu
        read -p "[test-marking] Choose an option (1-6): " choice

        case "$choice" in
            1) show_marking_rules "$table_name" ;;
            2) show_marking_stats "$table_name" ;;
            3)
                read -p "Enter mark to test (e.g., 0x10000): " mark
                test_mark "$mark" "$table_name"
                ;;
            4) reset_counters "$table_name" ;;
            5) show_fireqos_integration "$table_name" ;;
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
