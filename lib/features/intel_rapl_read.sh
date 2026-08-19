#!/hint/bash

#shellcheck source=../lifecycle.sh
source "${SCRIPT_DIR:-.}/lifecycle.sh"
#shellcheck source=../config.sh
source "${SCRIPT_DIR:-.}/config.sh"
#shellcheck source=../utils.sh
source "${SCRIPT_DIR:-.}/utils.sh"
#shellcheck source=../log.sh
source "${SCRIPT_DIR:-.}/log.sh"

feat_intel_rapl_read_prepare() {
    isy "$(config_get prepare.intel_rapl_read)" || return 0

    local files=(
        /sys/class/powercap/intel-rapl:0/energy_uj
        /sys/class/powercap/intel-rapl:0:*/energy_uj
    )

    local file
    for file in "${files[@]}"; do
        if [ -f "$file" ] && [ ! -r "$file" ]; then
            sudo_request "使 Intel CPU 能量消耗可被读取" chmod a+r "$file"
        fi
    done
}

register_hook prepare feat_intel_rapl_read_prepare
