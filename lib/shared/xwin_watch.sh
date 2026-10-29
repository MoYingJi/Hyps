#!/hint/bash

[[ -n "${__SHARED_XWIN_WATCH_SH_LOADED:-}" ]] && return 0
__SHARED_XWIN_WATCH_SH_LOADED=1

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

#shellcheck source=../config/environment.sh
source "$SCRIPT_DIR/config/environment.sh"

XWIN_WATCH_TOOL="$PROJECT_ROOT/tools/xwin-watch"
XWIN_WATCH_CMD=()

feat_xwin_watch_load_config() {
    if ! config_is_true features.xwin_watch.enabled; then
        XWIN_WATCH_SKIPPED=1
        [ "${#XWIN_WATCH_CALLBACKS_EXISTS[@]}" -gt 0 ] ||
        [ "${#XWIN_WATCH_CALLBACKS_CLOSED[@]}" -gt 0 ] ||
        [ "${#XWIN_WATCH_CALLBACKS_FAILED[@]}" -gt 0 ] &&
            die 1 xwin-watch "xwin-watch 功能未启用，但已注册回调"
        return 0
    fi

    config_has features.xwin_watch.window_name || die 1 xwin-watch "'features.xwin_watch.window_name' 未设置"

    local timeout

    config_default features.xwin_watch.timeout 0
    config_read features.xwin_watch.timeout timeout

    [[ "$timeout" =~ [^0-9] ]] && die 1 xwin-watch "'features.xwin_watch.timeout' 必须是整数"

    # 后端开关: x11/wayland 可独立开启关闭 (默认 auto，按 pkg-config 自动检测)
    local x11 wayland
    config_default features.xwin_watch.x11 auto
    config_default features.xwin_watch.wayland auto
    config_read features.xwin_watch.x11 x11
    config_read features.xwin_watch.wayland wayland
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
    local cfg
    config_read "features.xwin_watch.$backend" cfg auto
    if [[ "$cfg" == auto ]]; then
        toolspec_load "$XWIN_WATCH_TOOL"
        if toolspec_backend_available "$backend"; then
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

# 输出已启用的后端, 每行一个
feat_xwin_watch_enabled_backends() {
    toolspec_load "$XWIN_WATCH_TOOL"
    local backend
    for backend in "${TOOLSPEC_BACKENDS[@]}"; do
        isy "$(feat_xwin_watch_backend_enabled "$backend")" && echo "$backend"
    done
}

# 没有任何可用后端时逐个列出原因后退出
feat_xwin_watch_require_backend() {
    local -a backends=()
    mapfile -t backends < <(feat_xwin_watch_enabled_backends)
    [[ "${#backends[@]}" -gt 0 ]] && return 0

    toolspec_load "$XWIN_WATCH_TOOL"
    local backend cfg hint="请把 features.xwin_watch.<后端> 设为 true 后重试"
    local msg="xwin-watch 没有可用的后端:"
    for backend in "${TOOLSPEC_BACKENDS[@]}"; do
        config_read "features.xwin_watch.$backend" cfg auto
        if [[ "$cfg" == auto ]]; then
            msg+=$'\n'"  $backend: 配置为 auto, 未找到依赖 $(toolspec_backend_pkg "$backend")"
            hint="请安装上述依赖, 或把 features.xwin_watch.<后端> 设为 true 后重试"
        else
            msg+=$'\n'"  $backend: 已在配置中禁用 (features.xwin_watch.$backend=$cfg)"
        fi
    done
    die 1 xwin-watch "$msg"$'\n'"$hint"
}

feat_xwin_watch_all_source() {
    local output="$1"
    local -a backends=()
    mapfile -t backends < <(feat_xwin_watch_enabled_backends)

    toolspec_runtime_fingerprint "$XWIN_WATCH_TOOL" "${backends[@]}"
    command_exists kwin_wayland && feat_xwin_watch_kwin_permission_desktop "$output" || echo "kwin not found"
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

    feat_xwin_watch_require_backend
    local -a backends=()
    mapfile -t backends < <(feat_xwin_watch_enabled_backends)
    log_debug xwin-watch "启用后端: ${backends[*]}"

    if isy "$(feat_xwin_watch_backend_enabled wayland)" && command_exists kwin_wayland; then
        local desktop_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
        local desktop_file="$desktop_dir/hyps-xwin-watch.desktop"
        mkdir -p "$desktop_dir"
        feat_xwin_watch_kwin_permission_desktop "$output" > "$desktop_file"
        command_exists kbuildsycoca6 && kbuildsycoca6 >/dev/null 2>&1 || true
    fi

    toolspec_runtime_build "$XWIN_WATCH_TOOL" "$output" "${backends[@]}" || return 1
    ensure_executable "$output" "xwin-watch"
}


feat_xwin_watch_prepare() {
    local bin
    bin="$(cache_bin_path xwin-watch)"

    feat_xwin_watch_require_backend

    check_cache_and_compile "xwin-watch" \
        "$bin" \
        feat_xwin_watch_all_source \
        feat_xwin_watch_verify_output \
        feat_xwin_watch_compile

    local window_name xwin_timeout
    config_read features.xwin_watch.window_name window_name
    config_read features.xwin_watch.timeout xwin_timeout
    XWIN_WATCH_CMD+=("$bin")
    XWIN_WATCH_CMD+=("-w" "$window_name")
    XWIN_WATCH_CMD+=("-a" "$xwin_timeout")

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

    # 没有 closed 回调时无需常驻等待窗口关闭
    [ "${#XWIN_WATCH_CALLBACKS_CLOSED[@]}" -gt 0 ] && XWIN_WATCH_CMD+=("-c")

    log_info xwin-watch "启动 xwin-watch 监控窗口: $(quote_args "${XWIN_WATCH_CMD[@]}")"
    XWIN_WATCH_FIFO="$(mktemp -u "$TEMP_DIR/xwin-watch-XXXXXX.fifo")"
    mkfifo "$XWIN_WATCH_FIFO"

    "${XWIN_WATCH_CMD[@]}" > "$XWIN_WATCH_FIFO" &
    XWIN_WATCH_PID="$!"

    feat_xwin_watch_dispatch_loop < "$XWIN_WATCH_FIFO" &
    XWIN_WATCH_DISPATCH_PID="$!"

    register_hook cleanup feat_xwin_watch_cleanup
}

feat_xwin_watch_dispatch_loop() {
    local event fn
    while IFS= read -r event; do
        local -n callback_list="XWIN_WATCH_CALLBACKS_${event^^}"
        for fn in "${callback_list[@]}"; do
            "$fn"
        done
    done
}

feat_xwin_watch_cleanup() {
    if [ -n "$XWIN_WATCH_PID" ]; then
        if kill -0 "$XWIN_WATCH_PID" 2>/dev/null; then
            log_debug xwin-watch "终止 xwin-watch 进程 PID: $XWIN_WATCH_PID"
            kill "$XWIN_WATCH_PID"
        else
            log_debug xwin-watch "终止 xwin-watch 进程 PID: $XWIN_WATCH_PID 不存在"
        fi
        wait "$XWIN_WATCH_PID" 2>/dev/null
    fi
    [ -n "$XWIN_WATCH_DISPATCH_PID" ] && wait "$XWIN_WATCH_DISPATCH_PID" 2>/dev/null
    [ -n "$XWIN_WATCH_FIFO" ] && rm -f "$XWIN_WATCH_FIFO"
    true
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
