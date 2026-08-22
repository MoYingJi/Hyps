#!/hint/bash

[[ -n "${__CONSOLE_SH_LOADED:-}" ]] && return 0
__CONSOLE_SH_LOADED=1

declare -A _CONSOLE_STYLES=(
    [reset]=$'\033[0m'

    [bold]=$'\033[1m'      # 粗体
    [dim]=$'\033[2m'       # 暗色
    [italic]=$'\033[3m'    # 斜体
    [underline]=$'\033[4m' # 下划线
    [blink]=$'\033[5m'     # 闪烁
    [reverse]=$'\033[7m'   # 反色 (前景色与背景色交换)
    [hidden]=$'\033[8m'    # 隐藏
    [strike]=$'\033[9m'    # 删除线

    [black]=$'\033[30m'
    [red]=$'\033[31m'
    [green]=$'\033[32m'
    [yellow]=$'\033[33m'
    [blue]=$'\033[34m'
    [magenta]=$'\033[35m'
    [cyan]=$'\033[36m'
    [white]=$'\033[37m'

    [black_bg]=$'\033[40m'
    [red_bg]=$'\033[41m'
    [green_bg]=$'\033[42m'
    [yellow_bg]=$'\033[43m'
    [blue_bg]=$'\033[44m'
    [magenta_bg]=$'\033[45m'
    [cyan_bg]=$'\033[46m'
    [white_bg]=$'\033[47m'

    [bright_black]=$'\033[90m'
    [bright_red]=$'\033[91m'
    [bright_green]=$'\033[92m'
    [bright_yellow]=$'\033[93m'
    [bright_blue]=$'\033[94m'
    [bright_magenta]=$'\033[95m'
    [bright_cyan]=$'\033[96m'
    [bright_white]=$'\033[97m'

    [bright_black_bg]=$'\033[100m'
    [bright_red_bg]=$'\033[101m'
    [bright_green_bg]=$'\033[102m'
    [bright_yellow_bg]=$'\033[103m'
    [bright_blue_bg]=$'\033[104m'
    [bright_magenta_bg]=$'\033[105m'
    [bright_cyan_bg]=$'\033[106m'
    [bright_white_bg]=$'\033[107m'
)

style() {
    local name="$1"
    if [[ -n "${_CONSOLE_STYLES[$name]:-}" ]]; then
        printf "%s" "${_CONSOLE_STYLES[$name]}"
    elif [[ "$name" == $'\033['* ]]; then
        printf "%s" "$name"
    else
        printf "\033[%sm" "$name"
    fi
}
style_reset() {
    printf $'\033[0m'
}
style_256_fg() {
    local color="$1"
    printf "\033[38;5;%sm" "$color"
}
style_256_bg() {
    local color="$1"
    printf "\033[48;5;%sm" "$color"
}
style_rgb_fg() {
    local r="$1" g="$2" b="$3"
    printf "\033[38;2;%s;%s;%sm" "$r" "$g" "$b"
}
style_rgb_bg() {
    local r="$1" g="$2" b="$3"
    printf "\033[48;2;%s;%s;%sm" "$r" "$g" "$b"
}

style_quote() {
    local styles=()
    IFS=',' read -ra styles <<< "$1"
    local text="$2"

    local style_sequence=""
    for style_name in "${styles[@]}"; do
        style_sequence+=$(style "$style_name")
    done

    printf "%s%s%s" "$style_sequence" "$text" "$(style reset)"
}
