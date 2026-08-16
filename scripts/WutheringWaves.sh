#!/usr/bin/bash
#shellcheck disable=2034

GAME_NAME="wuwa"

#shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

overlay_auto_lower() {
    local game_exe="$1"

    case "$game_exe" in
        */"Wuthering Waves.exe") dirname "$game_exe";;
        */"Client/Binaries/Win64/Client-Win64-Shipping.exe") realpath -m "$game_exe/../../../..";;
        *) echo "[Hyps] 无法识别游戏路径: $game_exe" >&2
           return 1;;
    esac
}

userdata_link() {
    local game_exe="$3"

    local game_dir
    game_dir="$(overlay_auto_lower "$game_exe")"

    try_link_dir "$USERDATA_LINK_SCREENSHOTS/WutheringWaves" "$game_dir/Client/Saved/ScreenShot"
}

start_game
