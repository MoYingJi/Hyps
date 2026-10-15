#!/hint/bash

#shellcheck source=../core/log.sh
source "$SCRIPT_DIR/core/log.sh"
#shellcheck source=../utils.sh
source "$SCRIPT_DIR/utils.sh"

# 读取配置值到调用方变量 $2（不存在时使用默认值 $3），不创建子 Shell
#shellcheck disable=SC2178
config_read() {
    local _key="$1"
    local -n _var="$2"
    local _default="${3:-}"
    local -n _map="${4:-CONFIG}"

    if [[ -n "${_map[$_key]+exists}" ]]; then
        _var="${_map[$_key]}"
    else
        _var="$_default"
    fi
}

# 布尔读取：配置值（不存在时使用默认值 $2）符合 isy 的真值规则时返回 0
config_is_true() {
    local _value
    config_read "$1" _value "${2:-}"
    isy "$_value"
}

# 配置项未设置时写入默认值（不输出到 stdout）
#shellcheck disable=SC2178
config_default() {
    local key="$1"
    local default="${2:-}"
    local -n target_map="${3:-CONFIG}"

    if [[ -z "${target_map[$key]+exists}" ]]; then
        log_debug config "设置配置 [${3:-CONFIG}] $key = $default"
        target_map["$key"]="$default"
    fi
}

#shellcheck disable=SC2178
config_set() {
    local key="$1"
    local value="$2"
    local -n target_map="${3:-CONFIG}"
    log_debug config "设置配置 [${3:-CONFIG}] $key = $value"
    target_map["$key"]="$value"
}

#shellcheck disable=SC2178
config_unset() {
    local key="$1"
    local -n target_map="${2:-CONFIG}"
    unset "target_map[$key]"
}

#shellcheck disable=SC2178
config_has() {
    local key="$1"
    local -n target_map="${2:-CONFIG}"
    [[ -n "${target_map[$key]+exists}" ]]
}

# 获取 $1 的绝对路径，并将其存储回配置中
config_realpath() {
    local key="$1"
    local default="${2:-}"
    local target_map_name="${3:-CONFIG}"

    local value
    config_read "$key" value "$default" "$target_map_name"
    [ -n "$value" ] && value="$(realpath -m "$value")"
    config_set "$key" "$value" "$target_map_name"
}

# 获取 $1 的绝对路径，如果不是文件则报错，并将其存储回配置中
config_require_realpath_file() {
    local key="$1"
    local default="${2:-}"
    local target_map_name="${3:-CONFIG}"

    local value
    config_read "$key" value "$default" "$target_map_name"
    [[ -n "$value" ]] || die 1 config "配置项 '$key' 未设置"
    value="$(realpath -m "$value")"
    [[ -e "$value" ]] || die 1 config "配置项 '$key' 指向的文件不存在：'$value'"
    [[ -f "$value" ]] || die 1 config "配置项 '$key' 指向的路径不是文件：'$value'"
    config_set "$key" "$value" "$target_map_name"
}

# 获取 $1 的绝对路径，如果不是目录则报错，并将其存储回配置中
config_require_realpath_dir() {
    local key="$1"
    local default="${2:-}"
    local target_map_name="${3:-CONFIG}"

    local value
    config_read "$key" value "$default" "$target_map_name"
    [[ -n "$value" ]] || die 1 config "配置项 '$key' 未设置"
    value="$(realpath -m "$value")"
    [[ -e "$value" ]] || die 1 config "配置项 '$key' 指向的目录不存在：'$value'"
    [[ -d "$value" ]] || die 1 config "配置项 '$key' 指向的路径不是目录：'$value'"
    config_set "$key" "$value" "$target_map_name"
}

# 获取 $1 的绝对路径，如果不是目录且无法创建则报错，并将其存储回配置中
config_require_realpath_mkdir() {
    local key="$1"
    local default="${2:-}"
    local target_map_name="${3:-CONFIG}"

    local value
    config_read "$key" value "$default" "$target_map_name"
    [[ -n "$value" ]] || die 1 config "配置项 '$key' 未设置"
    value="$(realpath -m "$value")"
    [[ -e "$value" ]] && [[ ! -d "$value" ]] && die 1 config "配置项 '$key' 指向的路径不是目录：'$value'"
    [[ -d "$value" ]] || mkdir -p "$value" || die 1 config "配置项 '$key' 指向的目录不存在，且创建失败：'$value'"
    config_set "$key" "$value" "$target_map_name"
}

# 获取 $1 的绝对路径，如果不是可执行文件则报错，并将其存储回配置中
config_require_realpath_which_exe() {
    local key="$1"
    local default="${2:-}"
    local target_map_name="${3:-CONFIG}"

    local value path
    config_read "$key" value "$default" "$target_map_name"
    [[ -n "$value" ]] || die 1 config "配置项 '$key' 未设置"

    path="$(type -P -- "$value")" \
        || die 1 config "配置项 '$key' 指向的可执行文件不存在：'$value'"
    config_set "$key" "$path" "$target_map_name"
}

config_read_realpath_prefer_env() {
    local key="$1"
    local -n var="$2"
    local default="${3:-}"
    local target_map_name="${4:-CONFIG}"

    [[ -z "$var" ]] && config_read "$key" var "$default" "$target_map_name"
    var="$(realpath -m "$var")"
    config_set "$key" "$var" "$target_map_name"
}

#shellcheck disable=SC2034
config_read_array() {
    local key="$1"
    local var_array_name="$2"
    local -n var_array="$var_array_name"
    local default="${3:-}"
    local target_map_name="${4:-CONFIG}"

    [[ "${#var_array[@]}" -eq 0 ]] || return 0

    local array_str
    config_read "$key" array_str "$default" "$target_map_name"
    parse_array "$array_str" "$var_array_name" || die 1 config "配置项 '$key' 的值 '$array_str' 无法解析为数组"
}

#shellcheck disable=SC2178
config_print_all() {
    local -n target_map="${1:-CONFIG}"

    for key in "${!target_map[@]}"; do
        echo "$key: ${target_map[$key]}"
    done
}
