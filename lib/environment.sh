#!/hint/bash

[[ -n "${__ENVIRONMENT_SH_LOADED:-}" ]] && return 0
__ENVIRONMENT_SH_LOADED=1

#shellcheck source=libs.sh
source "$SCRIPT_DIR/libs.sh"

declare -a ENV_EXPORTS=(
    # 跳过导出 在项目内设置
    "env.CFLAGS|CFLAGS|noop"
    # Spritz
    "env.WINE_ENABLE_TIMEOUT_FIX|WINE_ENABLE_TIMEOUT_FIX|bool_to_01"
    "env.WINE_ENABLE_STEAM_STUB|WINE_ENABLE_STEAM_STUB|bool_to_01"
    # DXVK
    "env.DXVK_HUD|DXVK_HUD|bool_to_01"
    "env.DXVK_HDR|DXVK_HDR|bool_to_01"
    "env.DXVK_CONFIG|DXVK_CONFIG|string"
    # VKD3D
    "env.VKD3D_CONFIG|VKD3D_CONFIG|string"
    # UMU
    "runner.protonpath|PROTONPATH|protonpath"
    "env.PROTONPATH|PROTONPATH|protonpath"
    "env.GAMEID|GAMEID|string"
    "env.UMU_LOG|UMU_LOG|string"
    "env.PROTON_VERB|PROTON_VERB|string"
    "env.UMU_RUNTIME_UPDATE|UMU_RUNTIME_UPDATE|bool_to_01"
    "env.UMU_NO_PROTON|UMU_NO_PROTON|bool_to_01"
    "env.UMU_HTTP_TIMEOUT|UMU_HTTP_TIMEOUT|uint"
    "env.UMU_HTTP_RETRIES|UMU_HTTP_RETRIES|uint"
    # Proton
    "env.UMU_USE_STEAM|UMU_USE_STEAM|bool_to_01"
    "env.UMU_ID|UMU_ID|string"
    "env.STEAM_COMPAT_CLIENT_INSTALL_PATH|STEAM_COMPAT_CLIENT_INSTALL_PATH|path_dir"
    "env.PROTON_DLSS_INDICATOR|PROTON_DLSS_INDICATOR|bool_to_01"
    "env.PROTON_FSR4_INDICATOR|PROTON_FSR4_INDICATOR|bool_to_01"
    "env.PROTON_PREFER_SDL|PROTON_PREFER_SDL|bool_to_01"
    "env.PROTON_ENABLE_WAYLAND|PROTON_ENABLE_WAYLAND|bool_to_01"
    "env.PROTON_ENABLE_HDR|PROTON_ENABLE_HDR|bool_to_01"
    "env.PROTON_USE_OPTISCALER|PROTON_USE_OPTISCALER|bool_to_01"
    "env.PROTON_OPTISCALER_NAME|PROTON_OPTISCALER_NAME|string"
    # MangoHud
    "env.MANGOHUD|MANGOHUD|bool_to_01"
    "mangohud.config|MANGOHUD_CONFIG|string"
    "env.MANGOHUD_CONFIG|MANGOHUD_CONFIG|string"
    "mangohud.configfile|MANGOHUD_CONFIGFILE|path_file"
    "env.MANGOHUD_CONFIGFILE|MANGOHUD_CONFIGFILE|path_file"
    "mangohud.presetsfile|MANGOHUD_PRESETSFILE|path_file"
    "env.MANGOHUD_PRESETSFILE|MANGOHUD_PRESETSFILE|path_file"
    "env.MANGOHUD_DLSYM|MANGOHUD_DLSYM|bool_to_01"
    # NVIDIA
    "env.NVPRESENT_ENABLE_SMOOTH_MOTION|NVPRESENT_ENABLE_SMOOTH_MOTION|bool_to_01"
    # OBS Game Capture
    "obs_vkcapture.env|OBS_VKCAPTURE|bool_to_01"
    "env.OBS_VKCAPTURE|OBS_VKCAPTURE|bool_to_01"
    # 我是 Steam Deck 别杀我 ✋😭🤚
    "env.STEAMDECK|STEAMDECK|bool_to_01"
    "env.SteamDeck|SteamDeck|bool_to_01"
    "env.SteamOS|SteamOS|bool_to_01"
)

env_load_config() {
    # 有些 proton 默认开启 DXVK_HUD=compiler，此处如果未设置则显式指定为关闭
    config_default env.DXVK_HUD false >/dev/null

    # prefix 变量导出
    ENV_EXPORTS+=("game.prefix|$(config_default runner.prefix_var "WINEPREFIX")|string")

    # CFLAGS 设置
    env_parse_cflags
}

register_hook load_config env_load_config

export_env_vars() {
    local key raw_value final_value env_name

    for entry in "${ENV_EXPORTS[@]}"; do
        IFS='|' read -r conf_key env_name transform <<< "$entry"
        raw_value="${CONFIG[$conf_key]:-}"
        [[ -z "${CONFIG[$conf_key]+exists}" ]] && continue
        final_value="$("env_transform_$transform" "$raw_value" "$conf_key")"
        exit_code=$?
        if [ "$exit_code" -ne 0 ]; then
            if [ "$exit_code" -eq 1 ]; then
                log_debug environment "[显式] 跳过 export $env_name, transform: $transform, exit code: $exit_code"
            elif [ "$exit_code" -eq 2 ]; then
                log_info environment "[显式] 跳过 export $env_name, transform: $transform, exit code: $exit_code"
            elif [ "$exit_code" -eq 3 ]; then
                log_warn environment "[显式] 跳过 export $env_name, transform: $transform, exit code: $exit_code"
            elif [ "$exit_code" -eq 4 ]; then
                die "$exit_code" environment "配置项 '$conf_key' 的值 '$raw_value' 无效: transform '$transform' 返回错误码 $exit_code"
            fi
            continue
        fi
        _export_env_var "$env_name" "$final_value" "显式"
    done

    for key in "${!CONFIG[@]}"; do
        [[ "$key" != env.* ]] && continue
        local already_handled=false
        for entry in "${ENV_EXPORTS[@]}"; do
            IFS='|' read -r conf_key _ <<< "$entry"
            [[ "$conf_key" == "$key" ]] && already_handled=true && break
        done
        $already_handled && continue
        raw_value="${CONFIG[$key]}"
        env_name="${key#env.}"
        _export_env_var "$env_name" "$raw_value" "自动"
    done
}

