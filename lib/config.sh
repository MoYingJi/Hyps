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

load_game_config() {
    local game_name="$1"

    local game_config_file
    local runner_name

    game_config_file="$CONFIG_DIR/games/${game_name}.conf"
    [ -f "$game_config_file" ] || die 1 config "游戏配置文件不存在：$game_config_file"

    if config_has runner.name; then
        # 如果已经有 runner，直接读
        runner_name="$(config_get runner.name)"
        config_parse_file "$CONFIG_DIR/runners/${runner_name}.conf"
        config_parse_file "$game_config_file"
    else
        # 为了保证优先级 runner < games
        # 先从 games 读 runner，再读 runner 配置，然后将 games 配置合并上去
        config_parse_to_temp "$game_config_file"
        runner_name="${TEMP_CONFIG[runner.name]}"
        config_parse_file "$CONFIG_DIR/runners/${runner_name}.conf"
        config_merge_temp
    fi

    if ! config_has runner.exe && config_has runner.protonpath; then
        local proton_path
        proton_path="$(env_transform_protonpath "$(config_get runner.protonpath)")"
        config_set runner.protonpath "$proton_path"
        config_set runner.exe "$proton_path/proton"
    fi

    config_require_realpath_which_exe runner.exe
    config_require_realpath_file game.exe

    config_realpath game.prefix "$DATA_DIR/prefixes/${game_name}" >/dev/null
}
