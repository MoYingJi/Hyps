#!/hint/bash

[[ -n "${__FEATURES_XWIN_WATCH_SH_LOADED:-}" ]] && return 0
__FEATURES_XWIN_WATCH_SH_LOADED=1

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

#shellcheck source=../environment.sh
source "${SCRIPT_DIR:-.}/environment.sh"

XWIN_WATCH_TOOL="$PROJECT_ROOT/tools/xwin-watch"
XWIN_WATCH_CMD=()

feat_xwin_watch_load_config() {
    if ! isy "$(config_get features.xwin_watch.enabled)"; then
        XWIN_WATCH_SKIPPED=1
        [ "${#XWIN_WATCH_CALLBACKS_EXISTS[@]}" -gt 0 ] ||
        [ "${#XWIN_WATCH_CALLBACKS_CLOSED[@]}" -gt 0 ] ||
        [ "${#XWIN_WATCH_CALLBACKS_FAILED[@]}" -gt 0 ] &&
            die 1 xwin-watch "xwin-watch 功能未启用，但已注册回调"
        return 0
    fi

    config_has features.xwin_watch.window_name || die 1 xwin-watch "'features.xwin_watch.window_name' 未设置"

    local timeout

    config_default features.xwin_watch.timeout 0 >/dev/null
    timeout="$(config_get features.xwin_watch.timeout)"

    [[ "$timeout" =~ [^0-9] ]] && die 1 xwin-watch "'features.xwin_watch.timeout' 必须是整数"

    # 后端开关: x11/wayland 可独立开启关闭 (默认 auto，按 pkg-config 自动检测)
    local x11 wayland
    config_default features.xwin_watch.x11 auto >/dev/null
    config_default features.xwin_watch.wayland auto >/dev/null
    x11="$(config_get features.xwin_watch.x11)"
    wayland="$(config_get features.xwin_watch.wayland)"
    if [[ "$x11" != auto ]] && ! isy "$x11"; then
        die 1 xwin-watch "'features.xwin_watch.x11' 必须是 auto/true/false"
    fi
    if [[ "$wayland" != auto ]] && ! isy "$wayland"; then
        die 1 xwin-watch "'features.xwin_watch.wayland' 必须是 auto/true/false"
    fi

    register_hook pre_start feat_xwin_watch_prepare
}

register_hook load_config feat_xwin_watch_load_config

# KWin 只对声明了 org_kde_plasma_window_management 接口的客户端开放该协议。
# 权限通过 .desktop 文件授予：Exec 必须精确匹配客户端可执行文件的规范路径，
# 且声明 X-KDE-Wayland-Interfaces。这里按 XWIN_WATCH_BIN 的实际路径生成并安装。
feat_xwin_watch_kwin_permission_desktop() {
    local bin="$1"
    echo "[Desktop Entry]"
    echo "Type=Application"
    echo "Name=Hyps xwin-watch"
    echo "Exec=$bin"
    echo "X-KDE-Wayland-Interfaces=org_kde_plasma_window_management"
    echo "NoDisplay=true"
    echo "Terminal=false"
}

# 后端开关解析: 输出 x11/wayland 是否启用 (true/false)
feat_xwin_watch_backend_enabled() {
    local backend="$1"
    local module="$backend"
    [[ "$backend" == wayland ]] && module="wayland-client"
    local cfg
    cfg="$(config_get "features.xwin_watch.$backend" auto)"
    if [[ "$cfg" == auto ]]; then
        if pkg-config --exists "$module"; then
            echo true
        else
            echo false
        fi
    elif isy "$cfg"; then
        echo true
    else
        echo false
    fi
}

