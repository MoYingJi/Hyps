#!/hint/bash

[[ -n "${__COMMON_SH_LOADED:-}" ]] && return 0
__COMMON_SH_LOADED=1

[ "$UID" -ne 0 ] || { echo "你个小天才是怎么想到用 root 运行的（"; exit 1; }
[ -n "$GAME_NAME" ] || { echo "请在运行前设置环境变量 GAME_NAME"; exit 1; }

SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "$SCRIPT_DIR" == "${BASH_SOURCE[0]}" ]] && SCRIPT_DIR="."
SCRIPT_DIR="$(cd -- "$SCRIPT_DIR" &> /dev/null && pwd)"
PROJECT_ROOT="${SCRIPT_DIR%/*}"
[[ "$PROJECT_ROOT" == "$SCRIPT_DIR" ]] && PROJECT_ROOT="/"

cd "$PROJECT_ROOT" || { echo "找不到或无法切换到项目根目录"; exit 1; }

#shellcheck disable=SC2034
SCRIPT_START_NANOSECONDS="$(date +%s%N)"


#shellcheck source=libs.sh
source "$SCRIPT_DIR/libs.sh"

#shellcheck source=config/environment.sh
source "$SCRIPT_DIR/config/environment.sh"

for shared_script in "$SCRIPT_DIR"/shared/*.sh; do
    #shellcheck source=/dev/null
    source "$shared_script"
done

for feature_script in "$SCRIPT_DIR"/features/*.sh; do
    #shellcheck source=/dev/null
    source "$feature_script"
done

hyps_main() {
    register_hook prepare flush_pending_mkdirs 0

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

    launch_plan_select_mode
    launch_plan_build_command
    run_hooks pre_start || exit $?
    launch_plan_run
    run_hooks post_start continue
    wait "$(launch_plan_get_pid)"
}

cleanup() {
    log_info lifecycle "终止"
    launch_plan_kill
    run_hooks cleanup continue

    isy "$DEBUG_SKIP_REMOVE_TEMP" || rm -rf "$TEMP_DIR"
}

load_config() {
    load_common_config
    load_game_config "$GAME_NAME"

    local -a game_args=()
    config_has game.args && config_read_array game.args game_args
    launch_plan_args_set "${game_args[@]}"

    local game_exe game_cwd
    config_read game.exe game_exe
    launch_plan_set_game_exe "$game_exe"
    config_read game.cwd game_cwd
    launch_plan_set_cwd "$game_cwd"
}
