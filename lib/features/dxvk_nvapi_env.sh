#!/hint/bash

#shellcheck source=../lifecycle.sh
source "${SCRIPT_DIR:-.}/lifecycle.sh"
#shellcheck source=../config.sh
source "${SCRIPT_DIR:-.}/config.sh"
#shellcheck source=../utils.sh
source "${SCRIPT_DIR:-.}/utils.sh"
#shellcheck source=../log.sh
source "${SCRIPT_DIR:-.}/log.sh"

feat_dxvk_nvapi_load_config() {
    local key
    local env_name

    local drs_settings=()
    config_read_array nvapi.drs.settings drs_settings

    for key in "${!CONFIG[@]}"; do
        if [[ "$key" == nvapi.drs.* ]]; then
            [[ "$key" == nvapi.drs.settings ]] && continue
            env_name="${key#nvapi.drs.}"
            drs_settings+=("$env_name=${CONFIG[$key]}")
        fi
    done

    if [[ "${#drs_settings[@]}" -gt 0 ]]; then
        config_set nvapi.drs.settings "$(IFS=,; echo "${drs_settings[*]}")" >/dev/null
    fi

    ENV_EXPORTS+=(
        "nvapi.drs.settings|DXVK_NVAPI_DRS_SETTINGS|string"
        "nvapi.vkreflex|DXVK_NVAPI_VKREFLEX|bool_to_01"
        "nvapi.gpu_arch|DXVK_NVAPI_GPU_ARCH|string"
    )
}

register_hook load_config feat_dxvk_nvapi_load_config
