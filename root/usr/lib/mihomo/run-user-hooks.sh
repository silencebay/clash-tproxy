#!/bin/bash
set -eu

HOOK_STAGE="${1:-pre}"
HOOK_CRITICAL="${2:-true}"  # 是否为关键阶段，关键阶段失败会停止容器
HOOK_DIR="/config/hooks/${HOOK_STAGE}"

# 配置参数
HOOK_MAX_RETRIES="${HOOK_MAX_RETRIES:-1}"
HOOK_RETRY_DELAY="${HOOK_RETRY_DELAY:-5}"
HOOK_TIMEOUT="${HOOK_TIMEOUT:-300}"  # 5分钟超时

log() {
    local level="${2:-INFO}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [user-hooks-${HOOK_STAGE}] [$level] $1"
}

log_error() {
    log "$1" "ERROR"
}

log_warn() {
    log "$1" "WARN"
}

log_debug() {
    if [[ "${HOOK_DEBUG:-false}" == "true" ]]; then
        log "$1" "DEBUG"
    fi
}

# 解析 hook 脚本的元数据
parse_hook_metadata() {
    local hook_file="$1"
    local metadata_line

    # 读取脚本开头的元数据注释
    while IFS= read -r line; do
        if [[ "$line" =~ ^#[[:space:]]*HOOK_([A-Z_]+):[[:space:]]*(.+)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            case "$key" in
                "TIMEOUT") HOOK_SCRIPT_TIMEOUT="$value" ;;
                "RETRY") HOOK_SCRIPT_RETRIES="$value" ;;
                "CRITICAL") HOOK_SCRIPT_CRITICAL="$value" ;;
                "NAME") HOOK_SCRIPT_NAME="$value" ;;
                "DESCRIPTION") HOOK_SCRIPT_DESCRIPTION="$value" ;;
            esac
        elif [[ ! "$line" =~ ^#.*$ ]] && [[ -n "$line" ]]; then
            # 遇到非注释行，停止解析
            break
        fi
    done < "$hook_file"
}

# 带重试和超时的 hook 执行函数
execute_hook_with_retry() {
    local hook="$1"
    local hook_name="$(basename "$hook")"
    local max_retries="${HOOK_SCRIPT_RETRIES:-$HOOK_MAX_RETRIES}"
    local retry_delay="${HOOK_RETRY_DELAY}"
    local timeout="${HOOK_SCRIPT_TIMEOUT:-$HOOK_TIMEOUT}"
    local is_critical="${HOOK_SCRIPT_CRITICAL:-$HOOK_CRITICAL}"

    log_debug "Hook metadata: retries=$max_retries, timeout=$timeout, critical=$is_critical"

    for ((i=1; i<=max_retries; i++)); do
        log "Executing hook: ${hook_name} (attempt $i/$max_retries)"

        # 使用 timeout 命令执行 hook
        if timeout "$timeout" "$hook"; then
            log "Hook ${hook_name} completed successfully"
            return 0
        else
            local exit_code=$?

            if [[ $exit_code -eq 124 ]]; then
                log_error "Hook ${hook_name} timed out after ${timeout} seconds"
            else
                log_error "Hook ${hook_name} failed with exit code ${exit_code}"
            fi

            if [[ $i -lt $max_retries ]]; then
                log_warn "Retrying hook ${hook_name} in ${retry_delay} seconds..."
                sleep "$retry_delay"
            fi
        fi
    done

    # 所有重试都失败了
    if [[ "$is_critical" == "true" ]]; then
        log_error "Critical hook ${hook_name} failed after $max_retries attempts, stopping container"
        return 1
    else
        log_warn "Non-critical hook ${hook_name} failed after $max_retries attempts, continuing"
        return 0
    fi
}

if [[ ! -d "${HOOK_DIR}" ]]; then
    log "Hook directory ${HOOK_DIR} not found, skipping"
    exit 0
fi

log "Running ${HOOK_STAGE} hooks from ${HOOK_DIR}"

shopt -s nullglob
hook_files=("${HOOK_DIR}"/*)

if [[ ${#hook_files[@]} -eq 0 ]]; then
    log "No hooks found in ${HOOK_DIR}"

    # 如果是 pre-mihomo 阶段且没有用户 hooks，运行内置配置验证
    if [[ "$HOOK_STAGE" == "pre-mihomo" ]]; then
        log "Running built-in configuration validation..."
        if /usr/lib/mihomo/validate-config.sh; then
            log "Built-in configuration validation completed successfully"
        else
            log_error "Built-in configuration validation failed"
            exit 1
        fi
    fi

    exit 0
fi

# Sort hooks by filename for predictable execution order
IFS=$'\n' sorted_hooks=($(sort <<<"${hook_files[*]}"))
unset IFS

for hook in "${sorted_hooks[@]}"; do
    if [[ -f "${hook}" && -x "${hook}" ]]; then
        # 重置脚本级别的元数据变量
        HOOK_SCRIPT_TIMEOUT=""
        HOOK_SCRIPT_RETRIES=""
        HOOK_SCRIPT_CRITICAL=""
        HOOK_SCRIPT_NAME=""
        HOOK_SCRIPT_DESCRIPTION=""

        # 解析 hook 脚本的元数据
        parse_hook_metadata "$hook"

        hook_name="$(basename "$hook")"
        if [[ -n "$HOOK_SCRIPT_NAME" ]]; then
            log "Starting hook: $HOOK_SCRIPT_NAME ($hook_name)"
            if [[ -n "$HOOK_SCRIPT_DESCRIPTION" ]]; then
                log_debug "Description: $HOOK_SCRIPT_DESCRIPTION"
            fi
        else
            log "Starting hook: $hook_name"
        fi

        # 执行 hook 脚本
        if ! execute_hook_with_retry "$hook"; then
            log_error "Hook execution failed, stopping"
            exit 1
        fi

    elif [[ -f "${hook}" ]]; then
        log_warn "Hook $(basename "${hook}") is not executable, skipping"
    fi
done

log "All ${HOOK_STAGE} hooks completed successfully"