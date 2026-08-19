#!/hint/bash

[[ -n "${__FEATURES_XWIN_WATCH_SH_LOADED:-}" ]] && return 0
__FEATURES_XWIN_WATCH_SH_LOADED=1

#shellcheck source=../lifecycle.sh
source "${SCRIPT_DIR:-.}/lifecycle.sh"
#shellcheck source=../config.sh
source "${SCRIPT_DIR:-.}/config.sh"
#shellcheck source=../utils.sh
source "${SCRIPT_DIR:-.}/utils.sh"
#shellcheck source=../log.sh
source "${SCRIPT_DIR:-.}/log.sh"

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

    if isy "$(config_get env.PROTON_ENABLE_WAYLAND)"; then
        log_error xwin-watch "检测到启用了原生 Wayland，xwin-watch 功能无法正常工作"
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
            # 有 wayland-client 时启用 Wayland 后端 (wlr-foreign-toplevel-management)
            log_debug xwin-watch "启用 Wayland 后端"
            gcc "$XWIN_WATCH_SRC" "$(dirname "$XWIN_WATCH_SRC")/wlr-foreign-toplevel-management-unstable-v1.c" \
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
        log_debug xwin-watch "终止 xwin-watch 进程 PID: $XWIN_WATCH_PID"

        if kill -0 "$XWIN_WATCH_PID" 2>/dev/null; then
            kill "$XWIN_WATCH_PID"
            wait "$XWIN_WATCH_PID"
            true
        else
            log_debug xwin-watch "xwin-watch 进程 PID: $XWIN_WATCH_PID 不存在，可能已退出"
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
