#!/hint/bash
#shellcheck disable=SC2034

[[ -n "${__CONFIG_CORE_SH_LOADED:-}" ]] && return 0
__CONFIG_CORE_SH_LOADED=1

#shellcheck source=schema.sh
source "$SCRIPT_DIR/config/schema.sh"
#shellcheck source=access.sh
source "$SCRIPT_DIR/config/access.sh"

_config_default_config_dir() {
    local -n result="$1"
    result="${XDG_CONFIG_HOME:-$HOME/.config}/hypsc"
}

_config_default_cache_dir() {
    local -n result="$1"
    result="${XDG_CACHE_HOME:-$HOME/.cache}/hypsc"
}

_config_default_data_dir() {
    local -n result="$1"
    result="${XDG_DATA_HOME:-$HOME/.local/share}/hypsc"
}

_config_default_state_dir() {
    local -n result="$1"
    result="${XDG_STATE_HOME:-$HOME/.local/state}/hypsc"
}

_config_default_runtime_dir() {
    local -n result="$1"
    # XDG_RUNTIME_DIR 未设置时回退到 path.temp
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
        result="$XDG_RUNTIME_DIR/hypsc"
    else
        config_read path.temp result
    fi
}

_config_default_prefix() {
    [[ -n "${CONFIG_GAME_NAME:-}" ]] || return 3
    local -n result="$1"
    result="$DATA_DIR/prefixes/$CONFIG_GAME_NAME"
}

_config_default_overlay_dir() {
    local -n result="$1"
    result="$DATA_DIR/overlays"
}

config_declare path.config path --default-fn _config_default_config_dir --description "配置目录"
config_declare path.cache path --default-fn _config_default_cache_dir --description "缓存目录"
config_declare path.data path --default-fn _config_default_data_dir --description "数据目录"
config_declare path.state path --default-fn _config_default_state_dir --description "状态目录"
config_declare path.temp path --default /tmp/hypsc --description "临时目录"
config_declare path.runtime path --default-fn _config_default_runtime_dir --description "运行时目录"

config_declare runner.name string --description "运行器预设名称，空值表示不使用预设"
config_declare runner.exe string --description "运行器命令，启动时可由 Proton 路径派生"
config_declare runner.protonpath string --description "Proton 名称或目录"
config_declare runner.args args --default '[]' --description "运行器参数"
config_declare runner.prefix_var string --default WINEPREFIX --description "接收游戏前缀的环境变量"

config_declare game.exe path --description "游戏主程序"
config_declare game.install_dir path --description "游戏安装目录"
config_declare game.cwd path --description "游戏工作目录"
config_declare game.prefix path --default-fn _config_default_prefix --description "游戏 Wine 前缀"
config_declare game.args args --default '[]' --description "游戏启动参数"
config_declare game.umu_id string --description "UMU 游戏标识"

config_declare overlay.enabled bool --default false --description "启用游戏文件系统 overlay"
config_declare overlay.backend enum --choices fuse,kernel --default fuse --when overlay.enabled
config_declare overlay.dir path --default-fn _config_default_overlay_dir --when overlay.enabled
config_declare overlay.lower path --when overlay.enabled
config_declare overlay.upper path --when overlay.enabled
config_declare overlay.work path --when overlay.enabled
config_declare overlay.mount path --when overlay.enabled
