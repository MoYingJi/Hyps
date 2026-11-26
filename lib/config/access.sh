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

_config_expand_reference() {
    local _cfg_ref="$1" _cfg_ref_key="$3" _cfg_ref_origin="$4" _cfg_ref_kind="$5"
    local -n _cfg_ref_out="$2"
    local _cfg_ref_schema _cfg_ref_target _cfg_ref_source _cfg_ref_status=0
    local _cfg_ref_layers _cfg_ref_target_layers _cfg_ref_value_kind _cfg_ref_deferred
    _config_schema_key "$_cfg_ref_key" _cfg_ref_schema
    _cfg_ref_layers=",${CONFIG_SCHEMA[$_cfg_ref_schema.in]:-global,game-instance},"

    if [[ "$_cfg_ref_kind" == scalar && "${CONFIG_SCHEMA[$_cfg_ref_schema.type]:-}" == args ]]; then
        die 1 config "$_cfg_ref_origin 配置项 '$_cfg_ref_key' 的参数模板需要使用数组"
    fi
    if [[ "$_cfg_ref" == game.name ]]; then
        [[ "$_cfg_resolve_view" == effective && "$_cfg_ref_layers" == *',game-instance,'* ]] ||
            die 1 config "$_cfg_ref_origin 配置项 '$_cfg_ref_key' 不能引用游戏名"
        [[ -n "${CONFIG_GAME_NAME:-}" ]] || return 4
        _cfg_ref_out="$CONFIG_GAME_NAME"
        return 0
    fi

    _config_schema_key "$_cfg_ref" _cfg_ref_target
    _cfg_ref_target_layers="${CONFIG_SCHEMA[$_cfg_ref_target.in]:-}"
    [[ -n "$_cfg_ref_target_layers" || -n "${_cfg_resolve_values[$_cfg_ref]+exists}" ]] ||
        die 1 config "$_cfg_ref_origin 配置项 '$_cfg_ref_key' 使用了未知的模板引用 '\${$_cfg_ref}'"
    _cfg_ref_target_layers=",${_cfg_ref_target_layers:-global,game-instance},"

    if [[ "$_cfg_resolve_view" == bootstrap && "$_cfg_ref_target_layers" != *',bootstrap,'* ]]; then
        die 1 config "$_cfg_ref_origin 配置项 '$_cfg_ref_key' 在引导阶段无法引用 '$_cfg_ref'"
    fi
    if [[ "$_cfg_resolve_view" == global && "$_cfg_ref_target_layers" != *',global,'* &&
          "$_cfg_ref_target_layers" != *',bootstrap,'* ]]; then
        die 1 config "$_cfg_ref_origin 配置项 '$_cfg_ref_key' 无法引用只在 runner 或游戏中可用的 '$_cfg_ref'"
    fi

    _config_resolve "$_cfg_ref" _cfg_ref_out _cfg_ref_source _cfg_ref_value_kind _cfg_ref_deferred || _cfg_ref_status=$?
    [[ "$_cfg_ref_deferred" != true ]] || return 4
    [[ "$_cfg_ref_status" -eq 0 ]] ||
        die 1 config "$_cfg_ref_origin 配置项 '$_cfg_ref_key' 引用的 '$_cfg_ref' 尚未设置"
    [[ "$_cfg_ref_value_kind" == scalar ]] ||
        die 1 config "$_cfg_ref_origin 配置项 '$_cfg_ref_key' 需要引用标量，'$_cfg_ref' 是数组"
    [[ "${CONFIG_SCHEMA[$_cfg_ref_target.type]:-string}" != path || -n "$_cfg_ref_out" ]] ||
        die 1 config "$_cfg_ref_origin 配置项 '$_cfg_ref_key' 引用的路径 '$_cfg_ref' 为空"
}

_config_resolve_literal() {
    _config_value_parse "$2" "$4" "$5" "$3 配置项 '$1'" _config_expand_reference "$1" "$3"
}

