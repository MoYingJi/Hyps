#!/hint/bash

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

#shellcheck source=xwin_watch.sh
source "${SCRIPT_DIR:-.}/features/xwin_watch.sh"

feat_xwin_watch_kill_load_config() {
    isy "$(config_get features.xwin_watch_kill.enabled)" || return 0

    local count=0
    config_has features.xwin_watch_kill.name && count=$((count + 1))
    config_has features.xwin_watch_kill.pgrep_args && count=$((count + 1))
    [[ "$count" -eq 1 ]] || die 1 xwin-watch-kill "必须设置 features.xwin_watch_kill.name 或 features.xwin_watch_kill.pgrep_args 中的一个"

    config_set features.xwin_watch.enabled true
    xwin_watch_on closed feat_xwin_watch_kill_on_closed
}

register_hook load_config feat_xwin_watch_kill_load_config 50 before:feat_xwin_watch_load_config

feat_xwin_watch_kill_on_closed() {
    local pid
    local list
    list="$(feat_xwin_watch_kill_list_pid)"
    [[ -n "$list" ]] || log_info xwin-watch-kill "没有找到要杀死的进程"
    for pid in $list; do
        log_info xwin-watch-kill "正在杀死: $pid"
        kill "$pid" || log_warn xwin-watch-kill "无法杀死 PID: $pid"
    done
}

feat_xwin_watch_kill_list_pid() {
    if config_has features.xwin_watch_kill.name; then
        local name
        name="$(config_get features.xwin_watch_kill.name)"
        pgrep -u "$USER" -x "$name"
    else
        local args
        config_read_array features.xwin_watch_kill.pgrep_args args
        [[ "${#args[@]}" -gt 0 ]] || die 1 xwin-watch-kill "features.xwin_watch_kill.pgrep_args 未设置"
        pgrep "${args[@]}"
    fi
}
