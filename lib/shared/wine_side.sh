#!/hint/bash

[[ -n "${__SHARED_WINE_SIDE_SH_LOADED:-}" ]] && return 0
__SHARED_WINE_SIDE_SH_LOADED=1

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

wine_side_windows_path() {
    printf 'Z:%s' "${1//\//\\}"
}

wine_side_quote_cmd_args() {
    local arg
    for arg in "$@"; do
        printf '"%s" ' "$arg"
    done
    echo
}

wine_side_append_runner_command() {
    #shellcheck disable=SC2178
    local -n command_ref="$1"
    local runner_exe
    local -a runner_args=()

    command_ref+=("${RUNNER_WRAPPER[@]}")
    config_read runner.exe runner_exe
    command_ref+=("$runner_exe")
    config_has runner.args && config_read_array runner.args runner_args
    command_ref+=("${runner_args[@]}")
}

wine_side_generate_game_batch() {
    local script
    local content
    local game_cwd
    local game_cwd_win
    local game_exe
    local -a outer_wrapper=("${WINE_SIDE_OUTER_WRAPPER[@]}")
    local -a game_wrapper=("${WINE_SIDE_GAME_WRAPPER[@]}")

    script="$(mktemp "$TEMP_DIR/start-game-XXXXXXX.bat")"
    config_read game.cwd game_cwd
    config_read game.exe game_exe
    game_cwd_win="$(wine_side_windows_path "$game_cwd")"
    game_exe="$(wine_side_windows_path "$game_exe")"
    if [[ "${outer_wrapper[0]:-}" == /* ]]; then
        outer_wrapper[0]="$(wine_side_windows_path "${outer_wrapper[0]}")"
    fi
    if [[ "${game_wrapper[0]:-}" == /* ]]; then
        game_wrapper[0]="$(wine_side_windows_path "${game_wrapper[0]}")"
    fi

    content="$(cat << EOF
chcp 65001
Z:
cd /d "$game_cwd_win"
$WINE_SIDE_PREPARE_BATCH
$WINE_SIDE_BEFORE_GAME_BATCH
start "" /WAIT /B $(wine_side_quote_cmd_args "${outer_wrapper[@]}" "${game_wrapper[@]}") "$game_exe" $(quote_args "${GAME_ARGS[@]}")
$WINE_SIDE_AFTER_GAME_BATCH
EOF
    )"
    echo "$content" > "$script" || die 1 wine-side "无法写入游戏批处理文件: '$script'"
    echo "$script"
}

wine_side_run_prepare_batch() {
    [ -z "$WINE_SIDE_PREPARE_BATCH" ] && [ -z "$WINE_SIDE_BEFORE_GAME_BATCH" ] && return 0

    local script
    local content
    script="$(mktemp "$TEMP_DIR/prepare-XXXXXXX.bat")"
    content="$(cat << EOF
chcp 65001
$WINE_SIDE_PREPARE_BATCH
$WINE_SIDE_BEFORE_GAME_BATCH
EOF
    )"
    echo "$content" > "$script" || die 1 wine-side "无法写入准备批处理文件: '$script'"

    local -a cmd=()
    wine_side_append_runner_command cmd
    cmd+=("cmd" "/c" "$script")
    log_info wine-side "运行准备批处理脚本: $(quote_args "${cmd[@]}")"
    "${cmd[@]}" &
    local prepare_pid="$!"
    wait "$prepare_pid"
}

wine_side_set_runner_target() {
    local game_exe
    # Outer wrappers are the first Windows process; game wrappers sit immediately around the game.
    local -a outer_wrapper=("${WINE_SIDE_OUTER_WRAPPER[@]}")
    local -a game_wrapper=("${WINE_SIDE_GAME_WRAPPER[@]}")

    COMMAND_RUNNER_TARGET=()
    config_read game.exe game_exe

    if isy "$WINE_SIDE_NEEDS_BATCH" \
        && { ((${#outer_wrapper[@]} + ${#game_wrapper[@]} == 0)) || [[ -n "$WINE_SIDE_AFTER_GAME_BATCH" ]]; }; then
        COMMAND_RUNNER_TARGET=("cmd" "/c" "$WINE_SIDE_GAME_BATCH_SCRIPT")
    elif ((${#outer_wrapper[@]})); then
        COMMAND_RUNNER_TARGET=("${outer_wrapper[@]}")
        if ((${#game_wrapper[@]})); then
            if [[ "${game_wrapper[0]}" == /* ]]; then
                game_wrapper[0]="$(wine_side_windows_path "${game_wrapper[0]}")"
            fi
            COMMAND_RUNNER_TARGET+=("${game_wrapper[@]}")
            COMMAND_RUNNER_TARGET+=("$(wine_side_windows_path "$game_exe")" "${GAME_ARGS[@]}")
        else
            COMMAND_RUNNER_TARGET+=("$(wine_side_windows_path "$game_exe")" "${GAME_ARGS[@]}")
        fi
    elif ((${#game_wrapper[@]})); then
        COMMAND_RUNNER_TARGET=("${game_wrapper[@]}" "$(wine_side_windows_path "$game_exe")" "${GAME_ARGS[@]}")
    else
        COMMAND_RUNNER_TARGET=("$game_exe" "${GAME_ARGS[@]}")
    fi
}

wine_side_prepare() {
    [[ -n "$WINE_SIDE_AFTER_GAME_BATCH" ]] && WINE_SIDE_NEEDS_BATCH=1

    if isy "$WINE_SIDE_NEEDS_BATCH" && isy "$UMU_USE_STEAM"; then
        log_error wine-side "使用自定义批处理脚本时，UMU_USE_STEAM=1 时将不起作用。请检查配置中哪里出现了问题！"
    fi

    if isy "$WINE_SIDE_NEEDS_BATCH" \
        && { ((${#WINE_SIDE_OUTER_WRAPPER[@]} + ${#WINE_SIDE_GAME_WRAPPER[@]} == 0)) || [[ -n "$WINE_SIDE_AFTER_GAME_BATCH" ]]; }; then
        local wrapper_arg
        for wrapper_arg in "${WINE_SIDE_OUTER_WRAPPER[@]}" "${WINE_SIDE_GAME_WRAPPER[@]}"; do
            [[ "$wrapper_arg" == *\"* ]] && die 1 wine-side "包装程序参数不能包含双引号: '$wrapper_arg'"
        done
        WINE_SIDE_GAME_BATCH_SCRIPT="$(wine_side_generate_game_batch)"
    else
        wine_side_run_prepare_batch
    fi

    wine_side_set_runner_target
}

register_hook prepare wine_side_prepare 100
