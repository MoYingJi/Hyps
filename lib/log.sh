#!/hint/bash

[[ -n "${__LOG_SH_LOADED:-}" ]] && return 0
__LOG_SH_LOADED=1

#shellcheck source=console.sh
source "${SCRIPT_DIR:-.}/console.sh"

LOG_LEVEL="${LOG_LEVEL:-INFO}"

declare -A _LOG_LEVELS=(
    [DEBUG]=10
    [INFO]=20
    [WARN]=30
    [ERROR]=40
)

declare -A _LOG_STYLES=(
    [DEBUG]=bright_black
    [INFO]=reset
    [WARN]=yellow
    [ERROR]=red
)

LOG_FILE="${LOG_FILE:-}"

log_should_output() {
    local level="$1"
    local level_num="${_LOG_LEVELS[$level]:-0}"
    local current_num="${_LOG_LEVELS[$LOG_LEVEL]:-20}"
    [[ $level_num -ge $current_num ]]
}

_log_write_file() {
    if [[ -n "$LOG_FILE" ]]; then
        local log_dir
        log_dir="$(dirname "$LOG_FILE")"
        [[ -d "$log_dir" ]] || mkdir -p "$log_dir" 2>/dev/null

        echo "$1" >> "$LOG_FILE" 2>/dev/null || {
            echo "[log] ERROR: 无法写入日志文件 $LOG_FILE" >&2
        }
    fi
}

log() {
    local level="$1"

    local module
    local message

    if [[ $# -gt 2 ]]; then
        module="$2"
        message="$3"
    else
        module=""
        message="$2"
    fi

    if ! log_should_output "$level"; then
        return 0
    fi

    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    local log_line
    if [[ -n "$module" ]]; then
        log_line="[$timestamp] [$level] [$module] $message"
    else
        log_line="[$timestamp] [$level] $message"
    fi

    local style_name color_code color_reset

    if use_color; then
        style_name="${_LOG_STYLES[$level]:-}"
        color_code="${_CONSOLE_STYLES[$style_name]:-}"
        color_reset="${_CONSOLE_STYLES[reset]:-}"
        printf "%s%s%s\n" "$color_code" "$log_line" "$color_reset" >&2
    else
        echo "$log_line" >&2
    fi

    _log_write_file "$log_line"
}

# 调试日志
log_debug() {
    log DEBUG "$@"
}

# 信息日志
log_info() {
    log INFO "$@"
}

# 警告日志
log_warn() {
    log WARN "$@"
}

# 错误日志
log_error() {
    log ERROR "$@"
}

# 致命错误：记录错误并退出
# 用法: die [exit_code] [message]
die() {
    local exit_code="${1:-1}"
    shift
    if [[ $# -gt 0 ]]; then
        log_error "$@"
    fi
    exit "$exit_code"
}

set_log_level() {
    local level="$1"

    if [[ -n "${_LOG_LEVELS[$level]:-}" ]]; then
        LOG_LEVEL="$level"
        log_debug "日志级别设置为 $level"
    else
        log_error "无效日志级别: $level (可用: DEBUG, INFO, WARN, ERROR)"
        return 1
    fi
}

enable_log_file() {
    LOG_FILE="$1"
    log_debug "日志文件已设置: $LOG_FILE"
}
