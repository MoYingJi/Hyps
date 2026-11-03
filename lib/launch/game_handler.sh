#!/hint/bash

[[ -n "${__LAUNCH_GAME_HANDLER_SH_LOADED:-}" ]] && return 0
__LAUNCH_GAME_HANDLER_SH_LOADED=1

# 游戏 handler 契约 (最多注册一个):
#   handler <out_nameref>
#     把 Windows 侧游戏启动 argv（含游戏 exe 与 game.args）写入 $1 指向的数组
#     argv[0] 保持 Unix 路径：直接启动时由 runner 转换，脚本模式下由 mode_script.sh 转换
#     其余路径参数由 handler 自行转换为 Windows 路径
#     私有配置由所属模块在 load_config 中写入全局变量，handler 直接读取
#     只构建 argv，不产生副作用

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

launch_plan_default_game_handler() {
    #shellcheck disable=SC2178
    local -n _out="$1"
    local game_exe
    local -a game_args=()

    config_read game.exe game_exe
    launch_plan_args_get game_args

    _out=("$game_exe" "${game_args[@]}")
}

# 经临时数组 _argv 接收 handler 输出，不能把 _out 的名字直接传给 handler (会形成 nameref 自引用)
launch_plan_build_game_argv() {
    #shellcheck disable=SC2178
    local -n _out="$1"
    local handler
    handler="$(launch_plan_game_handler_get)"

    local -a _argv=()
    "$handler" _argv
    _out=("${_argv[@]}")
}
