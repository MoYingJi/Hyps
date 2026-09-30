#!/hint/bash

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

overlay_auto_lower() {
    local game_exe="$1"
    dirname "$game_exe"
}

feat_time_record_today_reset() {
    echo "04:00 Asia/Shanghai"
}

userdata_link() {
    local userprofile="$2"
    # 我已经不玩崩崩崩了，这个路径是我在米游社找的
    try_link_dir "$SCREENSHOTS/Honkai3" "$userprofile/Pictures/bh3rd"
}
