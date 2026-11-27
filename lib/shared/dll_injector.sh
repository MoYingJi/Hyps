#!/hint/bash

[[ -n "${__SHARED_DLL_INJECTOR_SH_LOADED:-}" ]] && return 0
__SHARED_DLL_INJECTOR_SH_LOADED=1

#shellcheck source=../config/access.sh
source "$SCRIPT_DIR/config/access.sh"
#shellcheck source=../core/lifecycle.sh
source "$SCRIPT_DIR/core/lifecycle.sh"
#shellcheck source=../core/log.sh
source "$SCRIPT_DIR/core/log.sh"
#shellcheck source=../utils/string.sh
source "$SCRIPT_DIR/utils/string.sh"
#shellcheck source=../utils/command.sh
source "$SCRIPT_DIR/utils/command.sh"
#shellcheck source=../utils/cache.sh
source "$SCRIPT_DIR/utils/cache.sh"
#shellcheck source=../utils/exe_alias.sh
source "$SCRIPT_DIR/utils/exe_alias.sh"
#shellcheck source=../utils/toolspec_build.sh
source "$SCRIPT_DIR/utils/toolspec_build.sh"
#shellcheck source=../utils/wine.sh
source "$SCRIPT_DIR/utils/wine.sh"
#shellcheck source=../launch/plan.sh
source "$SCRIPT_DIR/launch/plan.sh"

# dll-injector: 通用 Windows DLL 注入器，见 tools/dll-injector/
# 注入发生在游戏主线程恢复之前，所以必须由它接管游戏启动，注册成 Game Handler
# 与其它 Game Handler (如终末地父进程替身) 互斥
#
# 分三段，和 xwin-watch 类似:
#   load_config  只看是否启用，注册 prepare 收尾钩子；此时不冻结 DLL 列表
#   prepare(90)  收集配置和 dll_injector_add 登记的 DLL，校验后注册 Game Handler 并编译注入器
#   handler      启动时把最终 DLL 列表拼成注入器的命令行
#
# 接入方式有两种，结果合并，只注册一次 Game Handler:
#   1. 配置 features.dll_inject.enabled = true 与 features.dll_inject.dlls
#   2. 其它 feature 在自身 load_config 里 config_set features.dll_inject.enabled true
#      并在 prepare(早于 90) 阶段编译好自己的 DLL 后调用 dll_injector_add <DLL>
# 注入顺序: 先配置列表，再按 dll_injector_add 的调用顺序追加

DLL_INJECTOR_TOOL="$PROJECT_ROOT/tools/dll-injector"
declare -ga DLL_INJECTOR_DLLS=()         # prepare 收尾合并后的最终列表，handler 读取
declare -ga DLL_INJECTOR_ADDED_DLLS=()   # dll_injector_add 登记的 DLL
declare -g DLL_INJECTOR_NO_WAIT=0
declare -g DLL_INJECTOR_SKIPPED=0        # load_config 时未启用
declare -g DLL_INJECTOR_FINALIZED=0      # prepare 收尾已完成
declare -g DLL_INJECTOR_LAUNCH_EXE=""    # handler 实际使用的注入器路径

config_declare features.dll_inject.enabled bool --default false --description "启用 DLL 注入"
config_declare features.dll_inject.dlls array --default '[]' --when features.dll_inject.enabled \
    --description "要注入的 DLL 路径，按顺序注入"
config_declare features.dll_inject.no_wait bool --default false --when features.dll_inject.enabled \
    --description "注入后不等待游戏，仅 umu-run 等跟随 prefix 生命周期的 runner 下安全"
config_declare features.dll_inject.exe_name string --default "" --when features.dll_inject.enabled \
    --validate exe_alias_name_is_valid \
    --description "注入器进程名，留空用 dll-injector.exe；自定义名须带 .exe，会放到统一的 bin/${EXE_ALIAS_DIRNAME}/ 别名目录并以它启动"

# 展开开头的 ~ 并转绝对路径，不要求存在
dll_injector_resolve_path() {
    local dll="$1"
    # shellcheck disable=SC2088 # 匹配字面量 ~，下面是手动展开
    case "$dll" in
        '~') dll="$HOME" ;;
        '~/'*) dll="$HOME/${dll#'~/'}" ;;
    esac
    realpath -m -- "$dll"
}

