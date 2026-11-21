#!/hint/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

#shellcheck source=../config/environment.sh
source "$SCRIPT_DIR/config/environment.sh"
#shellcheck source=../environment.sh
source "$SCRIPT_DIR/environment.sh"

config_declare_namespace nvapi.drs string --description "NVAPI DRS 设置，成员名对应驱动设置名"
config_declare nvapi.drs.settings array --default '[]'
config_declare nvapi.vkreflex bool
config_declare nvapi.gpu_arch string

env_encode_nvapi_drs() {
    local key drs_value
    local -n result="$2"
    local drs_settings=()
    config_read_array nvapi.drs.settings drs_settings

    while IFS= read -r key; do
        if [[ "$key" == nvapi.drs.* ]]; then
            [[ "$key" == nvapi.drs.settings ]] && continue
            config_read "$key" drs_value
            drs_settings+=("${key#nvapi.drs.}=$drs_value")
        fi
    done < <(printf '%s\n' "${!CONFIG[@]}" | LC_ALL=C sort)

    local IFS=,
    #shellcheck disable=SC2034 # 通过 nameref 写回调用方
    result="${drs_settings[*]}"
}

env_bind nvapi.drs.settings DXVK_NVAPI_DRS_SETTINGS --encode nvapi_drs
env_bind nvapi.vkreflex DXVK_NVAPI_VKREFLEX --encode bool01
env_bind nvapi.gpu_arch DXVK_NVAPI_GPU_ARCH
