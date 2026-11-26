#!/hint/bash

[[ -n "${__UTILS_ARRAY_SH_LOADED:-}" ]] && return 0
__UTILS_ARRAY_SH_LOADED=1

#shellcheck source=quoted_string.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/quoted_string.sh"

# 本文件部分使用 LLM 生成

# 识别数组语法的起始，合法性由 parse_array 完整检查
array_syntax_started() {
    local string="$1"
    # 去除字符串前导空白
    string="${string#"${string%%[![:space:]]*}"}"
    [[ "$string" == \[* || "$string" == \(* ]]
}

parse_array() {
    local string="$1"
    # 去除字符串首尾空白
    string="${string#"${string%%[![:space:]]*}"}"
    string="${string%"${string##*[![:space:]]}"}"
    case "$string" in
        \[*\]) _parse_flat_array "${string:1:-1}" "$2" comma "${@:3}" ;;
        \(*\)) _parse_flat_array "${string:1:-1}" "$2" space "${@:3}" ;;
        *) return 1 ;;
    esac
}

# 字符串按空白分隔，引号和反斜杠按字面保留
split_args() {
    local -n _split_args_out="$2"
    IFS=$' \t\n' read -ra _split_args_out <<< "${1//$'\n'/ }"
}

# 参数列表接受数组或按空白分隔的字符串
parse_args() {
    if array_syntax_started "$1"; then
        parse_array "$1" "$2"
    else
        split_args "$1" "$2"
    fi
}

# 按顺序读取首个已设置的环境输入
# 返回 1 表示均未设置，返回 2 表示选中的输入格式无效
read_env_args() {
    local -n _env_args_out="$1" _env_args_source="$2"
    shift 2
    local _env_args_name _env_args_attributes
    _env_args_out=()
    _env_args_source=""
    for _env_args_name in "$@"; do
        _env_args_attributes="${!_env_args_name@a}"
        [[ -v "$_env_args_name" || "$_env_args_attributes" == *[aA]* ]] || continue
        _env_args_source="$_env_args_name"
        [[ "$_env_args_attributes" != *A* ]] || return 2
        if [[ "$_env_args_attributes" == *a* ]]; then
            local -n _env_args_input="$_env_args_name"
            _env_args_out=("${_env_args_input[@]}")
        else
            parse_args "${!_env_args_name}" _env_args_out || return 2
        fi
        return 0
    done
    return 1
}

parse_json_array() {
    local json="$1"
    # 去除字符串首尾空白
    json="${json#"${json%%[![:space:]]*}"}"
    json="${json%"${json##*[![:space:]]}"}"
    # 必须以 [ 开头，] 结尾
    [[ "$json" == \[*\] ]] || return 1
    _parse_flat_array "${json:1:-1}" "$2" comma
}

parse_bash_array() {
    local bash_array="$1"
    # 去除字符串首尾空白
    bash_array="${bash_array#"${bash_array%%[![:space:]]*}"}"
    bash_array="${bash_array%"${bash_array##*[![:space:]]}"}"
    # 必须以 ( 开头，) 结尾
    [[ "$bash_array" == \(*\) ]] || return 1
    _parse_flat_array "${bash_array:1:-1}" "$2" space
}

# 只解析一维字符串数组，只有调用方显式提供回调时才展开模板
# 完整解析成功后才替换输出，允许方括号数组的末尾逗号
_parse_flat_array() {
    local _arr_text="$1" _arr_mode="$3"
    local -n _arr_out="$2"
    local -a _arr_result=()
    local _arr_elem="" _arr_state=start _arr_char _arr_trimmed _arr_suffix _arr_rest
    local _arr_i _arr_status
    for ((_arr_i = 0; _arr_i < ${#_arr_text}; _arr_i++)); do
        _arr_char="${_arr_text:_arr_i:1}"
        case "$_arr_char" in
            '"' | "'")
                [[ "$_arr_state" == start ]] || return 1
                _arr_rest="${_arr_text:_arr_i}"
                _arr_status=0
                read_quoted_string "$_arr_rest" _arr_elem _arr_suffix "${@:4}" || _arr_status=$?
                [[ "$_arr_status" -eq 0 ]] || return "$_arr_status"
                ((_arr_i += ${#_arr_rest} - ${#_arr_suffix} - 1))
                _arr_state=closed
                ;;
            ',')
                if [[ "$_arr_mode" == space ]]; then
                    [[ "$_arr_state" != closed ]] || return 1
                    _arr_elem+=","
                    _arr_state=plain
                    continue
                fi
                # 结束当前元素
                [[ "$_arr_state" != start ]] || return 1
                if [[ "$_arr_state" == plain ]]; then
                    # 非引号元素：去除首尾空白
                    _arr_elem="${_arr_elem%"${_arr_elem##*[![:space:]]}"}"
                fi
                _arr_result+=("$_arr_elem")
                # 重置状态
                _arr_elem=""
                _arr_state=start
                ;;
            [[:space:]])
                if [[ "$_arr_mode" == space && "$_arr_state" != start ]]; then
                    # 空白字符作为元素分隔符
                    _arr_result+=("$_arr_elem")
                    _arr_elem=""
                    _arr_state=start
                elif [[ "$_arr_state" == plain ]]; then
                    _arr_elem+="$_arr_char"
                fi
                ;;
            '[' | ']' | '(' | ')') return 1 ;;
            *)
                [[ "$_arr_state" != closed ]] || return 1
                _arr_elem+="$_arr_char"
                _arr_state=plain
                ;;
        esac
    done
    # 处理最后一个元素
    if [[ "$_arr_state" != start ]]; then
        _arr_trimmed="$_arr_elem"
        [[ "$_arr_state" != plain ]] || _arr_trimmed="${_arr_elem%"${_arr_elem##*[![:space:]]}"}"
        _arr_result+=("$_arr_trimmed")
    fi
    _arr_out=("${_arr_result[@]}")
}

# 用可重新解析的一维数组表示保留元素边界
format_array() {
    local -n _fmt_array_out="$1"
    shift
    local _fmt_array_result="" _fmt_array_elem
    for _fmt_array_elem; do
        format_quoted_string _fmt_array_elem "$_fmt_array_elem"
        _fmt_array_result+="${_fmt_array_result:+, }$_fmt_array_elem"
    done
    _fmt_array_out="[$_fmt_array_result]"
}
