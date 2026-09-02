#!/hint/bash

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

feat_kill_wineserver_load_config() {
    isy "$(config_get prepare.kill_wineserver)" || return 0

    register_hook pre_start feat_kill_wineserver_prepare

    eval "$(declare -f ensure_no_wineserver | sed '1s/ensure_no_wineserver/ensure_no_wineserver_orig/')"

    #shellcheck disable=SC2329
    ensure_no_wineserver() {
        local prefix="$1"
        local action="$2"
        local why="$3"

        # 反正你迟早都要杀，不如不报错，让它现在就杀掉
        if [[ "$action" == "error" ]]; then
            log_debug kill-wineserver "prepare.kill_wineserver 已启用，强制设置 ensure_no_wineserver 的 action '$action' -> 'kill'"
            action="kill"
        fi

        ensure_no_wineserver_orig "$prefix" "$action" "$why"
    }
}

register_hook load_config feat_kill_wineserver_load_config

feat_kill_wineserver_prepare() {
    isy "$(config_get prepare.kill_wineserver)" || return 0
    ensure_no_wineserver "$(config_get game.prefix)" kill "'prepare.kill_wineserver' 已启用"
}
