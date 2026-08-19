#!/hint/bash

#shellcheck source=../lifecycle.sh
source "${SCRIPT_DIR:-.}/lifecycle.sh"
#shellcheck source=../config.sh
source "${SCRIPT_DIR:-.}/config.sh"
#shellcheck source=../utils.sh
source "${SCRIPT_DIR:-.}/utils.sh"
#shellcheck source=../log.sh
source "${SCRIPT_DIR:-.}/log.sh"

#shellcheck source=custom_batch.sh
source "${SCRIPT_DIR:-.}/features/custom_batch.sh"

feat_mod_reg_hostname_load_config() {
    isy "$(config_get feat.reg_hostname.enabled)" || return 0

    config_default feat.reg_hostname.hostname "STEAMDECK" >/dev/null
    local hostname
    hostname="$(config_get feat.reg_hostname.hostname)"

    CUSTOM_BATCH_BEFORE_GAME="$(cat << EOF
$CUSTOM_BATCH_BEFORE_GAME
reg add HKLM\\System\\CurrentControlSet\\Control\\ComputerName\\ActiveComputerName /v ComputerName /t REG_SZ /d "$hostname" /f
reg add HKLM\\System\\CurrentControlSet\\Control\\ComputerName\\ComputerName /v ComputerName /t REG_SZ /d "$hostname" /f
EOF
    )"
    NEEDS_CUSTOM_BATCH=1
}

register_hook load_config feat_mod_reg_hostname_load_config
