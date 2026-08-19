#!/hint/bash

#shellcheck source=../lifecycle.sh
source "${SCRIPT_DIR:-.}/lifecycle.sh"
#shellcheck source=../config.sh
source "${SCRIPT_DIR:-.}/config.sh"
#shellcheck source=../utils.sh
source "${SCRIPT_DIR:-.}/utils.sh"
#shellcheck source=../log.sh
source "${SCRIPT_DIR:-.}/log.sh"

feat_kill_wineserver_prepare() {
    isy "$(config_get prepare.kill_wineserver)" || return 0
    ensure_no_wineserver "$(config_get game.prefix)" kill "'prepare.kill_wineserver' 已启用"
}

register_hook pre_start feat_kill_wineserver_prepare
