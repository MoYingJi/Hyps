#!/hint/bash

[[ -n "${__CONFIG_ENVIRONMENT_SH_LOADED:-}" ]] && return 0
__CONFIG_ENVIRONMENT_SH_LOADED=1

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

declare -a ENV_EXPORTS=(
    # 跳过导出 在项目内设置
    "env.LD_PRELOAD|LD_PRELOAD|noop"
    # Spritz
    "env.WINE_ENABLE_TIMEOUT_FIX|WINE_ENABLE_TIMEOUT_FIX|bool_to_01"
    "env.WINE_ENABLE_STEAM_STUB|WINE_ENABLE_STEAM_STUB|bool_to_01"
    # DXVK
    "env.DXVK_HUD|DXVK_HUD|string"
    "env.DXVK_HDR|DXVK_HDR|bool_to_01"
    "env.DXVK_CONFIG|DXVK_CONFIG|string"
    # VKD3D
    "env.VKD3D_CONFIG|VKD3D_CONFIG|comma_separated_array_to_string"
    "env.VKD3D_DEBUG|VKD3D_DEBUG|string"
    # UMU
    "runner.protonpath|PROTONPATH|protonpath"
    "env.PROTONPATH|PROTONPATH|protonpath"
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
    "env.PRESSURE_VESSEL_FILESYSTEMS_RW|PRESSURE_VESSEL_FILESYSTEMS_RW|colon_separated_array_to_string"
    "env.PRESSURE_VESSEL_SYSTEMD_SCOPE|PRESSURE_VESSEL_SYSTEMD_SCOPE|bool_to_01"
    "env.PROTON_DLSS_INDICATOR|PROTON_DLSS_INDICATOR|bool_to_01"
    "env.PROTON_FSR4_INDICATOR|PROTON_FSR4_INDICATOR|bool_to_01"
    "env.PROTON_PREFER_SDL|PROTON_PREFER_SDL|bool_to_01"
    "env.PROTON_ENABLE_WAYLAND|PROTON_ENABLE_WAYLAND|bool_to_01"
    "env.PROTON_ENABLE_HDR|PROTON_ENABLE_HDR|bool_to_01"
    "env.PROTON_USE_OPTISCALER|PROTON_USE_OPTISCALER|bool_to_01"
    "env.PROTON_OPTISCALER_NAME|PROTON_OPTISCALER_NAME|string"
    # Wine
    "env.WINEDLLOVERRIDES|WINEDLLOVERRIDES|semicolon_separated_array_to_string"
    "wine.dll_overrides|WINEDLLOVERRIDES|semicolon_separated_array_to_string"
    # MangoHud
    "env.MANGOHUD|MANGOHUD|bool_to_01"
    "mangohud.config|MANGOHUD_CONFIG|comma_separated_array_to_string"
    "env.MANGOHUD_CONFIG|MANGOHUD_CONFIG|comma_separated_array_to_string"
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
    "obs_vkcapture.name|OBS_VKCAPTURE_NAME|string"
    "env.OBS_VKCAPTURE_NAME|OBS_VKCAPTURE_NAME|string"
    # 我是 Steam Deck 别杀我 ✋😭🤚
    "env.STEAMDECK|STEAMDECK|bool_to_01"
    "env.SteamDeck|SteamDeck|bool_to_01"
    "env.SteamOS|SteamOS|bool_to_01"
)

env_load_config() {
    # 有些 proton 默认开启 DXVK_HUD=compiler，此处如果未设置则显式指定为关闭
    config_default env.DXVK_HUD 0

    # prefix 变量导出
    config_default runner.prefix_var "WINEPREFIX"
    local prefix_var
    config_read runner.prefix_var prefix_var
    ENV_EXPORTS+=("game.prefix|$prefix_var|string")


    env_parse_compile_settings
    env_parse_ld_preload
}

register_hook load_config env_load_config

