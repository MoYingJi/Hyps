#!/hint/bash

[[ -n "${__UTILS_ARRAY_SH_LOADED:-}" ]] && return 0
__UTILS_ARRAY_SH_LOADED=1

# 本文件部分使用 LLM 生成

is_array() {
    local string="$1"
    # 去除字符串首尾空白
    string="${string#"${string%%[![:space:]]*}"}"
    string="${string%"${string##*[![:space:]]}"}"
    [[ "$string" == \[*\] || "$string" == \(*\) ]]
}

parse_array() {
    local string="$1"
    # 去除字符串首尾空白
    string="${string#"${string%%[![:space:]]*}"}"
    string="${string%"${string##*[![:space:]]}"}"
    case "$string" in
        \[*\]) _parse_flat_array "${string:1:-1}" "$2" comma ;;
        \(*\)) _parse_flat_array "${string:1:-1}" "$2" space ;;
        *) return 1 ;;
    esac
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

# 只解析一维字符串数组，不执行变量替换、命令替换或 shell 表达式
# 完整解析成功后才替换输出，允许方括号数组的末尾逗号
_parse_flat_array() {
    local _arr_text="$1" _arr_mode="$3"
    local -n _arr_out="$2"
    local -a _arr_result=()
    local _arr_elem="" _arr_quote="" _arr_state=start _arr_char _arr_trimmed
    local _arr_i
    for ((_arr_i = 0; _arr_i < ${#_arr_text}; _arr_i++)); do
        _arr_char="${_arr_text:_arr_i:1}"
        if [[ -n "$_arr_quote" ]]; then
            # ---------- 引号内部 ----------
            # 仅在双引号内支持反斜杠转义
            if [[ "$_arr_quote" == '"' && "$_arr_char" == \\ ]]; then
                ((_arr_i += 1))
                [[ "$_arr_i" -lt ${#_arr_text} ]] || return 1
                _arr_elem+="${_arr_text:_arr_i:1}"
            elif [[ "$_arr_char" == "$_arr_quote" ]]; then
                _arr_quote=""
                _arr_state=closed
            else
                _arr_elem+="$_arr_char"
            fi
            continue
        fi
        # ---------- 引号外部 ----------
        case "$_arr_char" in
            '"' | "'")
                [[ "$_arr_state" == start ]] || return 1
                _arr_quote="$_arr_char"
                _arr_state=quoted
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
    [[ -z "$_arr_quote" ]] || return 1
    # 处理最后一个元素
    if [[ "$_arr_state" != start ]]; then
        _arr_trimmed="$_arr_elem"
        [[ "$_arr_state" != plain ]] || _arr_trimmed="${_arr_elem%"${_arr_elem##*[![:space:]]}"}"
        _arr_result+=("$_arr_trimmed")
    fi
    _arr_out=("${_arr_result[@]}")
}
