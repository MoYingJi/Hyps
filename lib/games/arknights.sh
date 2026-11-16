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

game_install_dir() {
    local game_exe="$1"
    local game_dir
    path_dirname "$game_exe" game_dir
    printf '%s\n' "$game_dir"
}

game_executable() {
    printf '%s\n' "$1/Arknights.exe"
}

time_record_today_reset() {
    echo "04:00 Asia/Shanghai"
}

userdata_link() {
    local target
    target="$(game_fs_write_path userprofile "Pictures/Arknights_Screenshots")" || return 1
    try_link_dir "$SCREENSHOTS/Arknights" "$target"
}
