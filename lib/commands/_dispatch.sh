#!/usr/bin/bash

# 命令约定:
#   lib/commands/<group>.sh 定义 command_<group>_<sub>（可嵌套: command_<group>_<sub>_<subsub>），
#   无子命令的命令直接定义 command_<group>。
#   可选 help_<group>_<sub> 输出该命令的帮助文本。子命令名中的 - 对应函数名中的 _。

COMMANDS_DIR="$SCRIPT_DIR/commands"

command_help() {
    local fn="$1" help_fn subs sub

    help_fn="help${fn#command}"
    declare -F "$help_fn" &>/dev/null && "$help_fn"

    if [ "$fn" = "command" ]; then
        subs="$(compgen -G "$COMMANDS_DIR/[!_]*.sh" | xargs -r -n1 basename -s .sh)"
    else
        subs="$(compgen -A function "${fn}_" | sed "s/^${fn}_//")"
    fi

    [ -n "$subs" ] || return 0
    echo "可用子命令:"
    while IFS= read -r sub; do
        echo "  ${sub//_/-}"
    done <<< "$subs"
}

dispatch() {
    local group="${1:-}"

    if [[ "$group" == "" || "$group" == -h || "$group" == --help ]]; then
        command_help command
        [ -n "$group" ]
        return
    fi

    local file="$COMMANDS_DIR/${group//-/_}.sh"
    if [ ! -f "$file" ]; then
        echo "未知的命令: $group" >&2
        command_help command
        return 1
    fi
    #shellcheck source=/dev/null
    source "$file"
    shift

    local fn="command_${group//-/_}" next
    while [ "$#" -gt 0 ] && [[ "$1" != -* ]]; do
        next="${fn}_${1//-/_}"
        declare -F "$next" &>/dev/null || break
        fn="$next"
        shift
    done

    if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
        command_help "$fn"
        return 0
    fi

    if ! declare -F "$fn" &>/dev/null; then
        [ "$#" -eq 0 ] || echo "未知的子命令: $1" >&2
        command_help "$fn" >&2
        return 1
    fi

    "$fn" "$@"
}
