#!/hint/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

feat_userdata_link_prepare() {
    config_is_true features.userdata_link.enabled || return 0

    if [ ! "$(type -t userdata_link)" = "function" ]; then
        log_debug userdata-link "未定义 userdata_link 函数，跳过 userdata_link 功能"
        return 0
    fi

    if ! game_fs_resolve_user_dirs userdata-link; then
        log_error userdata-link "解析用户目录失败，跳过 userdata_link 功能"
        return 0
    fi

    local screenshots_dir
    config_require_realpath_mkdir features.userdata_link.screenshots "$(xdg-user-dir PICTURES)/HypsScreenshots"
    config_read features.userdata_link.screenshots screenshots_dir

    # 在 prepare 阶段执行，overlay 已挂载
    if ! SCREENSHOTS="$screenshots_dir" userdata_link; then
        log_warn userdata-link "userdata_link 执行失败，跳过"
    fi
}

register_hook prepare feat_userdata_link_prepare
