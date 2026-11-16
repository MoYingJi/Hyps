#!/hint/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

feat_userdata_link_prepare() {
    config_is_true features.userdata_link.enabled || return 0

    if [ ! "$(type -t game_paths)" = "function" ]; then
        log_debug userdata-link "未定义 game_paths，跳过 userdata_link 功能"
        return 0
    fi

    if ! game_fs_resolve_user_dirs userdata-link; then
        log_error userdata-link "解析用户目录失败，跳过 userdata_link 功能"
        return 0
    fi

    local screenshots_dir
    config_require_realpath_mkdir features.userdata_link.screenshots "$(xdg-user-dir PICTURES)/HypsScreenshots"
    config_read features.userdata_link.screenshots screenshots_dir

    local rc
    path_plan_collect userdata:screenshot
    rc=$?
    case "$rc" in
        0) ;;
        3)
            log_debug userdata-link "游戏未声明截图目录"
            return 0
            ;;
        4)
            log_debug userdata-link "游戏未实现路径声明"
            return 0
            ;;
        *)
            log_warn userdata-link "加载截图目录声明失败，跳过"
            return 0
            ;;
    esac

    local plan
    plan="$(path_plan_paths userdata:screenshot)" || {
        log_warn userdata-link "解析截图目录失败，跳过"
        return 0
    }

    local kind scope path label
    local failures=0
    while IFS=$'\t' read -r kind scope path label; do
        [ "$kind" = "link" ] || continue
        if ! game_fs_assert_mutation "$scope"; then
            failures=$((failures + 1))
            continue
        fi
        if ! SCREENSHOTS="$screenshots_dir" try_link_dir "$screenshots_dir/$label" "$path"; then
            log_warn userdata-link "创建截图链接失败: '$path' -> '$screenshots_dir/$label'"
            failures=$((failures + 1))
        fi
    done <<<"$plan"

    [ "$failures" -eq 0 ] || log_warn userdata-link "部分截图链接失败"
}

register_hook prepare feat_userdata_link_prepare
