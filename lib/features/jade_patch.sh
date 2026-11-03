#!/hint/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

# 此方法已废弃

feat_jade_patch_load_config() {
    config_is_true feature.jade_patch.enable || return 0
    log_warn jade-patch "此方法已废弃，推荐寻找其它方法"
    config_require_realpath_file feature.jade_patch.exe
    launch_plan_register_game_handler jadeite jade_patch_handler
}

jade_patch_handler() {
    local -n _out="$1"

    local jade_exe
    config_read feature.jade_patch.exe jade_exe

    local launcher_exe="--"
    if config_has feature.jade_patch.launcher; then
        config_read feature.jade_patch.launcher launcher_exe
        launcher_exe="$(wine_unix_path_to_windows "$launcher_exe")"
    fi

    local game_exe
    config_read game.exe game_exe

    local -a game_args=()
    launch_plan_args_get game_args

    _out=("$jade_exe" "$(wine_unix_path_to_windows "$game_exe")" "$launcher_exe" "${game_args[@]}")
}

register_hook load_config feat_jade_patch_load_config
