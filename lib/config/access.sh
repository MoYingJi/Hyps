#!/hint/bash

[[ -n "${__CONFIG_ACCESS_SH_LOADED:-}" ]] && return 0
__CONFIG_ACCESS_SH_LOADED=1

#shellcheck source=state.sh
source "$SCRIPT_DIR/config/state.sh"
#shellcheck source=schema.sh
source "$SCRIPT_DIR/config/schema.sh"
#shellcheck source=types.sh
source "$SCRIPT_DIR/config/types.sh"
#shellcheck source=../core/log.sh
source "$SCRIPT_DIR/core/log.sh"
#shellcheck source=../utils/string.sh
source "$SCRIPT_DIR/utils/string.sh"
#shellcheck source=../utils/array.sh
source "$SCRIPT_DIR/utils/array.sh"

declare -gA _CONFIG_RESOLVING=()

# 默认值函数接受输出变量名，可返回 3 表示当前上下文没有默认值
_config_resolve() {
    local _cfg_resolve_key="$1"
    local -n _cfg_resolve_out="$2" _cfg_resolve_source="$3"
    local _cfg_resolve_value="" _cfg_resolve_origin="" _cfg_resolve_fn _cfg_resolve_rc=0
    local _cfg_resolve_schema
    _config_schema_key "$_cfg_resolve_key" _cfg_resolve_schema

    [[ -z "${_CONFIG_RESOLVING[$_cfg_resolve_key]:-}" ]] ||
        die 1 config "配置项 '$_cfg_resolve_key' 的默认值存在循环依赖"
    _CONFIG_RESOLVING["$_cfg_resolve_key"]=1

    if [[ -n "${CONFIG[$_cfg_resolve_key]+exists}" ]]; then
        _cfg_resolve_value="${CONFIG[$_cfg_resolve_key]}"
        _cfg_resolve_origin="${CONFIG_SOURCE[$_cfg_resolve_key]:-运行时}"
    elif [[ -n "${CONFIG_SCHEMA[$_cfg_resolve_schema.default]+exists}" ]]; then
        _cfg_resolve_value="${CONFIG_SCHEMA[$_cfg_resolve_schema.default]}"
        _cfg_resolve_origin="默认值"
    elif [[ -n "${CONFIG_SCHEMA[$_cfg_resolve_schema.default-fn]:-}" ]]; then
        _cfg_resolve_fn="${CONFIG_SCHEMA[$_cfg_resolve_schema.default-fn]}"
        declare -F "$_cfg_resolve_fn" >/dev/null ||
            die 1 config "配置项 '$_cfg_resolve_key' 的默认值函数 '$_cfg_resolve_fn' 不存在"
        "$_cfg_resolve_fn" _cfg_resolve_value || _cfg_resolve_rc=$?
        if [[ "$_cfg_resolve_rc" -ne 0 && "$_cfg_resolve_rc" -ne 3 ]]; then
            die 1 config "配置项 '$_cfg_resolve_key' 的默认值计算失败"
        fi
        _cfg_resolve_origin="默认值 ($_cfg_resolve_fn)"
    else
        _cfg_resolve_rc=3
    fi

    if [[ "$_cfg_resolve_rc" -eq 3 ]]; then
        unset '_CONFIG_RESOLVING[$_cfg_resolve_key]'
        _cfg_resolve_out=""
        _cfg_resolve_source="未设置"
        [[ "${CONFIG_SCHEMA[$_cfg_resolve_schema.required]:-}" != true ]] ||
            die 1 config "配置项 '$_cfg_resolve_key' 未设置"
        return 3
    fi

    _config_normalize "$_cfg_resolve_key" _cfg_resolve_value "$_cfg_resolve_origin"
    if [[ "${CONFIG_SCHEMA[$_cfg_resolve_schema.required]:-}" == true && -z "$_cfg_resolve_value" ]]; then
        die 1 config "配置项 '$_cfg_resolve_key' 不能为空 ($_cfg_resolve_origin)"
    fi
    _cfg_resolve_fn="${CONFIG_SCHEMA[$_cfg_resolve_schema.validate]:-}"
    if [[ -n "$_cfg_resolve_fn" ]]; then
        declare -F "$_cfg_resolve_fn" >/dev/null ||
            die 1 config "配置项 '$_cfg_resolve_key' 的校验函数 '$_cfg_resolve_fn' 不存在"
        "$_cfg_resolve_fn" "$_cfg_resolve_value" ||
            die 1 config "配置项 '$_cfg_resolve_key' 的值 '$_cfg_resolve_value' 无效 ($_cfg_resolve_origin)"
    fi

    unset '_CONFIG_RESOLVING[$_cfg_resolve_key]'
    _cfg_resolve_out="$_cfg_resolve_value"
    _cfg_resolve_source="$_cfg_resolve_origin"
}

_config_schema_active() {
    local key="$1" schema_key when field fn condition_key
    _config_schema_key "$key" schema_key
    for field in default-fn validate; do
        fn="${CONFIG_SCHEMA[$schema_key.$field]:-}"
        [[ -z "$fn" ]] || declare -F "$fn" >/dev/null ||
            die 1 config "配置项 '$key' 引用的函数 '$fn' 不存在"
    done
    when="${CONFIG_SCHEMA[$schema_key.when]:-}"
    [[ -n "$when" ]] || return 0
    _config_schema_key "$when" condition_key
    [[ "${CONFIG_SCHEMA[$condition_key.type]:-}" == bool ]] ||
        die 1 config "配置项 '$key' 的条件 '$when' 必须声明为 bool"
    config_is_true "$when"
}

