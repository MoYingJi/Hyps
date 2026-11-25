#!/usr/bin/bash

GAME_NAME="wuwa"

exec "$(dirname -- "${BASH_SOURCE[0]}")/_Hyps" run "$GAME_NAME"
