#!/hint/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

config_declare features.reg_hostname.enabled bool --default false
config_declare features.reg_hostname.hostname string --default STEAMDECK --when features.reg_hostname.enabled

feat_mod_reg_hostname_load_config() {
    config_is_true features.reg_hostname.enabled || return 0

    local hostname
    config_read features.reg_hostname.hostname hostname

    launch_plan_before_snippet_append "\
reg add HKLM\\System\\CurrentControlSet\\Control\\ComputerName\\ActiveComputerName /v ComputerName /t REG_SZ /d \"$hostname\" /f
reg add HKLM\\System\\CurrentControlSet\\Control\\ComputerName\\ComputerName /v ComputerName /t REG_SZ /d \"$hostname\" /f"
}

register_hook load_config feat_mod_reg_hostname_load_config