# dll_injector_add <DLL>
# 供其它 feature 登记一个要注入的 DLL
# 未启用时与 prepare 收尾之后调用都会报错；DLL 可以此时还不存在，prepare 收尾时才校验
dll_injector_add() {
    [[ $# -eq 1 ]] || die 1 dll-injector "dll_injector_add 用法为 <DLL 路径>"
    if isy "$DLL_INJECTOR_SKIPPED"; then
        die 1 dll-injector "无法 dll_injector_add '$1'：features.dll_inject.enabled 未启用"
    fi
    if isy "$DLL_INJECTOR_FINALIZED"; then
        die 1 dll-injector "无法 dll_injector_add '$1'：DLL 注入已经完成 prepare 收尾"
    fi
    DLL_INJECTOR_ADDED_DLLS+=("$(dll_injector_resolve_path "$1")")
    log_debug dll-injector "登记注入 DLL: $1"
}

feat_dll_inject_load_config() {
    if ! config_is_true features.dll_inject.enabled; then
        DLL_INJECTOR_SKIPPED=1
        [[ "${#DLL_INJECTOR_ADDED_DLLS[@]}" -eq 0 ]] ||
            die 1 dll-injector "已通过 dll_injector_add 登记 DLL，但 features.dll_inject.enabled 未启用"
        return 0
    fi

    # 实际收集和注册放到 prepare 收尾，允许其它 feature 在 prepare 里编译出 DLL 后再登记
    register_hook prepare feat_dll_inject_finalize 90
}

register_hook load_config feat_dll_inject_load_config

# prepare 收尾: 此时其它 feature 的 prepare 钩子 (默认 50) 已经执行完
feat_dll_inject_finalize() {
    local -a dlls=()
    config_read_array features.dll_inject.dlls dlls

    DLL_INJECTOR_DLLS=()
    local dll resolved
    for dll in "${dlls[@]}"; do
        [[ -n "$dll" ]] || die 1 dll-injector "features.dll_inject.dlls 含有空路径"
        # 只有 DLL 路径按原样解析，不跟随 overlay
        resolved="$(dll_injector_resolve_path "$dll")"
        [[ -f "$resolved" ]] || die 1 dll-injector "DLL 文件不存在: '$dll'"
        DLL_INJECTOR_DLLS+=("$resolved")
    done
    for dll in "${DLL_INJECTOR_ADDED_DLLS[@]}"; do
        [[ -f "$dll" ]] || die 1 dll-injector "DLL 文件不存在: '$dll'"
        DLL_INJECTOR_DLLS+=("$dll")
    done
    [[ "${#DLL_INJECTOR_DLLS[@]}" -gt 0 ]] || die 1 dll-injector "features.dll_inject.dlls 不能为空"

    if config_is_true features.dll_inject.no_wait; then
        DLL_INJECTOR_NO_WAIT=1
    fi

    launch_plan_register_game_handler dll-injector feat_dll_inject_handler

    check_cache_and_compile "dll-injector" \
        "$(dll_injector_exe_path)" \
        dll_injector_all_source \
        dll_injector_verify_output \
        dll_injector_compile

    dll_injector_prepare_launch_exe

    DLL_INJECTOR_FINALIZED=1
    log_info dll-injector "启用 DLL 注入，共 ${#DLL_INJECTOR_DLLS[@]} 个 DLL"
}

feat_dll_inject_handler() {
    # shellcheck disable=SC2178 # nameref 指向调用方的数组
    local -n _out="$1"

    local -a game_args=()
    launch_plan_args_get game_args
    local game_exe
    game_exe="$(launch_plan_get_game_exe)"

    # argv[0] 是注入器（或其别名）本体的 Unix 路径，由 runner 或脚本模式负责转换
    [[ -n "$DLL_INJECTOR_LAUNCH_EXE" ]] || dll_injector_prepare_launch_exe
    local -a argv=("$DLL_INJECTOR_LAUNCH_EXE")
    isy "$DLL_INJECTOR_NO_WAIT" && argv+=(--no-wait)
    local dll
    for dll in "${DLL_INJECTOR_DLLS[@]}"; do
        argv+=("$(wine_unix_path_to_windows "$dll")")
    done
    argv+=(-- "$(wine_unix_path_to_windows "$game_exe")" "${game_args[@]}")

    _out=("${argv[@]}")
}

dll_injector_exe_path() {
    cache_bin_path "dll-injector.exe"
}

# 读取自定义进程名，未设置时输出空；配置校验已保证非空时带 .exe 后缀
dll_injector_exe_name() {
    local name
    config_read features.dll_inject.exe_name name
    [[ -n "$name" ]] || return 0
    printf '%s\n' "$name"
}

# 解析并设置 DLL_INJECTOR_LAUNCH_EXE: 有自定义名就放入统一别名目录，否则用本体
dll_injector_prepare_launch_exe() {
    local name src
    name="$(dll_injector_exe_name)"
    if [[ -n "$name" ]]; then
        src="$(dll_injector_exe_path)"
        exe_alias_place "$name" "$src" DLL_INJECTOR_LAUNCH_EXE
    else
        DLL_INJECTOR_LAUNCH_EXE="$(dll_injector_exe_path)"
    fi
}

dll_injector_all_source() {
    toolspec_runtime_fingerprint "$DLL_INJECTOR_TOOL"
}

dll_injector_verify_output() {
    [[ -f "$1" ]]
}

dll_injector_compile() {
    toolspec_runtime_build "$DLL_INJECTOR_TOOL" "$1"
}