# 不传前缀时检查全部已声明项，多个前缀之间取并集
#shellcheck disable=SC2034
config_validate() {
    local key prefix selected value matched=false
    local -A keys=()
    for key in "${CONFIG_NAMESPACE_KEYS[@]}"; do
        selected=false
        [[ $# -gt 0 ]] || selected=true
        for prefix in "$@"; do
            [[ "$key" == "$prefix" || "$key" == "$prefix".* || "$prefix" == "$key".* ]] && selected=true
        done
        [[ "$selected" == true ]] || continue
        matched=true
        # 即使命名空间尚无成员，也检查其声明引用的条件与函数
        _config_schema_active "$key.*" || continue
    done
    for key in "${CONFIG_SCHEMA_KEYS[@]}" "${!CONFIG[@]}"; do
        config_is_declared "$key" && keys["$key"]=1
    done
    for key in "${!keys[@]}"; do
        selected=false
        [[ $# -gt 0 ]] || selected=true
        for prefix in "$@"; do
            [[ "$key" == "$prefix" || "$key" == "$prefix".* ]] && selected=true
        done
        [[ "$selected" == true ]] || continue
        matched=true
        _config_schema_active "$key" || continue
        config_read "$key" value
    done
    [[ $# -eq 0 || "$matched" == true ]] || die 1 config "没有匹配的配置声明：$*"
    return 0
}

# 读取并校验有效值，不写回原始配置，也不创建子 shell
# 可选项缺失时输出空字符串，缺失与显式空值可通过 config_has 区分
config_read() {
    [[ $# -eq 2 ]] || die 1 config "config_read 用法为 <配置键> <输出变量>"
    local _cfg_read_value _cfg_read_source _cfg_read_rc=0
    _config_resolve "$1" _cfg_read_value _cfg_read_source || _cfg_read_rc=$?
    [[ "$_cfg_read_rc" -eq 0 || "$_cfg_read_rc" -eq 3 ]] || return "$_cfg_read_rc"
    local -n _cfg_read_out="$2"
    _cfg_read_out="$_cfg_read_value"
}

config_is_true() {
    [[ $# -eq 1 ]] || die 1 config "config_is_true 用法为 <配置键>"
    local _cfg_bool_value
    config_read "$1" _cfg_bool_value
    isy "$_cfg_bool_value"
}

# 只判断原始配置或运行时覆盖，不将 schema 默认值视为显式配置
config_has() {
    local -n _cfg_has_map="${2:-CONFIG}"
    [[ -n "${_cfg_has_map[$1]+exists}" ]]
}

#shellcheck disable=SC2034
config_set() {
    CONFIG["$1"]="$2"
    CONFIG_SOURCE["$1"]="${3:-运行时}"
}

config_unset() {
    unset 'CONFIG[$1]' 'CONFIG_SOURCE[$1]'
}

# 每次读取替换整个输出数组，不继承调用方的旧内容
config_read_array() {
    [[ $# -eq 2 ]] || die 1 config "config_read_array 用法为 <配置键> <输出数组>"
    local _cfg_array_value _cfg_array_source _cfg_array_rc=0
    local -n _cfg_array_out="$2"
    _config_resolve "$1" _cfg_array_value _cfg_array_source || _cfg_array_rc=$?
    _cfg_array_out=()
    [[ "$_cfg_array_rc" -ne 3 ]] || return 0
    [[ "$_cfg_array_rc" -eq 0 ]] || return "$_cfg_array_rc"
    parse_array "$_cfg_array_value" "$2" ||
        die 1 config "配置项 '$1' 的值 '$_cfg_array_value' 无法解析为数组 ($_cfg_array_source)"
}

config_source() {
    local _cfg_source_value _cfg_source_origin _cfg_source_rc=0
    _config_resolve "$1" _cfg_source_value _cfg_source_origin || _cfg_source_rc=$?
    [[ "$_cfg_source_rc" -eq 0 || "$_cfg_source_rc" -eq 3 ]] || return "$_cfg_source_rc"
    local -n _cfg_source_out="$2"
    _cfg_source_out="$_cfg_source_origin"
}

# 路径存在性属于操作要求，检查只读且不会创建目录
config_require() {
    local key="$1" kind="${2:-value}" value
    config_read "$key" value
    [[ -n "$value" ]] || die 1 config "配置项 '$key' 不能为空"
    case "$kind" in
        value) ;;
        file) [[ -f "$value" ]] || die 1 config "配置项 '$key' 指向的文件不存在：'$value'" ;;
        dir) [[ -d "$value" ]] || die 1 config "配置项 '$key' 指向的目录不存在：'$value'" ;;
        executable)
            type -P -- "$value" >/dev/null ||
                die 1 config "配置项 '$key' 指向的可执行文件不存在：'$value'"
            ;;
        *) die 1 config "未知配置检查 '$kind'" ;;
    esac
}

# 目录变量保留环境变量优先的约定，计算结果仍经过 schema 规范化
config_bind_path() {
    local key="$1"
    local -n _cfg_bind_out="$2"
    [[ -z "$_cfg_bind_out" ]] || config_set "$key" "$_cfg_bind_out" "环境变量 $2"
    config_read "$key" "$2"
}
