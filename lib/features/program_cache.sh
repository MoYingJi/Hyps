#!/hint/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

#shellcheck source=../config/environment.sh
source "$SCRIPT_DIR/config/environment.sh"
#shellcheck source=../environment.sh
source "$SCRIPT_DIR/environment.sh"

config_declare cache.shader.enabled bool --default false --description "重定向图形组件的着色器缓存"
config_declare cache.shader.path path --default '"${path.cache}/shader/${game.name}"' --when cache.shader.enabled \
    --description "着色器缓存根目录"
config_declare cache.shader.nv_enabled bool --default true --when cache.shader.enabled
config_declare cache.shader.nv_skip_cleanup bool --default true --when cache.shader.enabled
config_declare cache.shader.nv_max_size size --default 10G --when cache.shader.enabled
config_declare cache.shader.mesa_max_size size --default 10G --when cache.shader.enabled

env_encode_shader_nvidia() { env_encode_string "$1/nvidia" "$2"; }
env_encode_shader_mesa() { env_encode_string "$1/mesa" "$2"; }
env_encode_shader_dxvk() { env_encode_string "$1/dxvk" "$2"; }
env_encode_shader_vkd3d() { env_encode_string "$1/vkd3d" "$2"; }

# 缓存重定向开启时由功能接管路径，保持与目录准备和清理一致
env_bind cache.shader.path __GL_SHADER_DISK_CACHE_PATH --encode shader_nvidia --policy replace
env_bind cache.shader.path MESA_SHADER_CACHE_DIR --encode shader_mesa --policy replace
env_bind cache.shader.path DXVK_STATE_CACHE_PATH --encode shader_dxvk --policy replace
env_bind cache.shader.path VKD3D_SHADER_CACHE_PATH --encode shader_vkd3d --policy replace
env_bind cache.shader.nv_enabled __GL_SHADER_DISK_CACHE --encode bool01
env_bind cache.shader.nv_skip_cleanup __GL_SHADER_DISK_CACHE_SKIP_CLEANUP --encode bool01
env_bind cache.shader.nv_max_size __GL_SHADER_DISK_CACHE_SIZE --encode bytes
env_bind cache.shader.mesa_max_size MESA_SHADER_CACHE_MAX_SIZE

feat_program_cache_load_config() {
    if config_is_true cache.shader.enabled; then
        config_validate cache.shader

        local shader_path
        config_read cache.shader.path shader_path

        for subdir in nvidia mesa dxvk vkd3d; do
            defer_mkdir "$shader_path/$subdir"
        done
    fi
}

register_hook load_config feat_program_cache_load_config

# 清除缓存目录中的内容，保留目录本身
# 用法: program_cache_clear_dir <config_key> <label>
program_cache_clear_dir() {
    local key="$1"
    local label="$2"
    local path

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
    if config_has cache.shader.path || config_is_true cache.shader.enabled; then
        program_cache_clear_dir cache.shader.path "着色器"
    fi
}

program_cache_render() {
    local path

    # 显式配置的路径即使开关关闭也展示，因为 invalidate 仍会清理它
    if config_has cache.shader.path; then
        config_read cache.shader.path path
        [ -n "$path" ] && printf '[program] %s\n' "$path"
        return 0
    fi

    config_is_true cache.shader.enabled || return 0
    config_read cache.shader.path path
    printf '[program] %s\n' "$path"
}