export_env_vars() {
    local key raw_value final_value env_name

    env_export_game_umu_id

    for entry in "${ENV_EXPORTS[@]}"; do
        IFS='|' read -r conf_key env_name transform <<< "$entry"
        raw_value="${CONFIG[$conf_key]:-}"
        [[ -z "${CONFIG[$conf_key]+exists}" ]] && continue
        "env_transform_$transform" "$raw_value" "final_value" "$conf_key"
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

env_export_game_umu_id() {
    config_has game.umu_id || return 0

    local configured_id gameid_env umu_id_env game_id
    config_read game.umu_id configured_id
    [[ -n "$configured_id" ]] || die 1 environment "配置项 'game.umu_id' 不能为空"

    gameid_env="${GAMEID:-}"
    umu_id_env="${UMU_ID:-}"
    if [[ -n "$gameid_env" && -n "$umu_id_env" && "$gameid_env" != "$umu_id_env" ]]; then
        die 1 environment "环境变量 GAMEID ('$gameid_env') 与 UMU_ID ('$umu_id_env') 不一致"
    fi

    if [[ -n "$gameid_env" ]]; then
        game_id="$gameid_env"
    elif [[ -n "$umu_id_env" ]]; then
        game_id="$umu_id_env"
    else
        game_id="$configured_id"
    fi

    if [[ "$game_id" != "$configured_id" ]]; then
        log_debug environment "环境变量中的 UMU 游戏 ID '$game_id' 覆盖配置 game.umu_id='$configured_id'"
    fi

    export GAMEID="$game_id"
    export UMU_ID="$game_id"
    log_debug environment "统一 UMU 游戏 ID: GAMEID=UMU_ID='$game_id'"
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
    return 0
}

env_transform_string() {
    local value="$1"
    local -n result="$2"
    result="$value"
}

env_transform_bool_to_01() {
    local value="$1"
    local -n result="$2"
    [ -z "$value" ] && return 1
    isy "$value" && result="1" || result="0"
    return 0
}

env_transform_uint() {
    local value="$1"
    local -n result="$2"
    local conf_key="${3:-}"
    [ -z "$value" ] && die 1 environment "配置项 '$conf_key' 的值为空"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        result="$value"
    else
        die 1 environment "配置项 '$conf_key' 的值 '$value' 无效: 不是无符号整数"
    fi
}

env_transform_path_dir() {
    local dir_path="$1"
    local -n result="$2"
    local conf_key="${3:-}"
    [ -z "$dir_path" ] && die 1 environment "配置项 '$conf_key' 的值为空"
    if [[ -d "$dir_path" ]]; then
        result="$(realpath "$dir_path")"
    else
        die 1 environment "配置项 '$conf_key' 的值 '$dir_path' 无效: 目录不存在"
    fi
}

env_transform_path_mkdir() {
    local dir_path="$1"
    local -n result="$2"
    local conf_key="${3:-}"
    [ -z "$dir_path" ] && die 1 environment "配置项 '$conf_key' 的值为空"
    if [[ -d "$dir_path" ]]; then
        result="$(realpath "$dir_path")"
        return 0
    elif [[ -e "$dir_path" ]]; then
        die 1 environment "配置项 '$conf_key' 的值 '$dir_path' 无效: 路径已存在但不是目录"
    else
        result="$(realpath -m "$dir_path")"
        ENV_MKDIRS+=("$result")
        log_debug environment "目录待创建: '$final_value'"
        return 0
    fi
}

env_transform_path_file() {
    local file_path="$1"
    local -n result="$2"
    local conf_key="${3:-}"
    [ -z "$file_path" ] && die 1 environment "配置项 '$conf_key' 的值为空"
    if [[ -f "$file_path" ]]; then
        result="$(realpath "$file_path")"
    else
        die 1 environment "配置项 '$conf_key' 的值 '$file_path' 无效: 文件不存在"
    fi
}

env_transform_colon_separated_array_to_string() {
    local value="$1"
    local -n result="$2"
    local conf_key="${3:-}"
    if is_array "$value"; then
        local array=()
        parse_array "$value" array
        IFS=':' result="${array[*]}"
    elif [[ -n "$value" ]]; then
        result="$value"
    else
        die 1 environment "配置项 '$conf_key' 的值为空"
    fi
}

env_transform_comma_separated_array_to_string() {
    local value="$1"
    local -n result="$2"
    local conf_key="${3:-}"
    if is_array "$value"; then
        local array=()
        parse_array "$value" array
        IFS=',' result="${array[*]}"
    elif [[ -n "$value" ]]; then
        result="$value"
    else
        die 1 environment "配置项 '$conf_key' 的值为空"
    fi
}

env_transform_semicolon_separated_array_to_string() {
    local value="$1"
    local -n result="$2"
    local conf_key="${3:-}"
    if is_array "$value"; then
        local array=()
        parse_array "$value" array
        IFS=';' result="${array[*]}"
    elif [[ -n "$value" ]]; then
        result="$value"
    else
        die 1 environment "配置项 '$conf_key' 的值为空"
    fi
}

env_transform_protonpath() {
    local proton_path="$1"
    local -n result="$2"
    local conf_key="${3:-}"
    [ -z "$proton_path" ] && die 1 environment "配置项 '$conf_key' 的值为空"
    if [[ -d "$proton_path" ]]; then
        result="$(realpath "$proton_path")"
    else
        result="$(find_proton_by_name "$proton_path")" || die 1 environment "未找到 Proton: '$proton_path'"
    fi
}

GAME_LD_PRELOAD=()
env_parse_ld_preload() {
    local ld_preload_array

    if [[ -n "$LD_PRELOAD" ]] && config_has env.LD_PRELOAD; then
        log_debug environment "LD_PRELOAD 已在环境变量中设置，env.LD_PRELOAD 配置项将被忽略"
    fi

    if [[ -n "$LD_PRELOAD" ]] && [[ "${LD_PRELOAD@a}" != *a* ]]; then
        IFS=':' read -ra ld_preload_array <<< "$LD_PRELOAD"
        for lib in "${ld_preload_array[@]}"; do
            env_add_ld_preload "$lib"
        done
    fi

    if [ -z "$LD_PRELOAD" ] && config_has env.LD_PRELOAD; then
        local ld_preload_raw
        config_read env.LD_PRELOAD ld_preload_raw
        parse_array "$ld_preload_raw" ld_preload_array || IFS=':' read -ra ld_preload_array <<< "$ld_preload_raw"
        for lib in "${ld_preload_array[@]}"; do
            env_add_ld_preload "$lib"
        done
    fi
}
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

env_parse_compile_settings() {
    env_parse_compile_flags CFLAGS compile.CFLAGS HYPS_CFLAGS
    env_parse_compile_cc CC compile.CC HYPS_CC
    env_parse_compile_cc HYPS_WIN_CC compile.mingw.CC HYPS_WIN_CC
    env_parse_compile_flags MINGW_CFLAGS compile.mingw.CFLAGS HYPS_MINGW_CFLAGS
}

env_parse_compile_flags() {
    local env_name="$1"
    local config_key="$2"
    local output_name="$3"
    local env_value="${!env_name:-}"
    local env_attributes="${!env_name@a}"
    local config_value
    local -a flags=()

    unset "$output_name"

    if [[ -n "$env_value" ]] && config_has "$config_key"; then
        log_debug environment "$env_name 已在环境变量中设置，$config_key 配置项将被忽略"
    fi

    if [[ -n "$env_value" ]]; then
        if [[ "$env_attributes" == *a* ]]; then
            #shellcheck disable=SC2178
            local -n env_flags="$env_name"
            flags=("${env_flags[@]}")
        else
            read -ra flags <<< "$env_value"
        fi
    elif config_has "$config_key"; then
        config_read "$config_key" config_value
        parse_array "$config_value" flags || read -ra flags <<< "$config_value"
    else
        return 0
    fi

    #shellcheck disable=SC2178
    local -n output_flags="$output_name"
    #shellcheck disable=SC2034
    output_flags=("${flags[@]}")
    log_debug environment "应用内 CFLAGS [$config_key]: $(quote_args "${flags[@]}")"
}

env_parse_compile_cc() {
    local env_name="$1"
    local config_key="$2"
    local output_name="$3"
    local env_value="${!env_name:-}"
    local value=""

    unset "$output_name"

    if [[ -n "$env_value" ]] && config_has "$config_key"; then
        log_debug environment "$env_name 已在环境变量中设置，$config_key 配置项将被忽略"
    fi

    if [[ -n "$env_value" ]]; then
        value="$env_value"
    elif config_has "$config_key"; then
        config_read "$config_key" value
    else
        return 0
    fi

    printf -v "$output_name" '%s' "$value"
    log_debug environment "应用内 CC [$config_key]: '$value'"
}
