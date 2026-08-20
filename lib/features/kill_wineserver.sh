#!/hint/bash

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

feat_kill_wineserver_prepare() {
    isy "$(config_get prepare.kill_wineserver)" || return 0
    ensure_no_wineserver "$(config_get game.prefix)" kill "'prepare.kill_wineserver' 已启用"
}

register_hook pre_start feat_kill_wineserver_prepare
