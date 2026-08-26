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
    run_hooks prepare
    build_game_command
    run_hooks pre_start
    start_game_process
    run_hooks post_start
    wait "$GAME_PID"
}

cleanup() {
    log_info lifecycle "终止"
    kill "$GAME_PID" 2>/dev/null
    run_hooks cleanup

    isy "$DEBUG_SKIP_REMOVE_TEMP" || rm -rf "$TEMP_DIR"
}

load_config() {
    local game_config_file
    local runner_name

    load_common_config

    game_config_file="$CONFIG_DIR/games/${GAME_NAME}.conf"
    [ -f "$game_config_file" ] || die 1 config "游戏配置文件不存在：$game_config_file"

    if config_has runner.name; then
        # 如果已经有 runner，直接读
        runner_name="$(config_get runner.name)"
        config_parse_file "$CONFIG_DIR/runners/${runner_name}.conf"
        config_parse_file "$game_config_file"
    else
        # 为了保证优先级 runner < games
        # 先从 games 读 runner，再读 runner 配置，然后将 games 配置合并上去
        config_parse_to_temp "$game_config_file"
        runner_name="${TEMP_CONFIG[runner.name]}"
        config_parse_file "$CONFIG_DIR/runners/${runner_name}.conf"
        config_merge_temp
    fi

    if ! config_has runner.exe && config_has runner.protonpath; then
        local proton_path
        proton_path="$(env_transform_protonpath "$(config_get runner.protonpath)")"
        config_set runner.protonpath "$proton_path"
        config_set runner.exe "$proton_path/proton"
    fi

    config_require_realpath_which_exe runner.exe
    config_require_realpath_file game.exe

    config_realpath game.prefix "$DATA_DIR/prefixes/${GAME_NAME}" >/dev/null

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
        cmd+=("$CUSTOM_BATCH_SCRIPT")
    else
        cmd+=("$(config_get game.exe)")
        cmd+=("${GAME_ARGS[@]}")
    fi

    GAME_COMMAND=("${cmd[@]}")
}

start_game_process() {
    local -a cmd=("${GAME_COMMAND[@]}")

    log_info lifecycle "启动游戏: $(quote_args "${cmd[@]}")"
    LD_PRELOAD="$(env_get_ld_preload)" "${cmd[@]}" &
    GAME_PID="$!"
    log_debug lifecycle "游戏进程 PID: $GAME_PID"

    local now_ns dur_ns
    now_ns="$(date +%s%N)"
    dur_ns="$((now_ns - SCRIPT_START_NANOSECONDS))"
    log_debug lifecycle "本次脚本用时: $(printf "%'d" "$dur_ns") 纳秒"
}
