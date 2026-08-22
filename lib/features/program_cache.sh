#!/hint/bash

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

#shellcheck source=../environment.sh
source "${SCRIPT_DIR:-.}/environment.sh"

feat_program_cache_load_config() {
    # GLShaderCache
    if isy "$(config_get cache.shader.enabled)"; then
        config_default cache.shader.path "$CACHE_DIR/GLShaderCache/$GAME_NAME" >/dev/null

        ENV_EXPORTS+=(
            "cache.shader.enabled|__GL_SHADER_DISK_CACHE_SKIP_CLEANUP|bool_to_01"
            "cache.shader.path|__GL_SHADER_DISK_CACHE_PATH|path_mkdir"
        )
    fi

    # DXCache
    if isy "$(config_get cache.dx.enabled)"; then
        config_default cache.dx.path "$CACHE_DIR/DXCache/$GAME_NAME" >/dev/null

        ENV_EXPORTS+=(
            "cache.dx.path|DXVK_STATE_CACHE_PATH|path_mkdir"
            "cache.dx.path|VKD3D_SHADER_CACHE_PATH|path_mkdir"
        )
    fi
}

register_hook load_config feat_program_cache_load_config
