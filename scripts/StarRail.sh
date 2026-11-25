#!/usr/bin/bash

GAME_NAME="starrail"

exec "$(dirname -- "${BASH_SOURCE[0]}")/_Hyps" run "$GAME_NAME"
