#!/usr/bin/bash
#shellcheck disable=2034

GAME_NAME="starrail"

#shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

# 注册表解锁帧率 (修改 GraphicsSettings_Model 中的 FPS)
if isy "$STARRAIL_REG_FPS"; then
    [ -z "$STARRAIL_REG_FPS_VAL" ] && STARRAIL_REG_FPS_VAL="120"
    [ -z "$STARRAIL_REG_FPS_SCRIPT" ] && STARRAIL_REG_FPS_SCRIPT="./tools/starrail-fps.py"

    ensure_no_wineserver "$PREFIX" "error" "STARRAIL_REG_FPS 需要编辑注册表"

    if [ -f "$PREFIX/user.reg" ]; then
        USER_REG_FILE="$PREFIX/user.reg"
    elif [ -f "$PREFIX/pfx/user.reg" ]; then
        USER_REG_FILE="$PREFIX/pfx/user.reg"
    else
        echo "[fps-reg] 无法找到注册表文件"
        return 1
    fi

    if [ -r "$USER_REG_FILE" ] && [ -w "$USER_REG_FILE" ]; then
        python3 "$STARRAIL_REG_FPS_SCRIPT" "$USER_REG_FILE" "$STARRAIL_REG_FPS_VAL"
    else
        echo "[fps-reg] 无法读写注册表文件 $USER_REG_FILE"
    fi
fi

# Overlay
overlay_auto_lower() {
    local game_exe="$1"
    dirname "$game_exe"
}

# 用户数据链接
userdata_link() {
    local game_exe="$3"
    try_link_dir "$USERDATA_LINK_SCREENSHOTS/StarRail" "$(dirname "$game_exe")/StarRail_Data/ScreenShots"
}

start_game
