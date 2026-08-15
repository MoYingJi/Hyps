#!/usr/bin/bash
#shellcheck source=_Lib.sh disable=2034

GAME_NAME="zenless"

source _Lib.sh

userdata_link() {
    local game_exe="$3"
    try_link_dir "$USERDATA_LINK_SCREENSHOTS/ZenlessZoneZero" "$(dirname "$game_exe")/ScreenShot"
}

start_game
