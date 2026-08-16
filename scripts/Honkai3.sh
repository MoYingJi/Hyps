#!/usr/bin/bash
#shellcheck disable=2034

GAME_NAME="honkai3"

#shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

userdata_link() {
    local userprofile="$2"
    # 我已经不玩崩崩崩了，这个路径是我在米游社找的
    try_link_dir "$USERDATA_LINK_SCREENSHOTS/Honkai3" "$userprofile/Pictures/bh3rd"
}

start_game
