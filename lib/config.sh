#!/hint/bash

[[ -n "${__CONFIG_SH_LOADED:-}" ]] && return 0
__CONFIG_SH_LOADED=1

declare -A TEMP_CONFIG
declare -A CONFIG

#shellcheck source=config/parse.sh
source "${SCRIPT_DIR:-.}/config/parse.sh"
#shellcheck source=config/using.sh
source "${SCRIPT_DIR:-.}/config/using.sh"

load_common_config() {
    config_parse_file "$PROJECT_ROOT/config.conf"

    config_read_realpath_prefer_env path.config CONFIG_DIR "${XDG_CONFIG_HOME:-$HOME/.config}/hypsc"

    config_parse_file "$CONFIG_DIR/config.conf"

    config_read_realpath_prefer_env path.cache CACHE_DIR "${XDG_CACHE_HOME:-$HOME/.cache}/hypsc"
    config_read_realpath_prefer_env path.data DATA_DIR "${XDG_DATA_HOME:-$HOME/.local/share}/hypsc"
    config_read_realpath_prefer_env path.temp TEMP_DIR "/tmp/hypsc"

    config_parse_file "$CONFIG_DIR/games/_common.conf"
}
