#!/hint/bash

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

#shellcheck source=xwin_watch.sh
source "${SCRIPT_DIR:-.}/features/xwin_watch.sh"

feat_window_time_indicator_load_config() {
    isy "$(config_get features.window_time_indicator.enabled)" || return 0
    config_set features.xwin_watch.enabled true
    xwin_watch_on exists feat_window_time_indicator_on_exists
}

register_hook load_config feat_window_time_indicator_load_config 50 before:feat_xwin_watch_load_config

feat_window_time_indicator_on_exists() {
    [ -z "$SCRIPT_START_NANOSECONDS" ] && log_error window-time-indicator "SCRIPT_START_NANOSECONDS 未设置"

    local now_ns dur_ns
    now_ns="$(date +%s%N)"
    dur_ns="$((now_ns - SCRIPT_START_NANOSECONDS))"
    log_info window-time-indicator "从脚本启动到游戏窗口出现用了: $(printf "%'d" "$dur_ns") 纳秒"
}
