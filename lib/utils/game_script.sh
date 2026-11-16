#!/hint/bash

[[ -n "${__UTILS_GAME_SCRIPT_SH_LOADED:-}" ]] && return 0
__UTILS_GAME_SCRIPT_SH_LOADED=1

game_script_name() {
    local -n gsn_out="$2"
    local gsn_line
    gsn_out=""
    while IFS= read -r gsn_line || [[ -n $gsn_line ]]; do
        if [[ $gsn_line == 'GAME_NAME="'*'"' ]]; then
            gsn_out="${gsn_line#GAME_NAME=\"}"
            gsn_out="${gsn_out%\"}"
            return 0
        fi
    done < "$1"
    return 1
}

# 当前游戏实现的显示名；未实现或为空时回退到 GAME_NAME
game_meta_display_name() {
    local name=""

    if [ "$(type -t game_display_name)" = "function" ]; then
        name="$(game_display_name)" || name=""
    fi
    if [ -z "$name" ]; then
        [ -n "${GAME_NAME:-}" ] || {
            log_error game-meta "GAME_NAME 为空，无法确定游戏显示名"
            return 1
        }
        log_debug game-meta "game_display_name 未实现或为空，回退到 GAME_NAME: '$GAME_NAME'"
        name="$GAME_NAME"
    fi

    printf '%s\n' "$name"
}

# 当前游戏实现的路径友好名；未实现或为空时回退到 GAME_NAME
game_meta_path_name() {
    local name=""

    if [ "$(type -t game_path_name)" = "function" ]; then
        name="$(game_path_name)" || name=""
    fi
    if [ -z "$name" ]; then
        [ -n "${GAME_NAME:-}" ] || {
            log_error game-meta "GAME_NAME 为空，无法确定游戏路径名"
            return 1
        }
        log_debug game-meta "game_path_name 未实现或为空，回退到 GAME_NAME: '$GAME_NAME'"
        name="$GAME_NAME"
    fi

    case "$name" in
        . | ..)
            log_error game-meta "非法游戏路径名: '$name'"
            return 1
            ;;
    esac
    if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
        log_error game-meta "游戏路径名只能包含字母、数字、点、下划线和连字符: '$name'"
        return 1
    fi

    printf '%s\n' "$name"
}
