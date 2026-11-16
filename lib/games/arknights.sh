#!/hint/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

# 游戏元数据

game_display_name() {
    printf '%s\n' "明日方舟"
}

game_path_name() {
    printf '%s\n' "Arknights"
}

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

# 日常重置时间

time_record_today_reset() {
    echo "04:00 Asia/Shanghai"
}
