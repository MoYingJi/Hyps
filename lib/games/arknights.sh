#!/hint/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

game_install_dir() {
    local game_exe="$1"
    local game_dir
    path_dirname "$game_exe" game_dir
    printf '%s\n' "$game_dir"
}

time_record_today_reset() {
    echo "04:00 Asia/Shanghai"
}

userdata_link() {
    local target
    target="$(game_fs_write_path userprofile "Pictures/Arknights_Screenshots")" || return 1
    try_link_dir "$SCREENSHOTS/Arknights" "$target"
}
