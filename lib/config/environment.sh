#!/hint/bash

[[ -n "${__CONFIG_ENVIRONMENT_SH_LOADED:-}" ]] && return 0
__CONFIG_ENVIRONMENT_SH_LOADED=1

#shellcheck source=../environment.sh
source "$SCRIPT_DIR/environment.sh"
#shellcheck source=core.sh
source "$SCRIPT_DIR/config/core.sh"
#shellcheck source=../utils/wine.sh
source "$SCRIPT_DIR/utils/wine.sh"

config_declare_namespace env string --in global,runner,game-instance --description "环境变量，未单独声明的成员按字符串透传"
# 跳过导出 在项目内设置
config_declare env.LD_PRELOAD 'string|array' --in global,runner,game-instance
env_reserve LD_PRELOAD
# Spritz
env_declare WINE_ENABLE_TIMEOUT_FIX bool --encode bool01
env_declare WINE_ENABLE_STEAM_STUB bool --encode bool01
# DXVK
# 有些 proton 默认开启 DXVK_HUD=compiler，此处如果未设置则显式指定为关闭
env_declare DXVK_HUD string --default 0
env_declare DXVK_HDR bool --encode bool01
env_declare DXVK_CONFIG string
env_declare DXVK_ASYNC bool --encode bool01
env_declare DXVK_GPLASYNCCACHE bool --encode bool01
env_declare DXVK_FRAME_PACE string
# VKD3D
env_declare VKD3D_CONFIG 'string|array' --encode comma_list
env_declare VKD3D_DEBUG string
# UMU
env_declare UMU_LOG string
env_declare PROTON_VERB string
env_declare UMU_RUNTIME_UPDATE bool --encode bool01
env_declare UMU_NO_PROTON bool --encode bool01
env_declare UMU_HTTP_TIMEOUT uint
env_declare UMU_HTTP_RETRIES uint
# Proton
env_declare UMU_USE_STEAM bool --encode bool01
env_declare UMU_ID string
env_declare STEAM_COMPAT_CLIENT_INSTALL_PATH path --check dir
env_declare PRESSURE_VESSEL_FILESYSTEMS_RW 'string|array' --encode colon_list
env_declare PRESSURE_VESSEL_SYSTEMD_SCOPE bool --encode bool01
env_declare PROTON_DLSS_INDICATOR bool --encode bool01
env_declare PROTON_FSR4_INDICATOR bool --encode bool01
env_declare PROTON_PREFER_SDL bool --encode bool01
env_declare PROTON_ENABLE_WAYLAND bool --encode bool01
env_declare PROTON_ENABLE_HDR bool --encode bool01
env_declare PROTON_USE_OPTISCALER bool --encode bool01
env_declare PROTON_OPTISCALER_NAME string
env_declare PROTON_DXVK_GPLASYNC bool --encode bool01
env_declare PROTON_DXVK_LLASYNC bool --encode bool01
# Wine
env_declare WINEDLLOVERRIDES 'string|array' --encode semicolon_list
config_declare wine.dll_overrides array --in global,runner,game-instance
env_bind wine.dll_overrides WINEDLLOVERRIDES --encode semicolon
# MangoHud
env_declare MANGOHUD bool --encode bool01
config_declare mangohud.config array
env_bind mangohud.config MANGOHUD_CONFIG --encode comma
env_declare MANGOHUD_CONFIG 'string|array' --encode comma_list
config_declare mangohud.configfile path
env_bind mangohud.configfile MANGOHUD_CONFIGFILE --check file
env_declare MANGOHUD_CONFIGFILE path --check file
config_declare mangohud.presetsfile path
env_bind mangohud.presetsfile MANGOHUD_PRESETSFILE --check file
env_declare MANGOHUD_PRESETSFILE path --check file
env_declare MANGOHUD_DLSYM bool --encode bool01
# NVIDIA
env_declare NVPRESENT_ENABLE_SMOOTH_MOTION bool --encode bool01
# OBS Game Capture
config_declare obs_vkcapture.env bool
env_bind obs_vkcapture.env OBS_VKCAPTURE --encode bool01
env_declare OBS_VKCAPTURE bool --encode bool01
config_declare obs_vkcapture.name string
env_bind obs_vkcapture.name OBS_VKCAPTURE_NAME
env_declare OBS_VKCAPTURE_NAME string
# 我是 Steam Deck 别杀我 ✋😭🤚
env_declare STEAMDECK bool --encode bool01
env_declare SteamDeck bool --encode bool01
env_declare SteamOS bool --encode bool01

env_bind runner.protonpath PROTONPATH --encode protonpath
env_declare PROTONPATH string --encode protonpath
env_bind game.umu_id GAMEID
env_bind game.umu_id UMU_ID

env_encode_protonpath() {
    local -n _env_proton_out="$2"
    [[ -n "$1" ]] || die 1 environment "配置项 '$3' 不能为空"
    if [[ -d "$1" ]]; then
        _env_proton_out="$(realpath -- "$1")"
    else
        _env_proton_out="$(find_proton_by_name "$1")" ||
            die 4 environment "未找到 Proton: '$1' ($3)"
    fi
}

runner_environment_collect() {
    # prefix 变量名由 runner 决定
    local prefix_var
    config_read runner.prefix_var prefix_var
    environment_offer game.prefix "$prefix_var"
}

# GAMEID 与 UMU_ID 是同一标识，按最终来源优先级统一
runner_environment_finalize() {
    local chosen other
    if [[ -n "${ENV_OUTPUT[GAMEID]+exists}" ]]; then
        chosen=GAMEID
    elif [[ -n "${ENV_OUTPUT[UMU_ID]+exists}" ]]; then
        chosen=UMU_ID
    else
        return 0
    fi
    if [[ -n "${ENV_OUTPUT[GAMEID]+exists}" && -n "${ENV_OUTPUT[UMU_ID]+exists}" ]]; then
        if [[ "${ENV_PRIORITY[GAMEID]}" -eq "${ENV_PRIORITY[UMU_ID]}" ]]; then
            [[ "${ENV_OUTPUT[GAMEID]}" == "${ENV_OUTPUT[UMU_ID]}" ]] ||
                die 1 environment "GAMEID 与 UMU_ID 的同级来源不一致 (${ENV_SOURCE[GAMEID]}、${ENV_SOURCE[UMU_ID]})"
        elif [[ "${ENV_PRIORITY[UMU_ID]}" -gt "${ENV_PRIORITY[GAMEID]}" ]]; then
            chosen=UMU_ID
        fi
    fi
    [[ -n "${ENV_OUTPUT[$chosen]}" ]] ||
        die 1 environment "UMU 游戏标识不能为空 (${ENV_SOURCE[$chosen]})"
    for other in GAMEID UMU_ID; do
        [[ "$other" != "$chosen" ]] || continue
        ENV_OUTPUT["$other"]="${ENV_OUTPUT[$chosen]}"
        ENV_SOURCE["$other"]="统一自 $chosen：${ENV_SOURCE[$chosen]}"
        ENV_PRIORITY["$other"]="${ENV_PRIORITY[$chosen]}"
        ENV_CHECK["$other"]=""
    done
}

environment_register_provider runner_environment_collect
environment_register_finalizer runner_environment_finalize
