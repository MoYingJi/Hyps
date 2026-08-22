#!/hint/bash

[[ -n "${__CONSOLE_SH_LOADED:-}" ]] && return 0
__CONSOLE_SH_LOADED=1

declare -A _CONSOLE_STYLES=(
    [reset]=$'\033[0m'
    [black]=$'\033[30m'
    [red]=$'\033[31m'
    [green]=$'\033[32m'
    [yellow]=$'\033[33m'
    [blue]=$'\033[34m'
    [magenta]=$'\033[35m'
    [cyan]=$'\033[36m'
    [white]=$'\033[37m'
    [bright_black]=$'\033[90m'
    [bright_red]=$'\033[91m'
    [bright_green]=$'\033[92m'
    [bright_yellow]=$'\033[93m'
    [bright_blue]=$'\033[94m'
    [bright_magenta]=$'\033[95m'
    [bright_cyan]=$'\033[96m'
    [bright_white]=$'\033[97m'
)

style() {
    local name="$1"
    if [[ -n "${_CONSOLE_STYLES[$name]:-}" ]]; then
        printf "%s" "${_CONSOLE_STYLES[$name]}"
    else
        printf "\033[%sm" "$name"
    fi
}

style_quote() {
    local style_name="$1"
    local text="$2"
    printf "%s%s%s" "$(style "$style_name")" "$text" "$(style reset)"
}