# 默认值函数接受输出变量名，可返回 3 表示当前上下文没有默认值
_config_resolve() {
    local _cfg_resolve_key="$1"
    local -n _cfg_resolve_out="$2" _cfg_resolve_source="$3"
    local _cfg_resolve_value="" _cfg_resolve_origin="" _cfg_resolve_fn _cfg_resolve_rc=0
    local _cfg_resolve_kind=scalar _cfg_resolve_unused_kind _cfg_resolve_unused_deferred
    local -n _cfg_resolve_kind_out="${4:-_cfg_resolve_unused_kind}"
    local -n _cfg_resolve_deferred_out="${5:-_cfg_resolve_unused_deferred}"
    local _cfg_resolve_view="${_cfg_resolve_view:-effective}"
    local _cfg_resolve_schema _cfg_resolve_layers
    local -n _cfg_resolve_values=CONFIG _cfg_resolve_sources=CONFIG_SOURCE _cfg_resolve_kinds=CONFIG_KIND
    _cfg_resolve_deferred_out=false
    _config_schema_key "$_cfg_resolve_key" _cfg_resolve_schema
    _cfg_resolve_layers=",${CONFIG_SCHEMA[$_cfg_resolve_schema.in]:-global,game-instance},"

    if [[ "$_cfg_resolve_layers" == ',bootstrap,' ]]; then
        _cfg_resolve_view=bootstrap
    elif [[ "$_cfg_resolve_view" == effective && "$_cfg_resolve_layers" != *',runner,'* &&
            "$_cfg_resolve_layers" != *',game-instance,'* ]]; then
        _cfg_resolve_view=global
    fi
    if [[ "$_cfg_resolve_view" != effective && "$_CONFIG_GLOBAL_READY" == true ]]; then
        local -n _cfg_resolve_values=_CONFIG_GLOBAL _cfg_resolve_sources=_CONFIG_GLOBAL_ORIGINS \
            _cfg_resolve_kinds=_CONFIG_GLOBAL_KIND
    fi

    [[ -z "${_CONFIG_RESOLVING[$_cfg_resolve_key]:-}" ]] ||
        die 1 config "${_cfg_resolve_sources[$_cfg_resolve_key]:-默认值} 配置项 '$_cfg_resolve_key' 存在循环依赖"
    _CONFIG_RESOLVING["$_cfg_resolve_key"]=1

    if [[ -n "${_cfg_resolve_values[$_cfg_resolve_key]+exists}" ]]; then
        _cfg_resolve_value="${_cfg_resolve_values[$_cfg_resolve_key]}"
        _cfg_resolve_origin="${_cfg_resolve_sources[$_cfg_resolve_key]:-运行时}"
        _cfg_resolve_kind="${_cfg_resolve_kinds[$_cfg_resolve_key]}"
        if [[ "$_cfg_resolve_kind" == literal ]]; then
            _config_resolve_literal "$_cfg_resolve_key" "$_cfg_resolve_value" "$_cfg_resolve_origin" \
                _cfg_resolve_value _cfg_resolve_kind || _cfg_resolve_rc=$?
        fi
    elif [[ -n "${CONFIG_SCHEMA[$_cfg_resolve_schema.default]+exists}" ]]; then
        _cfg_resolve_value="${CONFIG_SCHEMA[$_cfg_resolve_schema.default]}"
        _cfg_resolve_origin="默认值"
        _config_resolve_literal "$_cfg_resolve_key" "$_cfg_resolve_value" "$_cfg_resolve_origin" \
            _cfg_resolve_value _cfg_resolve_kind || _cfg_resolve_rc=$?
    elif [[ -n "${CONFIG_SCHEMA[$_cfg_resolve_schema.default-fn]:-}" ]]; then
        _cfg_resolve_fn="${CONFIG_SCHEMA[$_cfg_resolve_schema.default-fn]}"
        declare -F "$_cfg_resolve_fn" >/dev/null ||
            die 1 config "配置项 '$_cfg_resolve_key' 的默认值函数 '$_cfg_resolve_fn' 不存在"
        "$_cfg_resolve_fn" _cfg_resolve_value _cfg_resolve_kind || _cfg_resolve_rc=$?
        if [[ "$_cfg_resolve_rc" -ne 0 && "$_cfg_resolve_rc" -ne 3 ]]; then
            die 1 config "配置项 '$_cfg_resolve_key' 的默认值计算失败"
        fi
        _cfg_resolve_origin="默认值 ($_cfg_resolve_fn)"
    else
        _cfg_resolve_rc=3
    fi

    if [[ "$_cfg_resolve_rc" -ne 0 ]]; then
        unset '_CONFIG_RESOLVING[$_cfg_resolve_key]'
        # 依赖只读游戏名的值在无游戏上下文时延迟展开
        if [[ "$_cfg_resolve_rc" -eq 4 ]]; then
            _cfg_resolve_deferred_out=true
            _cfg_resolve_rc=3
        fi
        [[ "$_cfg_resolve_rc" -eq 3 ]] || return "$_cfg_resolve_rc"
        _cfg_resolve_out=""
        _cfg_resolve_source="未设置"
        _cfg_resolve_kind_out=""
        [[ "${CONFIG_SCHEMA[$_cfg_resolve_schema.required]:-}" != true ]] ||
            die 1 config "配置项 '$_cfg_resolve_key' 未设置"
        return 3
    fi

    _config_normalize "$_cfg_resolve_key" _cfg_resolve_value "$_cfg_resolve_origin" "$_cfg_resolve_kind"
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
    _cfg_resolve_kind_out="$_cfg_resolve_kind"
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
    [[ $# -eq 2 || $# -eq 3 ]] || die 1 config "config_read 用法为 <配置键> <输出变量> [结构输出变量]"
    local _cfg_read_value _cfg_read_source _cfg_read_kind _cfg_read_rc=0
    _config_resolve "$1" _cfg_read_value _cfg_read_source _cfg_read_kind || _cfg_read_rc=$?
    [[ "$_cfg_read_rc" -eq 0 || "$_cfg_read_rc" -eq 3 ]] || return "$_cfg_read_rc"
    local -n _cfg_read_out="$2"
    _cfg_read_out="$_cfg_read_value"
    if [[ $# -eq 3 ]]; then
        local -n _cfg_read_kind_out="$3"
        _cfg_read_kind_out="$_cfg_read_kind"
    fi
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
    [[ $# -ge 2 && $# -le 4 ]] || die 1 config "config_set 用法为 <配置键> <值> [来源] [scalar|array]"
    [[ "$1" != game.name ]] || die 1 config "'game.name' 是只读的模板引用"
    _config_value_validate "$2" "${4:-scalar}" "${3:-运行时} 配置项 '$1'"
    CONFIG["$1"]="$2"
    CONFIG_SOURCE["$1"]="${3:-运行时}"
    CONFIG_KIND["$1"]="${4:-scalar}"
}

config_unset() {
    unset 'CONFIG[$1]' 'CONFIG_SOURCE[$1]' 'CONFIG_KIND[$1]'
}

# 每次读取替换整个输出数组，不继承调用方的旧内容
config_read_array() {
    [[ $# -eq 2 ]] || die 1 config "config_read_array 用法为 <配置键> <输出数组>"
    local _cfg_array_value _cfg_array_source _cfg_array_kind _cfg_array_rc=0
    local -n _cfg_array_out="$2"
    _config_resolve "$1" _cfg_array_value _cfg_array_source _cfg_array_kind || _cfg_array_rc=$?
    _cfg_array_out=()
    [[ "$_cfg_array_rc" -ne 3 ]] || return 0
    [[ "$_cfg_array_rc" -eq 0 ]] || return "$_cfg_array_rc"
    local _cfg_array_schema _cfg_array_parser=parse_array
    _config_schema_key "$1" _cfg_array_schema
    if [[ "$_cfg_array_kind" == scalar ]]; then
        [[ "${CONFIG_SCHEMA[$_cfg_array_schema.type]:-}" == args ]] ||
            die 1 config "配置项 '$1' 不是数组 ($_cfg_array_source)"
        _cfg_array_parser=split_args
    fi
    "$_cfg_array_parser" "$_cfg_array_value" "$2" ||
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

# 在解析路径引用之前保留环境变量优先的约定
config_capture_path_override() {
    local -n _cfg_path_override="$2"
    [[ -z "$_cfg_path_override" ]] || config_set "$1" "$_cfg_path_override" "环境变量 $2"
}
