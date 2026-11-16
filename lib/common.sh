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
    # defer_mkdir 在 prepare 创建，游戏目录内的目录会落到 upper
    # 必须在挂载前创建的目录用 game_fs_write_path writable
    register_hook prepare flush_pending_mkdirs 20

    local game_impl="$SCRIPT_DIR/games/$GAME_NAME.sh"
    if [ -f "$game_impl" ]; then
        log_debug lifecycle "加载游戏实现: $game_impl"
        #shellcheck source=/dev/null
        source "$game_impl"
    else
        log_debug lifecycle "未找到游戏实现 $GAME_NAME"
    fi

    load_config || exit $?
    run_hooks load_config || exit $?

    # LaunchPlan 的 exe/cwd 由 GameFS 派生
    game_fs_init || exit $?
    game_fs_apply_launch_plan || exit $?
    # 挂载点已存在时在 prepare_offline 前拒绝
    game_fs_require_launchable || exit $?

    export_env_vars

    trap cleanup EXIT

    mkdir -p "$TEMP_DIR" || die 1 lifecycle "无法创建临时目录: '$TEMP_DIR'"

    game_fs_set_phase prepare_offline || exit $?
    run_hooks prepare_offline || exit $?
    game_fs_mount || exit $?
    game_fs_set_phase prepare || exit $?
    run_hooks prepare || exit $?

    launch_plan_select_mode
    launch_plan_build_command
    game_fs_set_phase pre_start || exit $?
    run_hooks pre_start || exit $?
    launch_plan_run
    game_fs_set_phase post_start || exit $?
    run_hooks post_start continue
    wait "$(launch_plan_get_pid)"
}

cleanup() {
    log_info lifecycle "终止"
    launch_plan_kill
    game_fs_set_phase cleanup
    run_hooks cleanup continue

    if game_fs_unmount; then
        game_fs_set_phase cleanup_offline
        run_hooks cleanup_offline continue
    else
        log_warn lifecycle "overlay 未正常卸载或已懒卸载，跳过 cleanup_offline，保留恢复标记"
    fi

    isy "$DEBUG_SKIP_REMOVE_TEMP" || rm -rf "$TEMP_DIR"
}

load_config() {
    load_common_config
    load_game_config "$GAME_NAME"
    game_fs_resolve_paths || return 1

    local -a game_args=()
    config_has game.args && config_read_array game.args game_args
    launch_plan_args_set "${game_args[@]}"

    launch_plan_set_game_exe "${GAME_FS[game_exe_install]}"
    launch_plan_set_cwd "${GAME_FS[game_cwd_install]}"
}
