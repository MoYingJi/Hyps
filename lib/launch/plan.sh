#!/hint/bash

[[ -n "${__LAUNCH_PLAN_SH_LOADED:-}" ]] && return 0
__LAUNCH_PLAN_SH_LOADED=1

# LaunchPlan：本次启动全部「启动相关」状态的单一所有者

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

# --- 容器字段 ---

declare -a LP_ARGS=()              # game.args，追加在游戏 exe 之后的参数
declare -a LP_RUNNER_WRAPPER=()    # 系统级包装器链 (mangohud/gamescope/systemd-run...)
declare -a LP_RUNNER_TARGET=()     # runner 的目标命令 (handler 产物或批处理命令)
declare -a LP_LD_PRELOAD=()        # 需要注入的 LD_PRELOAD 库列表
declare -a LP_COMMAND=()           # 最终组装好的启动命令

declare LP_GAME_HANDLER="launch_plan_default_game_handler"  # 游戏 handler 函数名，契约见 game_handler.sh

declare    LP_PID=""              # 启动的游戏进程 PID
declare    LP_GAME_CWD=""         # 游戏工作目录

declare    LP_PREPARE_SNIPPET=""     # 准备片段: 脚本模式下写入整份 .bat，直接模式下单独运行一次
declare    LP_BEFORE_SNIPPET=""      # 游戏启动前的 .bat 片段: 存在即采用脚本模式
declare    LP_AFTER_SNIPPET=""       # 游戏退出后的 .bat 片段: 存在即采用脚本模式

# --- 游戏参数 (game.args) ---

launch_plan_args_set() {
    LP_ARGS=("$@")
}
#shellcheck disable=SC2178
launch_plan_args_get() {
    local -n _out="$1"
    _out=("${LP_ARGS[@]}")
}

# --- runner wrapper (系统级包装器链) ---

launch_plan_runner_wrapper_prepend() {
    LP_RUNNER_WRAPPER=("$@" "${LP_RUNNER_WRAPPER[@]}")
}
#shellcheck disable=SC2178
launch_plan_runner_wrapper_get() {
    local -n _out="$1"
    _out=("${LP_RUNNER_WRAPPER[@]}")
}

# --- 游戏目标 handler (独占) ---

launch_plan_register_game_handler() {
    local name="$1"
    local fn="$2"
    if [[ "$LP_GAME_HANDLER" != "launch_plan_default_game_handler" ]]; then
        die 1 launch "游戏目标 handler 冲突：'$LP_GAME_HANDLER' 与 '$fn' 都要接管游戏启动命令"
    fi
    LP_GAME_HANDLER="$fn"
    log_debug launch "注册游戏目标 handler: $name"
}
launch_plan_game_handler_get() {
    printf '%s' "$LP_GAME_HANDLER"
}

# --- runner 目标 (游戏目标 handler 产物 或 批处理命令) ---

launch_plan_runner_target_set() {
    LP_RUNNER_TARGET=("$@")
}
#shellcheck disable=SC2178
launch_plan_runner_target_get() {
    local -n _out="$1"
    _out=("${LP_RUNNER_TARGET[@]}")
}

# --- LD_PRELOAD 库列表 ---

launch_plan_ld_preload_append() {
    LP_LD_PRELOAD+=("$@")
}
launch_plan_ld_preload_join() {
    local IFS=':'
    echo "${LP_LD_PRELOAD[*]}"
}

# --- .bat 片段 (append 时以换行衔接) ---

launch_plan_prepare_snippet_append() {
    local block="$1"
    LP_PREPARE_SNIPPET="${LP_PREPARE_SNIPPET}${LP_PREPARE_SNIPPET:+$'\n'}$block"
}
launch_plan_prepare_snippet_get() {
    printf '%s' "$LP_PREPARE_SNIPPET"
}
launch_plan_prepare_snippet_empty() {
    [[ -z "$LP_PREPARE_SNIPPET" ]]
}

launch_plan_before_snippet_append() {
    local block="$1"
    LP_BEFORE_SNIPPET="${LP_BEFORE_SNIPPET}${LP_BEFORE_SNIPPET:+$'\n'}$block"
}
launch_plan_before_snippet_get() {
    printf '%s' "$LP_BEFORE_SNIPPET"
}
launch_plan_before_snippet_empty() {
    [[ -z "$LP_BEFORE_SNIPPET" ]]
}

launch_plan_after_snippet_get() {
    printf '%s' "$LP_AFTER_SNIPPET"
}
launch_plan_after_snippet_empty() {
    [[ -z "$LP_AFTER_SNIPPET" ]]
}

# --- 进程与命令 ---

launch_plan_get_pid() {
    printf '%s' "$LP_PID"
}
launch_plan_set_cwd() {
    LP_GAME_CWD="$1"
}
launch_plan_get_cwd() {
    printf '%s' "$LP_GAME_CWD"
}

# runner 前缀: runner wrapper + runner.exe + runner.args
#shellcheck disable=SC2178
launch_plan_runner_prefix_get() {
    local -n _out="$1"
    local runner_exe
    local -a runner_args=()

    config_read runner.exe runner_exe
    config_has runner.args && config_read_array runner.args runner_args

    _out=("${LP_RUNNER_WRAPPER[@]}" "$runner_exe" "${runner_args[@]}")
}

# 启动模式选择
# before / after 片段必须与游戏同次启动，只能写入 .bat，因此存在即采用脚本模式
# prepare 片段 和 handler 不参与选择
launch_plan_use_script_mode() {
    ! launch_plan_before_snippet_empty || ! launch_plan_after_snippet_empty
}

launch_plan_select_mode() {
    if launch_plan_use_script_mode; then
        if isy "$UMU_USE_STEAM"; then
            log_error launch "使用自定义批处理脚本时，UMU_USE_STEAM=1 时将不起作用。请检查配置中哪里出现了问题！"
        fi
        launch_script_mode
    else
        launch_direct_mode
    fi
}

launch_plan_build_command() {
    local -a runner_prefix=()
    local -a runner_target=()
    launch_plan_runner_prefix_get runner_prefix
    launch_plan_runner_target_get runner_target

    LP_COMMAND=("${runner_prefix[@]}" "${runner_target[@]}")
}

# 在 LP_GAME_CWD 下启动游戏进程并记录 PID
launch_plan_run() {
    local -a cmd=("${LP_COMMAND[@]}")
    local ld_preload
    ld_preload="$(launch_plan_ld_preload_join)"

    log_info lifecycle "启动游戏: $(quote_args "${cmd[@]}")"
    log_debug lifecycle "工作目录: $LP_GAME_CWD"
    pushd "$LP_GAME_CWD" > /dev/null || die 1 lifecycle "无法切换到游戏工作目录: '$LP_GAME_CWD'"
    LD_PRELOAD="$ld_preload" "${cmd[@]}" &
    LP_PID="$!"
    log_debug lifecycle "游戏进程 PID: $LP_PID"
    popd > /dev/null || die 1 lifecycle "无法切换回项目根目录"

    local now_ns dur_ns
    now_ns="$(date +%s%N)"
    dur_ns="$((now_ns - SCRIPT_START_NANOSECONDS))"
    log_debug lifecycle "本次脚本用时: $(printf "%'d" "$dur_ns") 纳秒"
}

launch_plan_kill() {
    [[ -n "$LP_PID" ]] && kill "$LP_PID" 2>/dev/null
}
