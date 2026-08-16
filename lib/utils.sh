#!/hint/bash

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

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

set_executable() {
    local file="$1"

    if [ ! -x "$file" ]; then
        chmod +x "$file"
    fi

    if [ ! -x "$file" ]; then
        echo "[Hyps] ERROR: $file 不可执行！请手动设置可执行权限！"
        exit 1
    fi
}

check_cached_compile() {
    local var_name="$1"
    local bin_default="$2"
    local src_default="$3"
    local sha256_file_default="$4"

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
        src_sha256="$(sha256sum "$src_file" | awk '{print $1}')"
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

    echo "[Hyps] 尝试创建链接: '$dst' -> '$src'"

    if [ ! -d "$src" ]; then
        if [ -e "$src" ]; then
            echo "[Hyps] WARN: 源目录 '$src' 不是目录，无法创建链接"
            return 1
        else
            mkdir -p "$src"
        fi
    fi

    if [ -L "$dst" ]; then
        if [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
            return 0
        else
            echo "[Hyps] WARN: '$dst' -> '$(readlink -f "$dst")' 已存在，指向错误的目标"
            echo "[Hyps] WARN: '$dst' -> '$src' 修复到期望的目标"
            ln -sfn "$src" "$dst" || echo "[Hyps] WARN: 无法修复 '$dst' 的链接"
            return 0
        fi
    fi

    if [ -d "$dst" ] && [ ! -L "$dst" ]; then
        if [ "$(ls -A "$dst")" ]; then
            shopt -s dotglob
            mv "$dst"/* "$src"/ || echo "[Hyps] WARN: 无法移动 '$dst' 中的内容到 '$src'"
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

    # 逻辑：反正你早晚都要杀，不如现在就杀了而不报错
    [ "$action" = "error" ] && isy "$EXE_KILL" && action="kill"

    local pid
    local current_prefix

    for pid in $(pgrep wineserver); do
        current_prefix="$(cat "/proc/$pid/environ" 2>/dev/null | tr '\0' '\n' | grep '^WINEPREFIX=' | cut -d= -f2)"
        [ "$current_prefix" -ef "$prefix" ] || [ "$current_prefix" -ef "$prefix/pfx" ] || continue

        case "$action" in
            kill)
                echo "[Hyps] 检测到 wineserver 正在运行，尝试杀死它 (PID: $pid)"
                echo "[Hyps]     原因: $why"
                WINEPREFIX="$prefix" "/proc/$pid/exe" --kill
                ;;
            error)
                echo "[Hyps] ERROR: 检测到 wineserver 正在运行 (PID: $pid)，请先关闭它再继续"
                echo "[Hyps]     原因: $why"
                exit 1
                ;;
            *)
                echo "[Hyps] ERROR: ensure_no_wineserver 未知的 action '$action'"
                exit 1
                ;;
        esac
    done
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
