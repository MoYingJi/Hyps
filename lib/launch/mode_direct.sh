#!/hint/bash

[[ -n "${__LAUNCH_MODE_DIRECT_SH_LOADED:-}" ]] && return 0
__LAUNCH_MODE_DIRECT_SH_LOADED=1

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"
#shellcheck source=../environment.sh
source "$SCRIPT_DIR/environment.sh"

launch_direct_run_prepare() {
    local script content
    script="$(mktemp "$TEMP_DIR/prepare-XXXXXXX.bat")"
    content="$(cat << EOF
chcp 65001
$(launch_plan_prepare_snippet_get)
EOF
    )"
    echo "$content" > "$script" || die 1 launch "无法写入准备批处理文件: '$script'"

    local -a runner=() cmd=()
    launch_plan_runner_prefix_get runner
    runner+=("cmd" "/c" "$script")
    environment_command_get cmd "${runner[@]}" || return $?
    log_info launch "运行准备批处理脚本: $(quote_args "${runner[@]}")"
    "${cmd[@]}" &
    local prepare_pid="$!"
    wait "$prepare_pid"
}

launch_direct_mode() {
    if ! launch_plan_prepare_snippet_empty; then
        launch_direct_run_prepare || return $?
    fi

    local -a game_argv=()
    launch_plan_build_game_argv game_argv
    launch_plan_runner_target_set "${game_argv[@]}"
}
