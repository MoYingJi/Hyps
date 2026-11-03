#!/hint/bash

[[ -n "${__UTILS_GAME_SCRIPT_SH_LOADED:-}" ]] && return 0
__UTILS_GAME_SCRIPT_SH_LOADED=1

game_script_name() {
    local -n gsn_out="$2"
    local gsn_line
    gsn_out=""
    while IFS= read -r gsn_line || [[ -n $gsn_line ]]; do
        if [[ $gsn_line == 'GAME_NAME="'*'"' ]]; then
            gsn_out="${gsn_line#GAME_NAME=\"}"
            gsn_out="${gsn_out%\"}"
            return 0
        fi
    done < "$1"
    return 1
}
