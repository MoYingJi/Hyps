#!/hint/bash

#shellcheck source=../lifecycle.sh
source "${SCRIPT_DIR:-.}/lifecycle.sh"
#shellcheck source=../config.sh
source "${SCRIPT_DIR:-.}/config.sh"
#shellcheck source=../utils.sh
source "${SCRIPT_DIR:-.}/utils.sh"
#shellcheck source=../log.sh
source "${SCRIPT_DIR:-.}/log.sh"

#shellcheck source=xwin_watch.sh
source "${SCRIPT_DIR:-.}/features/xwin_watch.sh"

feat_xwin_watch_kill_load_config() {
    isy "$(config_get features.xwin_watch_kill)" || return 0
    config_set features.xwin_watch.enabled true
    xwin_watch_on closed feat_xwin_watch_kill_on_closed
}

register_hook load_config feat_xwin_watch_kill_load_config 50 before:feat_xwin_watch_load_config

feat_xwin_watch_kill_on_closed() {
    if [ -n "$GAME_PID" ]; then
        log_info xwin-watch-kill "窗口关闭，尝试杀死游戏进程 PID: $GAME_PID"
        kill "$GAME_PID"
    else
        log_warn xwin-watch-kill "窗口关闭，但未找到游戏进程 PID"
    fi
}
