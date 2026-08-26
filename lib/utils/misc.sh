#!/hint/bash

[[ -n "${__UTILS_MISC_SH_LOADED:-}" ]] && return 0
__UTILS_MISC_SH_LOADED=1

#shellcheck source=string.sh
source "${SCRIPT_DIR:-.}/utils/string.sh"

sudo_request() {
    local why="$1"
    shift

    echo "[Hyps] [sudo 请求] $why"
    echo -n "[Hyps] $ "
    quote_args "$@"
    sudo "$@"
}

run_and_log() {
    local level="$1"
    local module="$2"
    local prompt="$3"
    shift 3

    [ -z "$prompt" ] && prompt="执行命令"
    log "$level" "$module" "$prompt: $(quote_args "$@")"
    "$@"
}
