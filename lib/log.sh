#!/hint/bash

[[ -n "${__LOG_SH_LOADED:-}" ]] && return 0
__LOG_SH_LOADED=1

LOG_LEVEL="${LOG_LEVEL:-INFO}"

declare -A _LOG_LEVELS=(
    [DEBUG]=10
    [INFO]=20
    [WARN]=30
    [ERROR]=40
)

if [[ -t 2 ]] && [[ -z "${LOG_NO_COLOR:-}" ]]; then
    _LOG_COLOR_RESET=$'\033[0m'
    _LOG_COLOR_DEBUG=$'\033[90m'   # 灰色
    _LOG_COLOR_INFO=$'\033[0m'     # 默认
    _LOG_COLOR_WARN=$'\033[33m'    # 黄色
    _LOG_COLOR_ERROR=$'\033[31m'   # 红色
else
    _LOG_COLOR_RESET=""
    _LOG_COLOR_DEBUG=""
    _LOG_COLOR_INFO=""
    _LOG_COLOR_WARN=""
    _LOG_COLOR_ERROR=""
fi

LOG_FILE="${LOG_FILE:-}"

_log_should_output() {
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

    if ! _log_should_output "$level"; then
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

    local color_code=""
    case "$level" in
        DEBUG) color_code="$_LOG_COLOR_DEBUG" ;;
        INFO)  color_code="$_LOG_COLOR_INFO"  ;;
        WARN)  color_code="$_LOG_COLOR_WARN"  ;;
        ERROR) color_code="$_LOG_COLOR_ERROR" ;;
    esac

    if [[ -n "$color_code" ]]; then
        echo "${color_code}${log_line}${_LOG_COLOR_RESET}" >&2
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

disable_log_color() {
    LOG_NO_COLOR=1
    _LOG_COLOR_RESET=""
    _LOG_COLOR_DEBUG=""
    _LOG_COLOR_INFO=""
    _LOG_COLOR_WARN=""
    _LOG_COLOR_ERROR=""
}
