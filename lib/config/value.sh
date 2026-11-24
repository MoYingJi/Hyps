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
    local _cfg_literal_origin="$4"
    _cfg_literal="${_cfg_literal#"${_cfg_literal%%[![:space:]]*}"}"
    _cfg_literal="${_cfg_literal%"${_cfg_literal##*[![:space:]]}"}"
    _cfg_literal_kind=scalar
    if [[ "$_cfg_literal" == \"* || "$_cfg_literal" == \'* ]]; then
        [[ ${#_cfg_literal} -ge 2 && "${_cfg_literal: -1}" == "${_cfg_literal:0:1}" ]] ||
            die 1 config "$_cfg_literal_origin 引号未闭合"
        _cfg_literal="${_cfg_literal:1:-1}"
    elif array_syntax_started "$_cfg_literal"; then
        _cfg_literal_kind=array
    fi
    _config_value_validate "$_cfg_literal" "$_cfg_literal_kind" "$_cfg_literal_origin"
    _cfg_literal_out="$_cfg_literal"
}
