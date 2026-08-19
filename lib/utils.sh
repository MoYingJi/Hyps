#!/hint/bash

[[ -n "${__UTILS_SH_LOADED:-}" ]] && return 0
__UTILS_SH_LOADED=1

#shellcheck source=log.sh
source "${SCRIPT_DIR:-.}/log.sh"

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

parse_json_array() {
    local json="$1"
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

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

ensure_executable() {
    local file="$1"
    local module="${2:-utils}"

    if [ ! -x "$file" ]; then
        chmod +x "$file"
    fi

    if [ ! -x "$file" ]; then
        die 1 "$module" "文件 '$file' 不可执行！请手动设置可执行权限！"
    fi
}

check_cached_compile() {
    local var_name="$1"
    local bin_default="$2"
    local src_default="$3"
    local sha256_file_default="$4"
    local additional_conditions="${5:-}"

    local var_name_bin="$var_name"_BIN
    local var_name_src="$var_name"_SRC
    local var_name_sha256_file="$var_name"_SHA256_FILE

    local bin_file="${!var_name_bin:=$bin_default}"
    local src_file="${!var_name_src:=$src_default}"
    local sha256_file="${!var_name_sha256_file:=$sha256_file_default}"

    bin_file="$(realpath "$bin_file")"
    src_file="$(realpath "$src_file")"
    sha256_file="$(realpath "$sha256_file")"

    declare -g "$var_name_bin=$bin_file"
    declare -g "$var_name_src=$src_file"
    declare -g "$var_name_sha256_file=$sha256_file"

    # 判断是否需要重新编译
    if [ -f "$bin_file" ] && [ -f "$src_file" ] && [ -f "$sha256_file" ]; then
        # 读取先前的 sha256
        local cached_sha256
        cached_sha256="$(cat "$sha256_file")"
        # 计算源文件的 sha256
        local src_sha256
        src_sha256="$(cat "$src_file" <(echo -n "$additional_conditions") | sha256sum | awk '{print $1}')"
        # 如果不一致，则删除二进制，重新编译
        if [ "$cached_sha256" != "$src_sha256" ]; then
            rm -f "$bin_file"
        fi
    fi

    if [ -f "$bin_file" ] && [ -f "$src_file" ] && [ ! -f "$sha256_file" ]; then
        rm -f "$bin_file"
    fi
}

try_link_dir() {
    local src="$1"
    local dst="$2"

    log_info "尝试创建链接: '$dst' -> '$src'"

    if [ ! -d "$src" ]; then
        if [ -e "$src" ]; then
            log_warn "源目录 '$src' 不是目录，无法创建链接"
            return 1
        else
            mkdir -p "$src"
        fi
    fi

    if [ -L "$dst" ]; then
        if [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
            return 0
        else
            log_warn "'$dst' -> '$(readlink -f "$dst")' 已存在，指向错误的目标"
            log_warn "'$dst' -> '$src' 修复到期望的目标"
            ln -sfn "$src" "$dst" || log_warn "无法修复 '$dst' 的链接"
            return 0
        fi
    fi

    if [ -d "$dst" ] && [ ! -L "$dst" ]; then
        if [ "$(ls -A "$dst")" ]; then
            shopt -s dotglob
            mv "$dst"/* "$src"/ || log_warn "无法移动 '$dst' 中的内容到 '$src'"
            shopt -u dotglob
        fi

        rmdir "$dst"
    fi

    mkdir -p "$(dirname "$dst")"
    ln -sn "$src" "$dst"
}

ensure_no_wineserver() {
    local prefix="$1"
    local action="$2" # kill | error
    local why="$3"

    local pid
    local current_prefix

    for pid in $(pgrep wineserver); do
        current_prefix="$(cat "/proc/$pid/environ" 2>/dev/null | tr '\0' '\n' | grep '^WINEPREFIX=' | cut -d= -f2)"
        [[ "$current_prefix" -ef "$prefix" ]] || [[ "$current_prefix" -ef "$prefix/pfx" ]] || continue

        case "$action" in
            kill)
                log_info utils "检测到 wineserver 正在运行，尝试杀死它 (PID: $pid)"
                log_info utils "    原因: $why"
                log_debug utils "    WINEPREFIX: $current_prefix"
                log_debug utils "    wineserver: $(readlink -f "/proc/$pid/exe")"
                WINEPREFIX="$prefix" "/proc/$pid/exe" --kill
                ;;
            error)
                log_error utils "检测到 wineserver 正在运行 (PID: $pid)，请先关闭它再继续"
                log_error utils "    原因: $why"
                die 1
                ;;
            *)
                log_error utils "ensure_no_wineserver 未知的 action '$action'"
                die
                ;;
        esac
    done
}

sudo_request() {
    local why="$1"
    shift

    echo "[Hyps] [sudo 请求] $why"
    echo -n "[Hyps] $ "
    quote_args "$@"
    sudo "$@"
}

find_wineprefix() {
    local prefix="$1"

    if [ -f "$prefix/user.reg" ] && [ -d "$prefix/drive_c" ]; then
        echo "$prefix"
    elif [ -f "$prefix/pfx/user.reg" ] && [ -d "$prefix/pfx/drive_c" ]; then
        echo "$prefix/pfx"
    else
        echo "$prefix"
    fi
}
