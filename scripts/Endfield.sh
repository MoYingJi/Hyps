#!/usr/bin/bash

GAME_NAME="endfield"

exec "$(dirname -- "${BASH_SOURCE[0]}")/_Hyps" run "$GAME_NAME"
