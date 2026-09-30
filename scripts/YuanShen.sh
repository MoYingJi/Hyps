#!/usr/bin/bash
#shellcheck disable=2034

# === 已不受支持 ===
# 目前能用，但不保证未来能用，方案多变

GAME_NAME="yuanshen"

#shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

hyps_main
