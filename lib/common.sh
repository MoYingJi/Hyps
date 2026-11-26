#!/hint/bash

[[ -n "${__COMMON_SH_LOADED:-}" ]] && return 0

#shellcheck source=bootstrap.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/bootstrap.sh" || return $?
#shellcheck source=utils/game_script.sh
source "$SCRIPT_DIR/utils/game_script.sh" || return $?

if ! game_name_valid "${GAME_NAME:-}"; then
    printf '无效的游戏名: %s\n' "${GAME_NAME:-}" >&2
    return 1
fi

#shellcheck disable=SC2034
SCRIPT_START_NANOSECONDS="$(date +%s%N)"

#shellcheck source=modules.sh
source "$SCRIPT_DIR/modules.sh" || return $?
#shellcheck source=environment.sh
source "$SCRIPT_DIR/environment.sh" || return $?

hyps_load_modules || return $?
__COMMON_SH_LOADED=1

hyps_main() {
    # defer_mkdir 在 prepare 创建，游戏目录内的目录会落到 upper
    # 必须在挂载前创建的目录用 game_fs_write_path writable
    register_hook prepare flush_pending_mkdirs 20

    local game_impl="$SCRIPT_DIR/games/$GAME_NAME.sh"
    if [ -f "$game_impl" ]; then
        log_debug lifecycle "加载游戏实现: $game_impl"
        #shellcheck source=/dev/null
        source "$game_impl" || exit $?
    else
        log_debug lifecycle "未找到游戏实现 $GAME_NAME"
    fi

    environment_capture
    load_config || exit $?
    run_hooks load_config || exit $?

    # LaunchPlan 的 exe/cwd 由 GameFS 派生
    game_fs_init || exit $?
    game_fs_apply_launch_plan || exit $?
    # 挂载点已存在时在 prepare_offline 前拒绝
    game_fs_require_launchable || exit $?

    environment_resolve || exit $?
    environment_check || exit $?

    trap cleanup EXIT

    mkdir -p "$TEMP_DIR" || die 1 lifecycle "无法创建临时目录: '$TEMP_DIR'"

    game_fs_set_phase prepare_offline || exit $?
    run_hooks prepare_offline || exit $?
    game_fs_mount || exit $?
    game_fs_set_phase prepare || exit $?
    run_hooks prepare || exit $?

    launch_plan_select_mode || exit $?
    launch_plan_build_command || exit $?
    game_fs_set_phase pre_start || exit $?
    run_hooks pre_start || exit $?
    launch_plan_run || exit $?
    game_fs_set_phase post_start || exit $?
    run_hooks post_start continue
    wait "$(launch_plan_get_pid)"
}

cleanup() {
    log_info lifecycle "终止"
    launch_plan_kill
    game_fs_set_phase cleanup
    run_hooks cleanup continue
    launch_plan_wait

    # cleanup 也可能注册离线钩子，需要在其返回后判断
    local require_offline=0
    lifecycle_has_hooks cleanup_offline && require_offline=1
    if game_fs_unmount "$require_offline"; then
        if [ "$require_offline" -eq 1 ]; then
            game_fs_set_phase cleanup_offline
            run_hooks cleanup_offline continue
        fi
    elif [ "$require_offline" -eq 1 ]; then
        log_warn lifecycle "overlay 未达到离线清理条件，跳过 cleanup_offline，保留恢复标记"
    fi

    isy "$DEBUG_SKIP_REMOVE_TEMP" || rm -rf "$TEMP_DIR"
}

load_config() {
    load_global_config || return $?
    load_game_config "$GAME_NAME" || return $?
    config_require_launch || return $?
    config_validate || return $?
    game_fs_resolve_paths || return 1

    local -a game_args=()
    config_read_array game.args game_args
    launch_plan_args_set "${game_args[@]}"

    launch_plan_set_game_exe "${GAME_FS[game_exe_install]}"
    launch_plan_set_cwd "${GAME_FS[game_cwd_install]}"
}
