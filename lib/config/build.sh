#!/hint/bash

[[ -n "${__CONFIG_BUILD_SH_LOADED:-}" ]] && return 0
__CONFIG_BUILD_SH_LOADED=1

#shellcheck source=schema.sh
source "$SCRIPT_DIR/config/schema.sh"
#shellcheck source=access.sh
source "$SCRIPT_DIR/config/access.sh"
#shellcheck source=../core/lifecycle.sh
source "$SCRIPT_DIR/core/lifecycle.sh"
#shellcheck source=../core/log.sh
source "$SCRIPT_DIR/core/log.sh"
#shellcheck source=../utils/string.sh
source "$SCRIPT_DIR/utils/string.sh"
#shellcheck source=../utils/array.sh
source "$SCRIPT_DIR/utils/array.sh"

config_declare compile.CC args --default gcc
config_declare compile.CFLAGS args --default '[]'
config_declare compile.mingw.CC args --default x86_64-w64-mingw32-gcc
config_declare compile.mingw.CFLAGS args --default '[]'

build_load_config() {
    build_read_args compile.CC BUILD_CC HYPS_CC CC || return $?
    build_read_args compile.CFLAGS BUILD_CFLAGS HYPS_CFLAGS CFLAGS || return $?
    build_read_args compile.mingw.CC BUILD_MINGW_CC HYPS_MINGW_CC || return $?
    build_read_args compile.mingw.CFLAGS BUILD_MINGW_CFLAGS HYPS_MINGW_CFLAGS
}

# 构建结果与外部输入分开保存，重复加载时重新读取输入与配置
# build_read_args <配置键> <输出数组> [按优先级排列的环境变量...]
build_read_args() {
    local config_key="$1" output_name="$2"
    shift 2
    local input_source status=0
    local -a args=()

    read_env_args args input_source "$@" || status=$?
    case "$status" in
        0)
            if config_has "$config_key"; then
                log_debug build "$input_source 已设置，$config_key 配置项将被忽略"
            fi
            ;;
        1) config_read_array "$config_key" args ;;
        *) die 1 build "环境变量 '$input_source' 格式无效，请使用 args 字符串或 Bash 索引数组" ;;
    esac

    unset "$output_name"
    #shellcheck disable=SC2178
    local -n output_args="$output_name"
    #shellcheck disable=SC2034
    output_args=("${args[@]}")
    log_debug build "应用内构建参数 [$config_key，来源 ${input_source:-配置}]: $(quote_args "${args[@]}")"
}

register_hook load_config build_load_config
