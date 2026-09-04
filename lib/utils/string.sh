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

bool_str() {
    "$@" && echo true || echo false
}

quote_args() {
    local arg
    for arg in "$@"; do
        # 匹配安全字符：字母数字下划线点斜杠横杠
        if [[ "$arg" =~ ^[a-zA-Z0-9_./-]+$ ]]; then
            printf '%s ' "$arg"
        else
            # 将参数中的单引号 ' 替换为 '\''（结束引号、转义单引号、重新开始引号）
            printf "'%s' " "${arg//\'/\'\\\'\'}"
        fi
    done
    echo # 最后换行
}
