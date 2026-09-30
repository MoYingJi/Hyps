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
    local game_exe="$3"
    try_link_dir "$SCREENSHOTS/ZenlessZoneZero" "$(dirname "$game_exe")/ScreenShot"
}
