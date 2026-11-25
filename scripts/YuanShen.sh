#!/usr/bin/bash

# === 已不受支持 ===
# 目前能用，但不保证未来能用，方案多变

GAME_NAME="yuanshen"

exec "$(dirname -- "${BASH_SOURCE[0]}")/_Hyps" run "$GAME_NAME"
