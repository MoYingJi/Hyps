#!/hint/bash

[[ -n "${__CONFIG_VALUE_SH_LOADED:-}" ]] && return 0
__CONFIG_VALUE_SH_LOADED=1

#shellcheck source=../core/log.sh
source "$SCRIPT_DIR/core/log.sh"
#shellcheck source=../utils/array.sh
source "$SCRIPT_DIR/utils/array.sh"

# 标量保留内容，数组必须通过完整语法校验
_config_value_validate() {
    local -a _cfg_value_elements=()
    case "$2" in
        scalar) ;;
        array)
            parse_array "$1" _cfg_value_elements ||
                die 1 config "$3 数组格式错误：$1"
            ;;
        *) die 1 config "$3 未知的配置值结构 '$2'" ;;
    esac
}

# 仅在输入边界识别语法，去掉引号后不再推断结构
_config_value_parse() {
    local _cfg_literal="$1"
    local -n _cfg_literal_out="$2" _cfg_literal_kind="$3"
    local _cfg_literal_origin="$4" _cfg_literal_fn="${5:-}" _cfg_literal_remainder _cfg_literal_status=0
    _cfg_literal="${_cfg_literal#"${_cfg_literal%%[![:space:]]*}"}"
    _cfg_literal="${_cfg_literal%"${_cfg_literal##*[![:space:]]}"}"
    _cfg_literal_kind=scalar
    if [[ "$_cfg_literal" == \"* || "$_cfg_literal" == \'* ]]; then
        read_quoted_string "$_cfg_literal" _cfg_literal _cfg_literal_remainder \
            "$_cfg_literal_origin" "$_cfg_literal_fn" "${@:6}" scalar || return $?
        [[ "$_cfg_literal_remainder" != *[![:space:]]* ]] ||
            die 1 config "$_cfg_literal_origin 结束引号后有多余内容"
    elif array_syntax_started "$_cfg_literal"; then
        local -a _cfg_literal_elements=()
        parse_array "$_cfg_literal" _cfg_literal_elements "$_cfg_literal_origin" \
            "$_cfg_literal_fn" "${@:6}" array || _cfg_literal_status=$?
        [[ "$_cfg_literal_status" -ne 4 ]] || return 4
        [[ "$_cfg_literal_status" -eq 0 ]] || die 1 config "$_cfg_literal_origin 数组格式错误：$_cfg_literal"
        _cfg_literal_kind=array
        format_array _cfg_literal "${_cfg_literal_elements[@]}"
    fi
    _cfg_literal_out="$_cfg_literal"
}

# 文件加载时检查引用语法，具体值等配置合并后再读取
_config_validate_reference() {
    local -n _cfg_reference_out="$2"
    _cfg_reference_out=""
}
