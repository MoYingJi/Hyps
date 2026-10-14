#!/hint/bash

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

#shellcheck source=custom_batch.sh
source "${SCRIPT_DIR:-.}/features/custom_batch.sh"

feat_jade_patch_load_config() {
    config_is_true feature.jade_patch.enable || return 0

    config_require_realpath_file feature.jade_patch.exe

    NEEDS_CUSTOM_BATCH=1
    local jade_exe
    config_read feature.jade_patch.exe jade_exe
    WINE_SIDE_GAME_WRAPPER+=("$jade_exe")
    GAME_ARGS=(-- "${GAME_ARGS[@]}")
}

register_hook load_config feat_jade_patch_load_config
