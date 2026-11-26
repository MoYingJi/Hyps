#!/hint/bash

[[ -n "${__MODULES_SH_LOADED:-}" ]] && return 0
__MODULES_SH_LOADED=1

#shellcheck source=libs.sh
source "$SCRIPT_DIR/libs.sh"

# 启动和配置查询共用模块清单，只加载声明和注册钩子
hyps_load_modules() {
    [[ -z "${__HYPS_MODULES_LOADED:-}" ]] || return 0

    #shellcheck source=config/environment.sh
    source "$SCRIPT_DIR/config/environment.sh" || return $?
    #shellcheck source=config/build.sh
    source "$SCRIPT_DIR/config/build.sh" || return $?
    #shellcheck source=shared/xwin_watch.sh
    source "$SCRIPT_DIR/shared/xwin_watch.sh" || return $?
    #shellcheck source=shared/dll_injector.sh
    source "$SCRIPT_DIR/shared/dll_injector.sh" || return $?

    local feature_script
    for feature_script in "$SCRIPT_DIR"/features/*.sh; do
        #shellcheck source=/dev/null
        source "$feature_script" || return $?
    done
    __HYPS_MODULES_LOADED=1
}
