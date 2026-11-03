#!/hint/bash

[[ -n "${__LAUNCH_MODE_SCRIPT_SH_LOADED:-}" ]] && return 0
__LAUNCH_MODE_SCRIPT_SH_LOADED=1

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

# $1 为游戏工作目录的 Windows 路径，其余参数为游戏启动 argv
launch_script_render() {
    local game_cwd_win="$1"
    shift

    cat << EOF
setlocal DisableDelayedExpansion
chcp 65001
Z:
cd /d $(quote_args_bat "$game_cwd_win")
$(launch_plan_prepare_snippet_get)
$(launch_plan_before_snippet_get)
setlocal DisableDelayedExpansion
start "" /WAIT /B $(quote_args_bat "$@")
$(launch_plan_after_snippet_get)
EOF
}

launch_script_mode() {
    local -a game_argv=()
    launch_plan_build_game_argv game_argv

    # argv[0] 为 Unix 路径，直接启动时由 runner 转换
    # .bat 中须在此转为 Windows 路径
    game_argv[0]="$(wine_unix_path_to_windows "${game_argv[0]}")"

    local game_arg
    for game_arg in "${game_argv[@]}"; do
        [[ "$game_arg" == *\"* ]] && die 1 launch "游戏启动参数不能包含双引号: '$game_arg'"
    done

    local game_cwd game_cwd_win content script
    game_cwd="$(launch_plan_get_cwd)"
    game_cwd_win="$(wine_unix_path_to_windows "$game_cwd")"

    content="$(launch_script_render "$game_cwd_win" "${game_argv[@]}")"
    script="$(mktemp "$TEMP_DIR/start-game-XXXXXXX.bat")"
    echo "$content" > "$script" || die 1 launch "无法写入游戏批处理文件: '$script'"

    launch_plan_runner_target_set cmd /c "$script"
}
