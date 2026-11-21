#!/hint/bash
#shellcheck disable=SC2034

[[ -n "${__CONFIG_STATE_SH_LOADED:-}" ]] && return 0
__CONFIG_STATE_SH_LOADED=1

declare -gA CONFIG=()
declare -gA CONFIG_SOURCE=()
declare -gA TEMP_CONFIG=()
declare -gA TEMP_CONFIG_SOURCE=()
