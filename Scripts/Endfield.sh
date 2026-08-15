#!/usr/bin/bash
#shellcheck disable=2034

GAME_NAME="endfield"

#shellcheck source=../Lib/Common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../Lib/Common.sh"

userdata_link() {
    local userprofile="$2"
    try_link_dir "$USERDATA_LINK_SCREENSHOTS/Endfield" "$userprofile/Pictures/ENDFIELD"
}

start_game
