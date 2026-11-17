#!/hint/bash
#shellcheck disable=SC2034 # 游戏元数据由通用模块读取

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

# 游戏元数据

GAME_DISPLAY_NAME="明日方舟"
GAME_PATH_NAME="Arknights"
GAME_DAILY_RESET="04:00 Asia/Shanghai"

# 游戏安装根与可执行文件

game_install_dir() {
    local game_exe="$1"
    local game_dir
    path_dirname "$game_exe" game_dir
    printf '%s\n' "$game_dir"
}

game_executable() {
    printf '%s\n' "$1/Arknights.exe"
}

# 游戏路径声明

game_paths() {
    path_plan_declare userdata:screenshot userprofile "Pictures/Arknights_Screenshots"
}
