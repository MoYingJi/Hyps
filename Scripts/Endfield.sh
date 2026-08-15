#!/usr/bin/bash
#shellcheck source=_Lib.sh disable=2034

GAME_NAME="endfield"

source _Lib.sh

userdata_link() {
    local userprofile="$2"
    try_link_dir "$USERDATA_LINK_SCREENSHOTS/Endfield" "$userprofile/Pictures/ENDFIELD"
}

start_game
