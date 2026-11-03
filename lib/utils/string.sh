#!/hint/bash

[[ -n "${__UTILS_STRING_SH_LOADED:-}" ]] && return 0
__UTILS_STRING_SH_LOADED=1

isy() {
    [ -z "$1" ] && return 1

    if [ "$1" = "y" ] ||
       [ "$1" = "Y" ] ||
       [ "$1" = "yes" ] ||
       [ "$1" = "Yes" ] ||
       [ "$1" = "YES" ] ||
       [ "$1" = "t" ] ||
       [ "$1" = "T" ] ||
       [ "$1" = "true" ] ||
       [ "$1" = "True" ] ||
       [ "$1" = "TRUE" ] ||
       [ "$1" = "1" ]
    then
        return 0
    else
        return 1
    fi
}

isn() {
    [ -z "$1" ] && return 1

    if [ "$1" = "n" ] ||
       [ "$1" = "N" ] ||
       [ "$1" = "no" ] ||
       [ "$1" = "No" ] ||
       [ "$1" = "NO" ] ||
       [ "$1" = "f" ] ||
       [ "$1" = "F" ] ||
       [ "$1" = "false" ] ||
       [ "$1" = "False" ] ||
       [ "$1" = "FALSE" ] ||
       [ "$1" = "0" ]
    then
        return 0
    else
        return 1
    fi
}

bool_str() {
    "$@" && echo true || echo false
}

quote_args() {
    local arg
    for arg in "$@"; do
        # 匹配安全字符：字母数字下划线点斜杠等号横杠
        if [[ "$arg" =~ ^[a-zA-Z0-9_./=-]+$ ]]; then
            printf '%s ' "$arg"
        else
            # 将参数中的单引号 ' 替换为 '\''（结束引号、转义单引号、重新开始引号）
            printf "'%s' " "${arg//\'/\'\\\'\'}"
        fi
    done
    echo # 最后换行
}

# 用于生成 Windows cmd 批处理命令行：cmd.exe 不识别单引号，并需转义百分号和结尾反斜杠
quote_args_bat() {
    local arg escaped_arg trailing_slashes
    for arg in "$@"; do
        escaped_arg="${arg//%/%%}"
        trailing_slashes=""
        while [[ "$escaped_arg" == *\\ ]]; do
            escaped_arg="${escaped_arg%\\}"
            trailing_slashes+="\\"
        done
        printf '"%s%s%s" ' "$escaped_arg" "$trailing_slashes" "$trailing_slashes"
    done
    echo
}

size_string_to_bytes_uint() {
    local input="${1//[[:space:]]/}"
    local num unit

    if [[ $input =~ ^([0-9]*\.?[0-9]+)([a-zA-Z]*)$ ]]; then
        num="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[2]}"
    else
        return 1
    fi

    local multiplier
    case "${unit,,}" in
        "" | b)          multiplier=1 ;;
        k | kb | kib)    multiplier=$(( 1 << 10 )) ;;
        m | mb | mib)    multiplier=$(( 1 << 20 )) ;;
        g | gb | gib)    multiplier=$(( 1 << 30 )) ;;
        t | tb | tib)    multiplier=$(( 1 << 40 )) ;;
        p | pb | pib)    multiplier=$(( 1 << 50 )) ;;
        e | eb | eib)    multiplier=$(( 1 << 60 )) ;;
        *) return 1 ;;
    esac

    local int_part frac_part=""
    if [[ $num == *.* ]]; then
        int_part="${num%.*}"
        frac_part="${num#*.}"
    else
        int_part="$num"
    fi
    int_part="${int_part:-0}"

    local result=$(( 10#$int_part * multiplier ))

    if [[ -n $frac_part ]]; then
        local flen=${#frac_part}
        local fnum=$(( 10#$frac_part ))
        local denom=$(( 10 ** flen ))
        result=$(( result + fnum * multiplier / denom ))
    fi

    echo "$result"
}
