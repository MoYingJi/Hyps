#!/hint/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

feat_mod_reg_hostname_load_config() {
    config_is_true feat.reg_hostname.enabled || return 0

    config_default feat.reg_hostname.hostname "STEAMDECK"
    local hostname
    config_read feat.reg_hostname.hostname hostname

    launch_plan_before_snippet_append "\
reg add HKLM\\System\\CurrentControlSet\\Control\\ComputerName\\ActiveComputerName /v ComputerName /t REG_SZ /d \"$hostname\" /f
reg add HKLM\\System\\CurrentControlSet\\Control\\ComputerName\\ComputerName /v ComputerName /t REG_SZ /d \"$hostname\" /f"
}

register_hook load_config feat_mod_reg_hostname_load_config
