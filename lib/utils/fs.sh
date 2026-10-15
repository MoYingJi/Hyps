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
