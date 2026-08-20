#!/hint/bash

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

#shellcheck source=custom_batch.sh
source "${SCRIPT_DIR:-.}/features/custom_batch.sh"

feat_jade_patch_load_config() {
    isy "$(config_get feature.jade_patch.enable)" || return 0

    config_require_realpath_file feature.jade_patch.exe

    NEEDS_CUSTOM_BATCH=1
    WINE_SIDE_GAME_WRAPPER+=("$(config_get feature.jade_patch.exe)")
    GAME_ARGS=(-- "${GAME_ARGS[@]}")
}

register_hook load_config feat_jade_patch_load_config
