#!/hint/bash

[[ -n "${__UTILS_FS_SH_LOADED:-}" ]] && return 0
__UTILS_FS_SH_LOADED=1

#shellcheck source=../core/log.sh
source "$SCRIPT_DIR/core/log.sh"

path_dirname() {
    local path="$1"
    local -n output="$2"

    while [[ "$path" == */ && "$path" != "/" ]]; do
        path="${path%/}"
    done

    local dir="${path%/*}"
    [[ "$dir" == "$path" ]] && dir="."
    [[ -z "$dir" ]] && dir="/"
    while [[ "$dir" == */ && "$dir" != "/" ]]; do
        dir="${dir%/}"
    done
    #shellcheck disable=SC2034 # Writes through the nameref to the caller's variable.
    output="$dir"
}

# 临时文件后缀；上次运行被打断时可能遗留 "$dst$FILE_ATOMIC_TMP_SUFFIX"
FILE_ATOMIC_TMP_SUFFIX=".hyps-tmp"

# 先复制到同目录的临时文件，再 mv 覆盖，替换是原子的；失败时不留下半个文件
file_replace_atomic() {
    local src="$1"
    local dst="$2"
    local tmp="$dst$FILE_ATOMIC_TMP_SUFFIX"

    if [ -e "$tmp" ]; then
        log_warn "发现上次遗留的临时文件，已删除: '$tmp'"
        rm -f "$tmp" || return 1
    fi

    if ! cp "$src" "$tmp" || ! mv -f "$tmp" "$dst"; then
        rm -f "$tmp"
        return 1
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

    local dst_dir
    path_dirname "$dst" dst_dir
    mkdir -p "$dst_dir"
    ln -sn "$src" "$dst"
}