feat_xwin_watch_all_source() {
    local output="$1"
    local tool="$XWIN_WATCH_TOOL"
    cat "$tool/xwin-watch.c"
    cat "$tool/backends.h"
    echo -n "x11=" && feat_xwin_watch_backend_enabled x11
    echo -n "wayland=" && feat_xwin_watch_backend_enabled wayland
    if isy "$(feat_xwin_watch_backend_enabled x11)"; then
        cat "$tool/x11-backend.c"
    fi
    if isy "$(feat_xwin_watch_backend_enabled wayland)"; then
        cat "$tool/wayland.c"
        cat "$tool/wayland.h"
        cat "$tool/wlr-backend.c"
        cat "$tool/ext-backend.c"
        cat "$tool/plasma-backend.c"
        cat "$tool/generated/wlr-foreign-toplevel-management-unstable-v1.c"
        cat "$tool/generated/ext-foreign-toplevel-list-v1.c"
        cat "$tool/generated/plasma-window-management.c"
    fi
    command_exists kwin_wayland && feat_xwin_watch_kwin_permission_desktop "$output" || echo "kwin not found"
    #shellcheck disable=SC2153
    echo "${CFLAGS[@]:-}"
}
feat_xwin_watch_verify_output() {
    local output="$1"
    [ -f "$output" ] || return 1
    [ -x "$output" ] || return 1
    local desktop_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    local desktop_file="$desktop_dir/hyps-xwin-watch.desktop"
    if isy "$(feat_xwin_watch_backend_enabled wayland)" && command_exists kwin_wayland; then
        diff <(feat_xwin_watch_kwin_permission_desktop "$output") "$desktop_file" >/dev/null 2>&1 || return 1
    fi
}
feat_xwin_watch_compile() {
    local output="$1"
    local tool="$XWIN_WATCH_TOOL"

    local x11 wayland
    x11="$(feat_xwin_watch_backend_enabled x11)"
    wayland="$(feat_xwin_watch_backend_enabled wayland)"

    if isy "$x11"; then
        log_debug xwin-watch "启用 X11 后端"
    else
        log_debug xwin-watch "禁用 X11 后端"
    fi
    if isy "$wayland"; then
        log_debug xwin-watch "启用 Wayland 后端"
    else
        log_debug xwin-watch "禁用 Wayland 后端"
    fi

    local -a sources=()
    local -a cflags=()
    local -a libs=()

    cflags+=("${CFLAGS[@]:-}")

    sources+=("$tool/xwin-watch.c")
    cflags+=("-I$tool")

    if isy "$x11"; then
        sources+=("$tool/x11-backend.c")
        cflags+=("-DHAVE_X11")
        libs+=("-lX11")
    fi

    if isy "$wayland"; then
        sources+=("$tool/wayland.c")
        cflags+=("-DHAVE_WAYLAND")
        libs+=("-lwayland-client")

        # Wayland 扩展各自独立编译 (wlr / ext / plasma)
        sources+=("$tool/wlr-backend.c")
        cflags+=("-DHAVE_WLR")
        sources+=("$tool/generated/wlr-foreign-toplevel-management-unstable-v1.c")

        sources+=("$tool/ext-backend.c")
        cflags+=("-DHAVE_EXT")
        sources+=("$tool/generated/ext-foreign-toplevel-list-v1.c")

        sources+=("$tool/plasma-backend.c")
        cflags+=("-DHAVE_PLASMA")
        sources+=("$tool/generated/plasma-window-management.c")

        if command_exists kwin_wayland; then
            local desktop_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
            local desktop_file="$desktop_dir/hyps-xwin-watch.desktop"
            mkdir -p "$desktop_dir"
            feat_xwin_watch_kwin_permission_desktop "$output" > "$desktop_file"
            command_exists kbuildsycoca6 && kbuildsycoca6 >/dev/null 2>&1 || true
        fi
    fi

    run_and_log DEBUG xwin-watch "编译命令" \
        gcc "${sources[@]}" "${cflags[@]}" "${libs[@]}" -o "$output" \
        || return 1
    ensure_executable "$output" "xwin-watch"
}

feat_xwin_watch_prepare() {
    local bin="$XWIN_WATCH_TOOL/xwin-watch"

    check_cache_and_compile "xwin-watch" \
        "$bin" \
        feat_xwin_watch_all_source \
        feat_xwin_watch_verify_output \
        feat_xwin_watch_compile

    XWIN_WATCH_CMD+=("$bin")
    XWIN_WATCH_CMD+=("-w" "$(config_get features.xwin_watch.window_name)")
    XWIN_WATCH_CMD+=("-a" "$(config_get features.xwin_watch.timeout)")

    register_hook post_start feat_xwin_watch_post_start
}

