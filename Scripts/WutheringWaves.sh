#!/usr/bin/bash
#shellcheck disable=2034

GAME_NAME="wuwa"

#shellcheck source=../Lib/Common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../Lib/Common.sh"

userdata_link() {
    local game_exe="$3"

    local game_dir
    case "$game_exe" in
        */"Wuthering Waves.exe") game_dir="$(dirname "$game_exe")";;
        */"Client/Binaries/Win64/Client-Win64-Shipping.exe") game_dir="$(realpath -m "$game_exe/../../../..")";;
    esac

    try_link_dir "$USERDATA_LINK_SCREENSHOTS/WutheringWaves" "$game_dir/Client/Saved/ScreenShot"
}

start_game
