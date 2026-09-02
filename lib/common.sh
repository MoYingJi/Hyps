#!/hint/bash

[ "$UID" -ne 0 ] || { echo "你个小天才是怎么想到用 root 运行的（"; exit 1; }
[ -n "$GAME_NAME" ] || { echo "请在运行前设置环境变量 GAME_NAME"; exit 1; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT" || { echo "找不到或无法切换到项目根目录"; exit 1; }

SCRIPT_START_NANOSECONDS="$(date +%s%N)"


#shellcheck source=libs.sh
source "$SCRIPT_DIR/libs.sh"

#shellcheck source=./features/custom_batch.sh
source "$SCRIPT_DIR/features/custom_batch.sh"
#shellcheck source=./features/dxvk_nvapi_env.sh
source "$SCRIPT_DIR/features/dxvk_nvapi_env.sh"
#shellcheck source=./features/hosts_disconnect.sh
source "$SCRIPT_DIR/features/hosts_disconnect.sh"
#shellcheck source=./features/intel_rapl_read.sh
source "$SCRIPT_DIR/features/intel_rapl_read.sh"
#shellcheck source=./features/jade_patch.sh
source "$SCRIPT_DIR/features/jade_patch.sh"
#shellcheck source=./features/kill_wineserver.sh
source "$SCRIPT_DIR/features/kill_wineserver.sh"
#shellcheck source=./features/mod_reg_hostname.sh
source "$SCRIPT_DIR/features/mod_reg_hostname.sh"
#shellcheck source=./features/overlay.sh
source "$SCRIPT_DIR/features/overlay.sh"
#shellcheck source=./features/pfx_link.sh
source "$SCRIPT_DIR/features/pfx_link.sh"
#shellcheck source=./features/program_cache.sh
source "$SCRIPT_DIR/features/program_cache.sh"
#shellcheck source=./features/time_record.sh
source "$SCRIPT_DIR/features/time_record.sh"
#shellcheck source=./features/userdata_link.sh
source "$SCRIPT_DIR/features/userdata_link.sh"
#shellcheck source=./features/window_time_indicator.sh
source "$SCRIPT_DIR/features/window_time_indicator.sh"
#shellcheck source=./features/wrappers.sh
source "$SCRIPT_DIR/features/wrappers.sh"
#shellcheck source=./features/xwin_watch_kill.sh
source "$SCRIPT_DIR/features/xwin_watch_kill.sh"
#shellcheck source=./features/xwin_watch.sh
source "$SCRIPT_DIR/features/xwin_watch.sh"


hyps_main() {
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
