#!/hint/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

#shellcheck source=../integrations/hyp.sh
source "$SCRIPT_DIR/integrations/hyp.sh"

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
    # 我已经不玩崩崩崩了，这个路径是我在米游社找的
    local target
    target="$(game_fs_write_path userprofile "Pictures/bh3rd")" || return 1
    try_link_dir "$SCREENSHOTS/Honkai3" "$target"
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
