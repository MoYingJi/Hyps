#!/hint/bash

[[ -n "${__QUOTED_STRING_SH_LOADED:-}" ]] && return 0
__QUOTED_STRING_SH_LOADED=1

_quoted_string_error() {
    [[ -z "$1" ]] || die 1 config "$1 $2"
    return 1
}

# 读取一段带引号的字符串，返回解码结果和结束引号之后的内容
# 提供回调时识别模板，回调接收引用名、输出变量名和附加参数
read_quoted_string() {
    local _qs_input="$1" _qs_origin="${4:-}" _qs_reference_fn="${5:-}"
    local -n _qs_out="$2" _qs_remainder="$3"
    local _qs_quote="${_qs_input:0:1}" _qs_text="${_qs_input:1}"
    local _qs_result="" _qs_char _qs_ref _qs_value _qs_i _qs_status

    if [[ "$_qs_quote" == "'" ]]; then
        [[ "$_qs_text" == *"'"* ]] || { _quoted_string_error "$_qs_origin" "单引号未闭合"; return 1; }
        _qs_out="${_qs_text%%\'*}"
        _qs_remainder="${_qs_text#*\'}"
        return 0
    fi

    for ((_qs_i=0; _qs_i<${#_qs_text}; _qs_i++)); do
        _qs_char="${_qs_text:_qs_i:1}"
        case "$_qs_char" in
            '"')
                _qs_out="$_qs_result"
                _qs_remainder="${_qs_text:_qs_i+1}"
                return 0
                ;;
            \\)
                ((_qs_i += 1))
                _qs_char="${_qs_text:_qs_i:1}"
                case "$_qs_char" in
                    '"' | \\ | '$') _qs_result+="$_qs_char" ;;
                    n) _qs_result+=$'\n' ;;
                    t) _qs_result+=$'\t' ;;
                    r) _qs_result+=$'\r' ;;
                    b) _qs_result+=$'\b' ;;
                    f) _qs_result+=$'\f' ;;
                    '') _quoted_string_error "$_qs_origin" "反斜杠后缺少转义字符"; return 1 ;;
                    *) _quoted_string_error "$_qs_origin" "不支持的转义 '\\$_qs_char'，原样保留反斜杠请用单引号或双写反斜杠"; return 1 ;;
                esac
                ;;
            '$')
                if [[ -z "$_qs_reference_fn" || "${_qs_text:_qs_i+1:1}" != '{' ]]; then
                    _qs_result+='$'
                    continue
                fi
                _qs_ref="${_qs_text:_qs_i+2}"
                [[ "$_qs_ref" == *'}'* ]] || { _quoted_string_error "$_qs_origin" "模板引用缺少右花括号"; return 1; }
                _qs_ref="${_qs_ref%%\}*}"
                [[ "$_qs_ref" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]] || {
                    _quoted_string_error "$_qs_origin" "无效的模板引用 '\${$_qs_ref}'"
                    return 1
                }
                _qs_status=0
                "$_qs_reference_fn" "$_qs_ref" _qs_value "${@:6}" || _qs_status=$?
                [[ "$_qs_status" -eq 0 ]] || return "$_qs_status"
                _qs_result+="$_qs_value"
                ((_qs_i += ${#_qs_ref} + 2))
                ;;
            *) _qs_result+="$_qs_char" ;;
        esac
    done
    _quoted_string_error "$_qs_origin" "双引号未闭合"
}

# 序列化为可重新读取的双引号字面量
format_quoted_string() {
    local -n _fmt_string_out="$1"
    local _fmt_string_value="$2"
    _fmt_string_value="${_fmt_string_value//\\/\\\\}"
    _fmt_string_value="${_fmt_string_value//\"/\\\"}"
    _fmt_string_value="${_fmt_string_value//\$/\\\$}"
    _fmt_string_value="${_fmt_string_value//$'\n'/\\n}"
    _fmt_string_value="${_fmt_string_value//$'\t'/\\t}"
    _fmt_string_value="${_fmt_string_value//$'\r'/\\r}"
    _fmt_string_value="${_fmt_string_value//$'\b'/\\b}"
    _fmt_string_value="${_fmt_string_value//$'\f'/\\f}"
    _fmt_string_out="\"$_fmt_string_value\""
}
