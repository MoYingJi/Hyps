#!/hint/bash

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

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

    wine_resolve_user_dirs userdata-link "$prefix" drive_c userprofile

    game_exe="$(config_get game.exe)"
    if isy "$(config_get overlay.enabled)"; then
        # overlayfs 开启时游戏截图会被保存到 upper 中，这里直接编辑 upper
        game_exe="$(config_get overlay.upper)/$(realpath --relative-to="$(config_get overlay.lower)" "$OVERLAY_ORIGINAL_GAME")"
    fi

    local screenshots_dir
    config_require_realpath_mkdir features.userdata_link.screenshots "$(xdg-user-dir PICTURES)/HypsScreenshots"
    screenshots_dir="$(config_get features.userdata_link.screenshots)"

    SCREENSHOTS="$screenshots_dir" \
        userdata_link "$drive_c" "$userprofile" "$game_exe"
}

register_hook prepare feat_userdata_link_prepare
