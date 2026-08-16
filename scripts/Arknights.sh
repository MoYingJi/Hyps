#!/usr/bin/bash
#shellcheck disable=2034

GAME_NAME="arknights"

#shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

overlay_auto_lower() {
    local game_exe="$1"
    dirname "$game_exe"
}

start_game
