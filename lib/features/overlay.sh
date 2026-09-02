#!/hint/bash

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

feat_overlay_load_config() {
    isy "$(config_get overlay.enabled)" || return 0

    command_exists fuse-overlayfs || die 1 overlay "'overlay.enabled' 为 true，但系统中未安装 fuse-overlayfs"

    if ! config_has overlay.lower && config_has overlay.lower_auto; then
        if [ "$(type -t overlay_auto_lower)" = "function" ]; then
            config_set overlay.lower "$(overlay_auto_lower "$(config_get game.exe)")"
        else
            die 1 overlay "游戏没有定义 overlay_auto_lower 函数，无法自动选择 lower 目录"
        fi
    fi

    config_require_realpath_dir overlay.lower

    local overlay_dir
    config_realpath overlay.dir "$DATA_DIR/overlays"
    overlay_dir="$(config_get overlay.dir)/$GAME_NAME"

    if [ -n "$overlay_dir" ]; then
        config_realpath overlay.mount "$overlay_dir/mount"
        config_realpath overlay.upper "$overlay_dir/upper"
        config_realpath overlay.work "$overlay_dir/work"
    fi

    config_has overlay.mount || die 1 overlay "overlay.mount 未设置"
    config_has overlay.upper || die 1 overlay "overlay.upper 未设置"
    config_has overlay.work || die 1 overlay "overlay.work 未设置"

    local mount lower
    mount="$(config_get overlay.mount)"
    lower="$(config_get overlay.lower)"

    OVERLAY_ORIGINAL_GAME="$(config_get game.exe)"
    config_set game.exe "$mount/$(realpath --relative-to="$lower" "$OVERLAY_ORIGINAL_GAME")"

    OVERLAY_ORIGINAL_GAME_CWD="$(config_get game.cwd)"
    if [[ "$OVERLAY_ORIGINAL_GAME_CWD" == "$lower"* ]]; then
        config_set game.cwd "$mount/$(realpath --relative-to="$lower" "$OVERLAY_ORIGINAL_GAME_CWD")"
    fi

    register_hook prepare feat_overlay_mount
}

register_hook load_config feat_overlay_load_config

feat_overlay_mount() {
    mkdir -p "$(config_get overlay.mount)" "$(config_get overlay.upper)" "$(config_get overlay.work)"
    config_require_realpath_mkdir overlay.mount
    config_require_realpath_mkdir overlay.upper
    config_require_realpath_mkdir overlay.work

    local cmd=()
    local options=()

    options+=(
        "lowerdir=$(config_get overlay.lower)"
        "upperdir=$(config_get overlay.upper)"
        "workdir=$(config_get overlay.work)"
    )

    cmd+=(
        "fuse-overlayfs"
        "-o"
        "$(IFS=,; echo "${options[*]}")"
        "$(config_get overlay.mount)"
    )

    log_debug overlay "挂载 overlayfs: $(quote_args "${cmd[@]}")"
    "${cmd[@]}" || die 1 overlay "挂载 overlayfs 失败"

    register_hook cleanup feat_overlay_umount
}

feat_overlay_umount() {
    if command_exists fusermount3; then
        fusermount3 -uz "$(config_get overlay.mount)"
    elif command_exists fusermount; then
        fusermount -uz "$(config_get overlay.mount)"
    elif command_exists umount; then
        umount -l "$(config_get overlay.mount)"
    else
        log_error overlay "无法卸载 overlayfs，请手动卸载 $(config_get overlay.mount)"
    fi
}
