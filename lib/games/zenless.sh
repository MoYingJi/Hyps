#!/hint/bash

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

overlay_auto_lower() {
    local game_exe="$1"
    dirname "$game_exe"
}

userdata_link() {
    local game_exe="$3"
    try_link_dir "$SCREENSHOTS/ZenlessZoneZero" "$(dirname "$game_exe")/ScreenShot"
}
