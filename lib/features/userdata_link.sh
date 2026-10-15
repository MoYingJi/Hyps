#!/hint/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

feat_userdata_link_prepare() {
    config_is_true features.userdata_link.enabled || return 0

    if [ ! "$(type -t userdata_link)" = "function" ]; then
        log_debug userdata-link "未定义 userdata_link 函数，跳过 userdata_link 功能"
        return 0
    fi

    local prefix
    local drive_c
    local userprofile
    local game_exe

    config_read game.prefix prefix

    wine_resolve_user_dirs userdata-link "$prefix" drive_c userprofile

    config_read game.exe game_exe
    if config_is_true overlay.enabled; then
        # overlayfs 开启时游戏截图会被保存到 upper 中，这里直接编辑 upper
        local overlay_upper overlay_lower
        config_read overlay.upper overlay_upper
        config_read overlay.lower overlay_lower
        game_exe="$overlay_upper/$(realpath --relative-to="$overlay_lower" "$OVERLAY_ORIGINAL_GAME")"
    fi

    local screenshots_dir
    config_require_realpath_mkdir features.userdata_link.screenshots "$(xdg-user-dir PICTURES)/HypsScreenshots"
    config_read features.userdata_link.screenshots screenshots_dir

    SCREENSHOTS="$screenshots_dir" \
        userdata_link "$drive_c" "$userprofile" "$game_exe"
}

register_hook prepare feat_userdata_link_prepare
