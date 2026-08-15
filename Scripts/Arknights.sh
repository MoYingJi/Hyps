#!/usr/bin/bash
#shellcheck disable=2034

GAME_NAME="arknights"

#shellcheck source=../Lib/Common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../Lib/Common.sh"

start_game
