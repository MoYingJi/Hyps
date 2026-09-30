#!/hint/bash

[[ -n "${__COMMON_SH_LOADED:-}" ]] && return 0
__COMMON_SH_LOADED=1

[ "$UID" -ne 0 ] || { echo "你个小天才是怎么想到用 root 运行的（"; exit 1; }
[ -n "$GAME_NAME" ] || { echo "请在运行前设置环境变量 GAME_NAME"; exit 1; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT" || { echo "找不到或无法切换到项目根目录"; exit 1; }

SCRIPT_START_NANOSECONDS="$(date +%s%N)"


#shellcheck source=libs.sh
source "$SCRIPT_DIR/libs.sh"

for feature_script in "$SCRIPT_DIR"/features/*.sh; do
    #shellcheck source=/dev/null
    source "$feature_script"
done

hyps_main() {
    local game_impl="$SCRIPT_DIR/games/$GAME_NAME.sh"
    if [ -f "$game_impl" ]; then
        log_debug lifecycle "加载游戏实现: $game_impl"
        #shellcheck source=/dev/null
        source "$game_impl"
    else
        log_debug lifecycle "未找到游戏实现 $GAME_NAME"
    fi

    load_config
    run_hooks load_config || exit $?
    export_env_vars

    trap cleanup EXIT

    mkdir -p "$TEMP_DIR" || die 1 lifecycle "无法创建临时目录: '$TEMP_DIR'"
    run_hooks prepare || exit $?
    build_game_command
    run_hooks pre_start || exit $?
    start_game_process
    run_hooks post_start continue
    wait "$GAME_PID"
}

cleanup() {
    log_info lifecycle "终止"
    kill "$GAME_PID" 2>/dev/null
    run_hooks cleanup continue

    isy "$DEBUG_SKIP_REMOVE_TEMP" || rm -rf "$TEMP_DIR"
}

load_config() {
    local game_config_file
    local runner_name

    load_common_config
    load_game_config "$GAME_NAME"

    GAME_ARGS=()
    config_has game.args && config_read_array game.args GAME_ARGS
}

build_game_command() {
    local -a cmd=()

    cmd+=("${RUNNER_WRAPPER[@]}")
    cmd+=("$(config_get runner.exe)")

    local -a runner_args=()
    config_has runner.args && config_read_array runner.args runner_args
    cmd+=("${runner_args[@]}")

    if isy "$NEEDS_CUSTOM_BATCH"; then
        cmd+=("cmd" "/c" "$CUSTOM_BATCH_SCRIPT")
    else
        cmd+=("$(config_get game.exe)")
        cmd+=("${GAME_ARGS[@]}")
    fi

    GAME_COMMAND=("${cmd[@]}")
}

start_game_process() {
    local -a cmd=("${GAME_COMMAND[@]}")
    local game_cwd
    game_cwd="$(config_get game.cwd)"

    log_info lifecycle "启动游戏: $(quote_args "${cmd[@]}")"
    log_debug lifecycle "工作目录: $game_cwd"
    cd "$game_cwd" || die 1 lifecycle "无法切换到游戏工作目录: '$game_cwd'"
    LD_PRELOAD="$(env_get_ld_preload)" "${cmd[@]}" &
    GAME_PID="$!"
    log_debug lifecycle "游戏进程 PID: $GAME_PID"
    cd - || die 1 lifecycle "无法切换回项目根目录"

    local now_ns dur_ns
    now_ns="$(date +%s%N)"
    dur_ns="$((now_ns - SCRIPT_START_NANOSECONDS))"
    log_debug lifecycle "本次脚本用时: $(printf "%'d" "$dur_ns") 纳秒"
}
