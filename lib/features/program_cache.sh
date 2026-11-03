#!/hint/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

#shellcheck source=../config/environment.sh
source "$SCRIPT_DIR/config/environment.sh"

feat_program_cache_load_config() {
    if config_is_true cache.shader.enabled; then
        config_default cache.shader.path "$CACHE_DIR/shader/$GAME_NAME"

        config_default cache.shader.nv_enabled true
        config_default cache.shader.nv_skip_cleanup true
        config_default cache.shader.nv_max_size "10G"
        config_default cache.shader.mesa_max_size "10G"

        local shader_path
        config_read cache.shader.path shader_path

        for subdir in nvidia mesa dxvk vkd3d; do
            defer_mkdir "$shader_path/$subdir"
        done

        export __GL_SHADER_DISK_CACHE_PATH="$shader_path/nvidia"
        export MESA_SHADER_CACHE_DIR="$shader_path/mesa"
        export DXVK_STATE_CACHE_PATH="$shader_path/dxvk"
        export VKD3D_SHADER_CACHE_PATH="$shader_path/vkd3d"

        ENV_EXPORTS+=(
            "cache.shader.nv_enabled|__GL_SHADER_DISK_CACHE|bool_to_01"
            "cache.shader.nv_skip_cleanup|__GL_SHADER_DISK_CACHE_SKIP_CLEANUP|bool_to_01"
            "cache.shader.nv_max_size|__GL_SHADER_DISK_CACHE_SIZE|size_string_to_bytes_uint"
            "cache.shader.mesa_max_size|MESA_SHADER_CACHE_MAX_SIZE|string"
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

    config_read "$key" path
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

    program_cache_clear_dir cache.shader.path "着色器"
}
