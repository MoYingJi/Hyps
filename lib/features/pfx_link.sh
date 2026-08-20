#!/hint/bash

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

feat_pfx_link_prepare() {
    isy "$(config_get features.pfx_link)" || return 0

    local prefix
    prefix="$(config_get game.prefix)"

    if [ ! -d "$prefix" ]; then
        [ -e "$prefix" ] && die 1 pfx-link "游戏前缀路径 '$prefix' 已存在，但不是目录"
        set -e
        mkdir -p "$prefix"
        set +e
    fi

    if [ -L "$prefix/pfx" ]; then
        if [ "$(readlink -f "$prefix/pfx")" = "$(readlink -f "$prefix")" ]; then
            log_debug pfx-link "'$prefix/pfx' 已存在，指向正确的目标"
            return 0
        else
            die 1 pfx-link "'$prefix/pfx' 已存在，指向错误的目标"
        fi
    fi

    if [ -e "$prefix/pfx" ] && [ ! -d "$prefix/pfx" ]; then
        die 1 pfx-link "'$prefix/pfx' 已存在，但不是目录"
    fi

    if [ -d "$prefix/pfx" ]; then
        if [ -d "$prefix/dosdevices" ] && [ -d "$prefix/pfx/dosdevices" ]; then
            die 1 pfx-link "'$prefix' 和 '$prefix/pfx' 处都存在 Wine 前缀，无法创建链接"
        fi

        if [ -d "$prefix/pfx/dosdevices" ]; then
            log_warn pfx-link "'$prefix/pfx' 是一个 Wine 前缀，移动其内容到 '$prefix' 并创建链接"
            set -e
            shopt -s dotglob
            mv "$prefix/pfx/"* "$prefix/"
            shopt -u dotglob
            rmdir "$prefix/pfx"
            ln -s . "$prefix/pfx"
            set +e
            return 0
        fi

        log_warn pfx-link "'$prefix/pfx' 已存在，备份它到 '$prefix/pfx.bak' 并创建链接"
        set -e
        mv "$prefix/pfx" "$prefix/pfx.bak"
        ln -s . "$prefix/pfx"
        set +e
        return 0
    fi

    set -e
    ln -s . "$prefix/pfx"
    set +e
}

register_hook prepare feat_pfx_link_prepare
