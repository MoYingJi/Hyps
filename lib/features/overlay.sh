#!/hint/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

feat_overlay_load_config() {
    config_is_true overlay.enabled || return 0

    local backend
    config_read overlay.backend backend fuse
    case "$backend" in
        fuse)
            command_exists fuse-overlayfs \
                || die 1 overlay "'overlay.backend' 为 fuse，但系统中未安装 fuse-overlayfs"
            ;;
        kernel)
            command_exists mount \
                || die 1 overlay "'overlay.backend' 为 kernel，但系统中未安装 mount"
            ;;
        *)
            die 1 overlay "不支持的 overlay.backend：'$backend'（可选值：fuse、kernel）"
            ;;
    esac
    config_set overlay.backend "$backend"

    if ! config_has overlay.lower && config_has overlay.lower_auto; then
        if [ "$(type -t overlay_auto_lower)" = "function" ]; then
            local auto_lower game_exe
            config_read game.exe game_exe
            auto_lower="$(overlay_auto_lower "$game_exe")" \
                || die 1 overlay "overlay_auto_lower 函数执行失败"
            config_set overlay.lower "$auto_lower"
        else
            die 1 overlay "游戏没有定义 overlay_auto_lower 函数，无法自动选择 lower 目录"
        fi
    fi

    config_require_realpath_dir overlay.lower

    local overlay_dir
    config_realpath overlay.dir "$DATA_DIR/overlays"
    config_read overlay.dir overlay_dir
    overlay_dir="$overlay_dir/$GAME_NAME"

    if [ -n "$overlay_dir" ]; then
        config_realpath overlay.mount "$overlay_dir/mount"
        config_realpath overlay.upper "$overlay_dir/upper"
        config_realpath overlay.work "$overlay_dir/work"
    fi

    config_has overlay.mount || die 1 overlay "overlay.mount 未设置"
    config_has overlay.upper || die 1 overlay "overlay.upper 未设置"
    config_has overlay.work || die 1 overlay "overlay.work 未设置"

    local mount lower
    config_read overlay.mount mount
    config_read overlay.lower lower

    config_read game.exe OVERLAY_ORIGINAL_GAME
    config_set game.exe "$mount/$(realpath --relative-to="$lower" "$OVERLAY_ORIGINAL_GAME")"

    config_read game.cwd OVERLAY_ORIGINAL_GAME_CWD
    if [[ "$OVERLAY_ORIGINAL_GAME_CWD" == "$lower"* ]]; then
        config_set game.cwd "$mount/$(realpath --relative-to="$lower" "$OVERLAY_ORIGINAL_GAME_CWD")"
    fi

    register_hook prepare feat_overlay_mount
}

register_hook load_config feat_overlay_load_config

feat_overlay_mount() {
    local mount upper work
    config_read overlay.mount mount
    config_read overlay.upper upper
    config_read overlay.work work
    mkdir -p "$mount" "$upper" "$work"
    config_require_realpath_mkdir overlay.mount
    config_require_realpath_mkdir overlay.upper
    config_require_realpath_mkdir overlay.work
    config_read overlay.mount mount
    config_read overlay.upper upper
    config_read overlay.work work

    local lower backend
    config_read overlay.lower lower
    config_read overlay.backend backend

    local cmd=()
    local options=()

    options+=(
        "lowerdir=$lower"
        "upperdir=$upper"
        "workdir=$work"
    )

    case "$backend" in
        fuse)
            cmd+=(
                "fuse-overlayfs"
                "-o"
                "$(IFS=,; echo "${options[*]}")"
                "$mount"
            )
            ;;
        kernel)
            options+=("userxattr")
            cmd+=(
                "mount"
                "-t"
                "overlay"
                "overlay"
                "-o"
                "$(IFS=,; echo "${options[*]}")"
                "$mount"
            )
            ;;
    esac

    log_debug overlay "挂载 overlayfs: $(quote_args "${cmd[@]}")"
    "${cmd[@]}" || die 1 overlay "挂载 overlayfs 失败"

    register_hook cleanup feat_overlay_umount
}

feat_overlay_umount() {
    local mount backend
    config_read overlay.mount mount
    config_read overlay.backend backend

    case "$backend" in
        fuse)
            if command_exists fusermount3; then
                fusermount3 -uz "$mount" || log_error overlay "卸载 overlayfs 失败：$mount"
            elif command_exists fusermount; then
                fusermount -uz "$mount" || log_error overlay "卸载 overlayfs 失败：$mount"
            elif command_exists umount; then
                umount -l "$mount" || log_error overlay "卸载 overlayfs 失败：$mount"
            else
                log_error overlay "无法卸载 overlayfs，请手动卸载 $mount"
                return 1
            fi
            ;;
        kernel)
            if command_exists umount; then
                umount -l "$mount" || log_error overlay "卸载 overlayfs 失败：$mount"
            else
                log_error overlay "无法卸载 overlayfs，请手动卸载 $mount"
                return 1
            fi
            ;;
    esac
}
