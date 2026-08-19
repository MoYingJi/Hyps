#!/hint/bash

#shellcheck source=../lifecycle.sh
source "${SCRIPT_DIR:-.}/lifecycle.sh"
#shellcheck source=../config.sh
source "${SCRIPT_DIR:-.}/config.sh"
#shellcheck source=../utils.sh
source "${SCRIPT_DIR:-.}/utils.sh"
#shellcheck source=../log.sh
source "${SCRIPT_DIR:-.}/log.sh"


feat_userdata_link_prepare() {
    isy "$(config_get features.userdata_link.enabled)" || return 0

    if [ ! "$(type -t userdata_link)" = "function" ]; then
        log_debug userdata-link "未定义 userdata_link 函数，跳过 userdata_link 功能"
        return 0
    fi

    local prefix
    local drive_c
    local userprofile
    local game_exe

    prefix="$(config_get game.prefix)"

    if [ -d "$prefix/drive_c" ]; then
        drive_c="$prefix/drive_c"
    elif [ -d "$prefix/pfx/drive_c" ]; then
        drive_c="$prefix/pfx/drive_c"
    else
        die 1 userdata-link "未找到 prefix 中的 drive_c 目录"
    fi

    if [ -d "$drive_c/users/steamuser" ]; then
        userprofile="$drive_c/users/steamuser"
    elif [ -d "$drive_c/users/$USER" ]; then
        userprofile="$drive_c/users/$USER"
    else
        die 1 userdata-link "未找到 prefix 中的用户目录"
    fi

    game_exe="$(config_get game.exe)"
    if isy "$(config_get overlay.enabled)"; then
        # overlayfs 开启时游戏截图会被保存到 upper 中，这里直接编辑 upper
        game_exe="$(config_get overlay.upper)/$(realpath --relative-to="$(config_get overlay.lower)" "$OVERLAY_ORIGINAL_GAME")"
    fi

    local screenshots_dir
    screenshots_dir="$(config_require_realpath_mkdir features.userdata_link.screenshots "$(xdg-user-dir PICTURES)/HypsScreenshots")"

    USERDATA_LINK_SCREENSHOTS="$screenshots_dir" \
        userdata_link "$drive_c" "$userprofile" "$game_exe"
}

register_hook prepare feat_userdata_link_prepare
