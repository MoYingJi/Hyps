#!/hint/bash

[[ -n "${__CONFIG_SH_LOADED:-}" ]] && return 0
__CONFIG_SH_LOADED=1

#shellcheck source=config/state.sh
source "$SCRIPT_DIR/config/state.sh"
#shellcheck source=core/log.sh
source "$SCRIPT_DIR/core/log.sh"
#shellcheck source=utils/wine.sh
source "$SCRIPT_DIR/utils/wine.sh"
#shellcheck source=utils/game_script.sh
source "$SCRIPT_DIR/utils/game_script.sh"

#shellcheck source=config/parse.sh
source "$SCRIPT_DIR/config/parse.sh"
#shellcheck source=config/access.sh
source "$SCRIPT_DIR/config/access.sh"
#shellcheck source=config/core.sh
source "$SCRIPT_DIR/config/core.sh"

declare -gA _CONFIG_BOOTSTRAP_SOURCE=() _CONFIG_GLOBAL_SOURCE=()
_CONFIG_BOOTSTRAP_LAYERS=bootstrap
CONFIG_GAME_NAME=""

load_global_config() {
    local bootstrap_file="$PROJECT_ROOT/config.conf" global_file legacy_file
    #shellcheck disable=SC2034 # 通过 nameref 接收解析结果
    local -A bootstrap_config=() bootstrap_kind=() global_config=() global_kind=()
    _CONFIG_BOOTSTRAP_SOURCE=() _CONFIG_GLOBAL_SOURCE=()
    _CONFIG_BOOTSTRAP_LAYERS=bootstrap
    _CONFIG_GLOBAL_READY=false

    config_parse_file "$bootstrap_file" bootstrap_config _CONFIG_BOOTSTRAP_SOURCE bootstrap_kind || return 1
    config_merge bootstrap_config _CONFIG_BOOTSTRAP_SOURCE bootstrap_kind
    config_capture_path_override path.config CONFIG_DIR
    config_read path.config CONFIG_DIR || return 1

    global_file="$CONFIG_DIR/config.conf"
    if [[ "$global_file" -ef "$bootstrap_file" ]]; then
        _CONFIG_BOOTSTRAP_LAYERS=bootstrap,global
    else
        config_parse_file "$global_file" global_config _CONFIG_GLOBAL_SOURCE global_kind || return 1
    fi
    _config_check_global_placement || return 1

    legacy_file="$CONFIG_DIR/games/_common.conf"
    if [[ -e "$legacy_file" || -L "$legacy_file" ]]; then
        log_error config "旧配置 '$legacy_file' 已停用。请将设置合并到 '$global_file'，再移走旧文件"
        return 1
    fi

    config_merge global_config _CONFIG_GLOBAL_SOURCE global_kind
    local path_key
    local -A path_vars=([path.cache]=CACHE_DIR [path.data]=DATA_DIR [path.state]=STATE_DIR
        [path.temp]=TEMP_DIR [path.runtime]=RUNTIME_DIR)
    for path_key in "${!path_vars[@]}"; do
        config_capture_path_override "$path_key" "${path_vars[$path_key]}"
    done
    for path_key in "${!path_vars[@]}"; do
        config_read "$path_key" "${path_vars[$path_key]}" || return 1
    done

    # 后续加载游戏和 runner 时，全局键的引用仍在全局配置中解析
    local key
    _CONFIG_GLOBAL=() _CONFIG_GLOBAL_ORIGINS=() _CONFIG_GLOBAL_KIND=()
    for key in "${!CONFIG[@]}"; do
        _CONFIG_GLOBAL["$key"]="${CONFIG[$key]}"
        _CONFIG_GLOBAL_ORIGINS["$key"]="${CONFIG_SOURCE[$key]}"
        _CONFIG_GLOBAL_KIND["$key"]="${CONFIG_KIND[$key]}"
    done
    _CONFIG_GLOBAL_READY=true
}

_config_check_global_placement() {
    config_check_placement "$_CONFIG_BOOTSTRAP_LAYERS" _CONFIG_BOOTSTRAP_SOURCE || return 1
    config_check_placement global _CONFIG_GLOBAL_SOURCE
}

load_game_config() {
    local game_name="$1"
    game_name_valid "$game_name" || die 1 config "无效的游戏名 '$game_name'"
    CONFIG_GAME_NAME="$game_name"

    local game_config_file
    local runner_name runner_file runner_source status=0
    #shellcheck disable=SC2034 # 通过 nameref 接收解析结果
    local -A instance_config=() instance_source=() instance_kind=()

    game_config_file="$CONFIG_DIR/games/${game_name}.conf"
    [ -f "$game_config_file" ] || die 1 config "游戏配置文件不存在：$game_config_file"

    # 查询命令可能先加载全局配置，再注册游戏专属声明
    _config_check_global_placement || return 1
    config_parse_file "$game_config_file" instance_config instance_source instance_kind || return 1
    config_check_placement game-instance instance_source || return 1

    config_merge instance_config instance_source instance_kind
    _config_resolve runner.name runner_name runner_source || status=$?
    [[ "$status" -eq 0 || "$status" -eq 3 ]] || return "$status"

    # 配置覆盖顺序为 全局配置 < runner 配置 < 游戏配置
    # 空名称不加载预设，允许直接配置 runner.exe / runner.protonpath
    if [[ -n "$runner_name" ]]; then
        [[ "$runner_name" =~ ^[A-Za-z0-9_-]+$ ]] || die 1 config "无效的运行器名称 '$runner_name'"
        runner_file="$CONFIG_DIR/runners/${runner_name}.conf"
        config_parse_to_temp "$runner_file" || return 1
        config_check_placement runner TEMP_CONFIG_SOURCE || return 1
        config_merge TEMP_CONFIG TEMP_CONFIG_SOURCE TEMP_CONFIG_KIND
        config_merge instance_config instance_source instance_kind
    fi
    # runner 的选择只依赖这一步已经加载的值
    if [[ "$status" -eq 0 ]]; then
        config_set runner.name "$runner_name" "$runner_source"
    fi
}

# 查询只合并配置，启动和需要游戏路径的操作显式执行检查
config_require_game_paths() {
    if config_has game.exe; then
        config_require game.exe file
    fi
    if config_has game.install_dir; then
        config_require game.install_dir dir
    fi

    if config_has game.cwd; then
        config_require game.cwd dir
    fi
}

config_require_launch() {
    config_validate game runner
    if ! config_has runner.exe && config_has runner.protonpath; then
        local proton_path
        config_read runner.protonpath proton_path
        [[ -n "$proton_path" ]] || die 1 config "配置项 'runner.protonpath' 不能为空"
        if [[ -d "$proton_path" ]]; then
            proton_path="$(realpath -- "$proton_path")"
        else
            proton_path="$(find_proton_by_name "$proton_path")" ||
                die 4 config "未找到 Proton: '$proton_path'"
        fi
        config_set runner.exe "$proton_path/proton" "派生自 runner.protonpath"
    fi
    config_require runner.exe executable
    config_require_game_paths
}
