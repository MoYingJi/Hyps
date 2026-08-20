#!/hint/bash

[[ -n "${__FEATURES_XWIN_WATCH_SH_LOADED:-}" ]] && return 0
__FEATURES_XWIN_WATCH_SH_LOADED=1

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

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

    local sleep
    local interval
    local attempts

    config_default features.xwin_watch.sleep 5 >/dev/null
    sleep="$(config_get features.xwin_watch.sleep)"
    config_default features.xwin_watch.interval "$sleep" >/dev/null
    interval="$(config_get features.xwin_watch.interval)"
    config_default features.xwin_watch.attempts 20 >/dev/null
    attempts="$(config_get features.xwin_watch.attempts)"

    [[ "$sleep" =~ [^0-9] ]] && die 1 xwin-watch "'features.xwin_watch.sleep' 必须是整数"
    [[ "$interval" =~ [^0-9] ]] && die 1 xwin-watch "'features.xwin_watch.interval' 必须是整数"
    [[ "$attempts" =~ [^0-9] ]] && die 1 xwin-watch "'features.xwin_watch.attempts' 必须是整数"

    register_hook pre_start feat_xwin_watch_prepare
}

register_hook load_config feat_xwin_watch_load_config

# KWin 只对声明了 org_kde_plasma_window_management 接口的客户端开放该协议。
# 权限通过 .desktop 文件授予：Exec 必须精确匹配客户端可执行文件的规范路径，
# 且声明 X-KDE-Wayland-Interfaces。这里按 XWIN_WATCH_BIN 的实际路径生成并安装。
feat_xwin_watch_install_kwin_permission() {
    local desktop_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    local desktop_file="$desktop_dir/hyps-xwin-watch.desktop"

    if [ ! -d "$desktop_dir" ]; then
        mkdir -p "$desktop_dir"
    fi

    {
        echo "[Desktop Entry]"
        echo "Type=Application"
        echo "Name=Hyps xwin-watch"
        echo "Exec=$XWIN_WATCH_BIN"
        echo "X-KDE-Wayland-Interfaces=org_kde_plasma_window_management"
        echo "NoDisplay=true"
        echo "Terminal=false"
    } > "$desktop_file"

    # 更新 KDE 的应用缓存，否则 KWin 可能读取不到新生成的 .desktop 文件
    if command -v kbuildsycoca6 >/dev/null 2>&1; then
        kbuildsycoca6 >/dev/null 2>&1 || true
    fi

    log_debug xwin-watch "已安装 KWin 权限文件: $desktop_file (Exec=$XWIN_WATCH_BIN)"
}

feat_xwin_watch_prepare() {
    local tool="$PROJECT_ROOT/tools/xwin-watch"

    local additional_conditions
    local have_wayland

    have_wayland="$(pkg-config --exists wayland-client && echo true || echo false)"

    additional_conditions="$have_wayland"

    check_cached_compile "XWIN_WATCH" \
        "$tool/xwin-watch" \
        "$tool/xwin-watch.c" \
        "$CACHE_DIR/xwin-watch.c.sha256sum" \
        "$additional_conditions"

    #shellcheck disable=SC2153
    if [ -n "$XWIN_WATCH_BIN" ] && [ ! -f "$XWIN_WATCH_BIN" ] && [ -f "$XWIN_WATCH_SRC" ]; then
        log_info xwin-watch "编译 $XWIN_WATCH_SRC"
        if "$have_wayland"; then
            # 有 wayland-client 时启用 Wayland 后端
            # (wlr-foreign-toplevel-management + ext-foreign-toplevel-list + org_kde_plasma_window_management)
            log_debug xwin-watch "启用 Wayland 后端"
            gcc "$XWIN_WATCH_SRC" "$(dirname "$XWIN_WATCH_SRC")/wlr-foreign-toplevel-management-unstable-v1.c" \
                "$(dirname "$XWIN_WATCH_SRC")/ext-foreign-toplevel-list-v1.c" \
                "$(dirname "$XWIN_WATCH_SRC")/plasma-window-management.c" \
                -o "$XWIN_WATCH_BIN" -lX11 -lwayland-client \
                -I"$(dirname "$XWIN_WATCH_SRC")" -DHAVE_WAYLAND
        else
            log_debug xwin-watch "禁用 Wayland 后端"
            gcc "$XWIN_WATCH_SRC" -o "$XWIN_WATCH_BIN" -lX11
        fi
    fi

    if [ ! -f "$XWIN_WATCH_BIN" ]; then
        die 1 xwin-watch "编译失败或源文件不存在"
    else
        sha256sum "$XWIN_WATCH_SRC" | awk '{print $1}' > "$XWIN_WATCH_SHA256_FILE"
    fi

    ensure_executable "$XWIN_WATCH_BIN" "xwin-watch"

    if "$have_wayland"; then
        feat_xwin_watch_install_kwin_permission
    fi

    XWIN_WATCH_CMD+=("$XWIN_WATCH_BIN")
    XWIN_WATCH_CMD+=("-w" "$(config_get features.xwin_watch.window_name)")
    XWIN_WATCH_CMD+=("-s" "$(config_get features.xwin_watch.sleep)")
    XWIN_WATCH_CMD+=("-i" "$(config_get features.xwin_watch.interval)")
    XWIN_WATCH_CMD+=("-a" "$(config_get features.xwin_watch.attempts)")

    register_hook post_start feat_xwin_watch_post_start
}

feat_xwin_watch_post_start() {
    XWIN_WATCH_STARTED=1

    local on_exists_script=""
    local on_closed_script=""
    local on_failed_script=""

    on_exists_script="$(generate_callback_script exists)"
    on_closed_script="$(generate_callback_script closed)"
    on_failed_script="$(generate_callback_script failed)"

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



#shellcheck disable=SC2034
declare -a XWIN_WATCH_CALLBACKS_EXISTS
#shellcheck disable=SC2034
declare -a XWIN_WATCH_CALLBACKS_CLOSED
#shellcheck disable=SC2034
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

#shellcheck disable=SC2178
generate_callback_script() {
    local event="$1" # exists | closed | failed
    local -n callback_list="XWIN_WATCH_CALLBACKS_${event^^}"
    [[ "${#callback_list[@]}" -eq 0 ]] && return 1

    local script_file
    script_file="$(mktemp "$TEMP_DIR/xwin-watch-$event-XXXXXX.sh")"

    {
        echo "#!/usr/bin/env bash"
        echo "# Auto-generated by Hyps xwin-watch module"
        echo ""

        pack_declare

        # 按顺序调用
        echo "# Execute callbacks"
        for fn in "${callback_list[@]}"; do
            echo "$fn"
        done

    } > "$script_file"

    chmod +x "$script_file"
    echo "$script_file"
}
