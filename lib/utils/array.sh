#!/hint/bash

[[ -n "${__UTILS_ARRAY_SH_LOADED:-}" ]] && return 0
__UTILS_ARRAY_SH_LOADED=1


is_array() {
    local string="$1"

    # 去除字符串首尾空白
    string="${string#"${string%%[![:space:]]*}"}"
    string="${string%"${string##*[![:space:]]}"}"

    [[ "$string" == \[*\] ]] || [[ "$string" == \(*\) ]] || return 1
}

parse_array() {
    local string="$1"
    #shellcheck disable=SC2178
    local -n reply_array="$2"

    # 去除字符串首尾空白
    string="${string#"${string%%[![:space:]]*}"}"
    string="${string%"${string##*[![:space:]]}"}"

    if [[ "$string" == \[*\] ]]; then
        parse_json_array "$string" "$2"
    elif [[ "$string" == \(*\) ]]; then
        parse_bash_array "$string" "$2"
    else
        return 1
    fi
}


parse_json_array() {
    local json="$1"
    #shellcheck disable=SC2178
    local -n reply_array="$2"

    # 去除字符串首尾空白
    json="${json#"${json%%[![:space:]]*}"}"
    json="${json%"${json##*[![:space:]]}"}"

    # 必须以 [ 开头，] 结尾
    [[ "$json" == \[*\] ]] || return 1

    local inner="${json:1:${#json}-2}"
    # 去除内部首尾空白
    inner="${inner#"${inner%%[![:space:]]*}"}"
    inner="${inner%"${inner##*[![:space:]]}"}"

    # 空数组
    [[ -z "$inner" ]] && return 0

    local elem=""
    local in_quote=""       # 当前引号类型：' " 或空
    local current_quoted=false   # 当前元素是否以引号开始（用于决定是否 trim）
    local current_has_content=false
    local char
    local -i i

    for ((i = 0; i < ${#inner}; i++)); do
        char="${inner:i:1}"

        if [[ -n "$in_quote" ]]; then
            # ---------- 引号内部 ----------
            # 仅在双引号内支持反斜杠转义
            if [[ "$in_quote" == "\"" && "$char" == "\\" ]]; then
                if (( i + 1 < ${#inner} )); then
                    i=$((i + 1))
                    elem+="${inner:i:1}"   # 转义字符，去掉反斜杠
                else
                    elem+="\\"             # 末尾孤立反斜杠，保留
                fi
                continue
            fi

            if [[ "$char" == "$in_quote" ]]; then
                in_quote=""               # 关闭引号
            else
                elem+="$char"
            fi
        else
            # ---------- 引号外部 ----------
            case "$char" in
                '"'|"'")
                    in_quote="$char"
                    current_quoted=true
                    current_has_content=true
                    ;;
                ',')
                    # 结束当前元素
                    if [[ "$current_has_content" == true ]]; then
                        if [[ "$current_quoted" == true ]]; then
                            # 引号元素：保留原始内容，不 trim
                            reply_array+=("$elem")
                        else
                            # 非引号元素：去除首尾空白
                            local trimmed="${elem#"${elem%%[![:space:]]*}"}"
                            trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
                            [[ -n "$trimmed" ]] && reply_array+=("$trimmed")
                        fi
                    fi
                    # 重置状态
                    elem=""
                    current_quoted=false
                    current_has_content=false
                    ;;
                [[:space:]])
                    if [[ "$current_quoted" == true ]]; then
                        # 引号元素关闭后的空白忽略
                        :
                    elif [[ -z "$elem" ]]; then
                        # 非引号元素开头的空白忽略
                        :
                    else
                        # 非引号元素内部的空白保留（后面会 trim）
                        elem+="$char"
                    fi
                    ;;
                *)
                    elem+="$char"
                    current_has_content=true
                    ;;
            esac
        fi
    done

    # 处理最后一个元素
    if [[ "$current_has_content" == true ]]; then
        if [[ "$current_quoted" == true ]]; then
            reply_array+=("$elem")
        else
            local trimmed="${elem#"${elem%%[![:space:]]*}"}"
            trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
            [[ -n "$trimmed" ]] && reply_array+=("$trimmed")
        fi
    fi

    return 0
}

parse_bash_array() {
    local bash_array="$1"
    #shellcheck disable=SC2178
    local -n reply_array="$2"

    # 去除字符串首尾空白
    bash_array="${bash_array#"${bash_array%%[![:space:]]*}"}"
    bash_array="${bash_array%"${bash_array##*[![:space:]]}"}"

    # 必须以 ( 开头，) 结尾
    [[ "$bash_array" == \(*\) ]] || return 1

    local inner="${bash_array:1:${#bash_array}-2}"
    # 去除内部首尾空白
    inner="${inner#"${inner%%[![:space:]]*}"}"
    inner="${inner%"${inner##*[![:space:]]}"}"

    # 空数组
    [[ -z "$inner" ]] && return 0

    local elem=""
    local in_quote=""       # 当前引号类型：' " 或空
    local current_quoted=false   # 当前元素是否以引号开始（用于决定是否 trim）
    local current_has_content=false
    local char
    local -i i

    for ((i = 0; i < ${#inner}; i++)); do
        char="${inner:i:1}"

        if [[ -n "$in_quote" ]]; then
            # ---------- 引号内部 ----------
            # 仅在双引号内支持反斜杠转义
            if [[ "$in_quote" == "\\" && "$char" == "\\" ]]; then
                if (( i + 1 < ${#inner} )); then
                    i=$((i + 1))
                    elem+="${inner:i:1}"   # 转义字符，去掉反斜杠
                else
                    elem+="\\"             # 末尾孤立反斜杠，保留
                fi
                continue
            fi

            if [[ "$char" == "$in_quote" ]]; then
                in_quote=""               # 关闭引号
            else
                elem+="$char"
            fi
        else
            # ---------- 引号外部 ----------
            case "$char" in
                '"'|"'")
                    in_quote="$char"
                    current_quoted=true
                    current_has_content=true
                    ;;
                [[:space:]])
                    # 空白字符作为元素分隔符
                    if [[ "$current_has_content" == true ]]; then
                        if [[ "$current_quoted" == true ]]; then
                            # 引号元素：保留原始内容，不 trim
                            reply_array+=("$elem")
                        else
                            # 非引号元素：去除首尾空白
                            local trimmed="${elem#"${elem%%[![:space:]]*}"}"
                            trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
                            [[ -n "$trimmed" ]] && reply_array+=("$trimmed")
                        fi
                        # 重置状态
                        elem=""
                        current_quoted=false
                        current_has_content=false
                    fi
                    ;;
                *)
                    elem+="$char"
                    current_has_content=true
                    ;;
            esac
        fi
    done

    # 处理最后一个元素
    if [[ "$current_has_content" == true ]]; then
        if [[ "$current_quoted" == true ]]; then
            reply_array+=("$elem")
        else
            local trimmed="${elem#"${elem%%[![:space:]]*}"}"
            trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
            [[ -n "$trimmed" ]] && reply_array+=("$trimmed")
        fi
    fi

    return 0
}
