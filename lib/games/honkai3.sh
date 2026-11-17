#!/hint/bash
#shellcheck disable=SC2034 # 游戏元数据由通用模块读取

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

#shellcheck source=../integrations/hyp.sh
source "$SCRIPT_DIR/integrations/hyp.sh"

# 游戏元数据

GAME_DISPLAY_NAME="崩坏三"
GAME_PATH_NAME="Honkai3"
GAME_DAILY_RESET="04:00 Asia/Shanghai"

# 游戏安装根与可执行文件

game_install_dir() {
    local game_exe="$1"
    local game_dir
    path_dirname "$game_exe" game_dir
    printf '%s\n' "$game_dir"
}

game_executable() {
    printf '%s\n' "$1/BH3.exe"
}

# 游戏路径声明

game_paths() {
    # 我已经不玩崩崩崩了，这个路径是我在米游社找的
    path_plan_declare userdata:screenshot userprofile "Pictures/bh3rd"
}

# 游戏版本

game_version_local() {
    integration_hyp_get_game_version_local "$@"
}

game_version_variant_human_readable() {
    integration_hyp_variant_human_readable "$1"
}

game_version_remote() {
    integration_hyp_get_game_version_remote "honkai3" "${1:-cn}"
}

game_version_predownload_remote() {
    integration_hyp_get_game_predownload_remote "honkai3" "${1:-cn}"
}
