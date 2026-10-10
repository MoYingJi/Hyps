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

# 清除缓存目录中的内容，保留目录本身
# 用法: program_cache_clear_dir <config_key> <label>
program_cache_clear_dir() {
    local key="$1"
    local label="$2"
    local path

    if ! config_has "$key"; then
        log_warn program-cache "未指定 $label 缓存路径 ($key)，跳过清除"
        return 0
    fi

    path="$(config_get "$key")"
    if [ -z "$path" ] || [ "$path" = / ]; then
        log_warn program-cache "$label 缓存路径无效: '$path'，跳过清除"
        return 0
    fi

    if [ ! -d "$path" ]; then
        log_info program-cache "$label 缓存目录不存在，无需清除: $path"
        return 0
    fi

    log_info program-cache "清除 $label 缓存: $path"
    find "$path" -mindepth 1 -delete || log_warn program-cache "清除 $label 缓存失败: $path"
}

feat_program_cache_invalidate() {
    # 应用默认路径，与游戏启动时的行为保持一致
    feat_program_cache_load_config

    program_cache_clear_dir cache.shader.path GLShaderCache
    program_cache_clear_dir cache.dx.path DXCache
}