feat_xwin_watch_post_start() {
    XWIN_WATCH_STARTED=1

    local callback_count=0
    callback_count=$((callback_count + ${#XWIN_WATCH_CALLBACKS_EXISTS[@]}))
    callback_count=$((callback_count + ${#XWIN_WATCH_CALLBACKS_CLOSED[@]}))
    callback_count=$((callback_count + ${#XWIN_WATCH_CALLBACKS_FAILED[@]}))
    if [ "$callback_count" -eq 0 ]; then
        log_debug xwin-watch "未注册任何回调，跳过启动 xwin-watch"
        return 0
    fi

    local declare_pack_file
    declare_pack_file="$(generate_declare_pack)"

    local on_exists_script=""
    local on_closed_script=""
    local on_failed_script=""

    on_exists_script="$(generate_callback_script exists "$declare_pack_file")"
    on_closed_script="$(generate_callback_script closed "$declare_pack_file")"
    on_failed_script="$(generate_callback_script failed "$declare_pack_file")"

    [[ -n "$on_exists_script" ]] && XWIN_WATCH_CMD+=("-e" "$on_exists_script")
    [[ -n "$on_closed_script" ]] && XWIN_WATCH_CMD+=("-c" "$on_closed_script")
    [[ -n "$on_failed_script" ]] && XWIN_WATCH_CMD+=("-f" "$on_failed_script")

    log_info xwin-watch "启动 xwin-watch 监控窗口: $(quote_args "${XWIN_WATCH_CMD[@]}")"
    "${XWIN_WATCH_CMD[@]}" &
    XWIN_WATCH_PID="$!"

    register_hook cleanup feat_xwin_watch_cleanup
}

feat_xwin_watch_cleanup() {
    if [ -n "$XWIN_WATCH_PID" ]; then
        if kill -0 "$XWIN_WATCH_PID" 2>/dev/null; then
            log_debug xwin-watch "终止 xwin-watch 进程 PID: $XWIN_WATCH_PID"
            kill "$XWIN_WATCH_PID"
            wait "$XWIN_WATCH_PID"
            true
        else
            log_debug xwin-watch "终止 xwin-watch 进程 PID: $XWIN_WATCH_PID 不存在"
        fi
    fi
}



declare -a XWIN_WATCH_CALLBACKS_EXISTS
declare -a XWIN_WATCH_CALLBACKS_CLOSED
declare -a XWIN_WATCH_CALLBACKS_FAILED

xwin_watch_on() {
    local event="$1" # exists | closed | failed
    local fn="$2"
    local -n callback_list="XWIN_WATCH_CALLBACKS_${event^^}"

    if isy "$XWIN_WATCH_SKIPPED"; then
        die 1 xwin-watch "无法注册回调 '$fn'，xwin-watch 功能未启用"
    fi

    if isy "$XWIN_WATCH_STARTED"; then
        die 1 xwin-watch "无法注册回调 '$fn'，xwin-watch 已经启动"
    fi

    if declare -F "$fn" >/dev/null; then
        callback_list+=("$fn")
        log_debug xwin-watch "注册回调 '$fn' 到事件 '$event'"
    else
        log_warn xwin-watch "注册回调 '$fn' 失败，函数不存在"
    fi
}

generate_declare_pack() {
    local script_file
    script_file="$(mktemp "$TEMP_DIR/xwin-watch-declare-pack-XXXXXX.sh")"
    {
        print_bash_script_header
        pack_declare
    } > "$script_file"
    echo "$script_file"
}

generate_callback_script() {
    local event="$1" # exists | closed | failed
    local declare_pack_file="$2"
    #shellcheck disable=SC2178
    local -n callback_list="XWIN_WATCH_CALLBACKS_${event^^}"
    [[ "${#callback_list[@]}" -eq 0 ]] && return 1

    local script_file
    script_file="$(mktemp "$TEMP_DIR/xwin-watch-$event-XXXXXX.sh")"

    {
        print_bash_script_header
        echo "source \"$declare_pack_file\""
        echo ""
        echo "# Execute callbacks"
        for fn in "${callback_list[@]}"; do
            echo "$fn"
        done
    } > "$script_file"

    chmod +x "$script_file"
    echo "$script_file"
}
