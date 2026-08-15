#!/usr/bin/bash
#shellcheck disable=2034

GAME_NAME="zenless"

#shellcheck source=../Lib/Common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../Lib/Common.sh"

userdata_link() {
    local game_exe="$3"
    try_link_dir "$USERDATA_LINK_SCREENSHOTS/ZenlessZoneZero" "$(dirname "$game_exe")/ScreenShot"
}

start_game
