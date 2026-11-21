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

config_declare compile.CC string --default gcc
config_declare compile.CFLAGS array --default '[]'
config_declare compile.mingw.CC string --default x86_64-w64-mingw32-gcc
config_declare compile.mingw.CFLAGS array --default '[]'

build_load_config() {
    build_read_flags CFLAGS compile.CFLAGS HYPS_CFLAGS
    build_read_cc CC compile.CC HYPS_CC
    build_read_cc HYPS_WIN_CC compile.mingw.CC HYPS_WIN_CC
    build_read_flags MINGW_CFLAGS compile.mingw.CFLAGS HYPS_MINGW_CFLAGS
}

build_read_flags() {
    local env_name="$1"
    local config_key="$2"
    local output_name="$3"
    local env_value="${!env_name:-}"
    local env_attributes="${!env_name@a}"
    local env_present=false
    [[ -v "$env_name" || "$env_attributes" == *a* ]] && env_present=true
    local -a flags=()

    unset "$output_name"

    if [[ "$env_present" == true ]] && config_has "$config_key"; then
        log_debug environment "$env_name 已在环境变量中设置，$config_key 配置项将被忽略"
    fi

    if [[ "$env_present" == true ]]; then
        if [[ "$env_attributes" == *a* ]]; then
            #shellcheck disable=SC2178
            local -n env_flags="$env_name"
            flags=("${env_flags[@]}")
        else
            read -ra flags <<< "$env_value"
        fi
    else
        config_read_array "$config_key" flags
    fi

    #shellcheck disable=SC2178
    local -n output_flags="$output_name"
    #shellcheck disable=SC2034
    output_flags=("${flags[@]}")
    log_debug environment "应用内 CFLAGS [$config_key]: $(quote_args "${flags[@]}")"
}

build_read_cc() {
    local env_name="$1"
    local config_key="$2"
    local output_name="$3"
    local env_value="${!env_name:-}"
    local value=""
    local env_present=false
    [[ -v "$env_name" ]] && env_present=true

    unset "$output_name"

    if [[ "$env_present" == true ]] && config_has "$config_key"; then
        log_debug environment "$env_name 已在环境变量中设置，$config_key 配置项将被忽略"
    fi

    if [[ "$env_present" == true ]]; then
        value="$env_value"
    else
        config_read "$config_key" value
    fi

    printf -v "$output_name" '%s' "$value"
    log_debug environment "应用内 CC [$config_key]: '$value'"
}

register_hook load_config build_load_config