_export_env_var() {
    local key="$1"
    local value="$2"
    local prefix="$3"

    if [[ -z "${!key:-}" ]]; then
        export "${key}=${value}"
        log_debug environment "[$prefix] export $key=$value"
    else
        log_debug environment "[$prefix] 跳过 export $key，已存在于环境变量中，保持环境值"
        log_debug environment "[$prefix]  - [环境值] $key=${!key}"
        log_debug environment "[$prefix]  - [配置值] $key=$value"
    fi
}

declare -a ENV_MKDIRS=()

env_mkdirs() {
    local dir
    for dir in "${ENV_MKDIRS[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir" || die 1 environment "无法创建目录: '$dir'"
        fi
    done
}

register_hook prepare env_mkdirs


env_transform_noop() {
    return 1
}

env_transform_string() {
    local value="$1"
    echo "$value"
}

env_transform_bool_to_01() {
    local value="$1"
    [ -z "$value" ] && return 1
    isy "$value" && echo "1" || echo "0"
    return 0
}

env_transform_uint() {
    local value="$1"
    local conf_key="${2:-}"
    [ -z "$value" ] && die 1 environment "配置项 '$conf_key' 的值为空"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "$value"
    else
        die 4 environment "配置项 '$conf_key' 的值 '$value' 无效: 不是无符号整数"
    fi
}

env_transform_path_dir() {
    local dir_path="$1"
    local conf_key="${2:-}"
    [ -z "$dir_path" ] && die 1 environment "配置项 '$conf_key' 的值为空"
    if [[ -d "$dir_path" ]]; then
        realpath "$dir_path"
    else
        die 4 environment "配置项 '$conf_key' 的值 '$dir_path' 无效: 目录不存在"
    fi
}

env_transform_path_mkdir() {
    local dir_path="$1"
    local conf_key="${2:-}"
    [ -z "$dir_path" ] && die 1 environment "配置项 '$conf_key' 的值为空"
    if [[ -d "$dir_path" ]]; then
        realpath "$dir_path"
        return 0
    elif [[ -e "$dir_path" ]]; then
        die 4 environment "配置项 '$conf_key' 的值 '$dir_path' 无效: 路径已存在但不是目录"
    else
        dir_path="$(realpath -m "$dir_path")"
        ENV_MKDIRS+=("$dir_path")
        log_debug environment "目录待创建: '$dir_path'"
        return 0
    fi
}

env_transform_path_file() {
    local file_path="$1"
    local conf_key="${2:-}"
    [ -z "$file_path" ] && die 1 environment "配置项 '$conf_key' 的值为空"
    if [[ -f "$file_path" ]]; then
        realpath "$file_path"
    else
        die 4 environment "配置项 '$conf_key' 的值 '$file_path' 无效: 文件不存在"
    fi
}

env_transform_protonpath() {
    local proton_path="$1"
    local conf_key="${2:-}"
    [ -z "$proton_path" ] && die 4 environment "配置项 '$conf_key' 的值为空"
    if [[ -d "$proton_path" ]]; then
        realpath "$proton_path"
    else
        find_proton_by_name "$proton_path" || die 4 environment "未找到 Proton: '$proton_path'"
    fi
}

GAME_LD_PRELOAD=()
env_add_ld_preload() {
    local lib="$1"
    if [[ -z "$lib" ]]; then
        die 1 environment "env_add_ld_preload: 参数不能为空"
    fi
    GAME_LD_PRELOAD+=("$lib")
    log_debug environment "添加 LD_PRELOAD 库: '$lib'"
}
env_get_ld_preload() {
    local IFS=':'
    echo "${GAME_LD_PRELOAD[*]}"
}

# 解析 CFLAGS 后续全局按 array 使用
env_parse_cflags() {
    local cflags=()
    local set_cflags=0

    if [[ -n "$CFLAGS" ]] && config_has env.CFLAGS; then
        log_debug environment "CFLAGS 已在环境变量中设置，env.CFLAGS 配置项将被忽略"
    fi

    if [[ -n "$CFLAGS" ]] && [[ "${CFLAGS@a}" != *a* ]]; then
        read -ra cflags <<< "$CFLAGS"
        set_cflags=1
    fi

    #shellcheck disable=SC2128
    if [ -z "$CFLAGS" ] && config_has env.CFLAGS; then
        local cflags_raw
        cflags_raw="$(config_get env.CFLAGS)"
        parse_array "$cflags_raw" cflags || read -ra cflags <<< "$cflags_raw"
        set_cflags=1
    fi

    if [ "$set_cflags" = 1 ]; then
        CFLAGS=("${cflags[@]}")
        log_debug environment "设置 CFLAGS: $(quote_args "${CFLAGS[@]}")"
    fi
}
