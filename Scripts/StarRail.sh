#!/usr/bin/bash
#shellcheck source=_Lib.sh disable=2034

GAME_NAME="starrail"

# 现在 Jadeite 是可选的
#FORCE_JADEITE="y"

source _Lib.sh

# 注册表解锁帧率 (修改 GraphicsSettings_Model 中的 FPS)
if isy "$STARRAIL_REG_FPS"; then
    [ -z "$STARRAIL_REG_FPS_VAL" ] && STARRAIL_REG_FPS_VAL="120"
    [ -z "$STARRAIL_REG_FPS_SCRIPT" ] && STARRAIL_REG_FPS_SCRIPT="./Tools/starrail-fps.py"
    # 先确保 wineserver 停止 (内存注册表写回磁盘后再修改)
    [ -n "$WINESERVER_KILL_CMD" ] && $WINESERVER_KILL_CMD 2>/dev/null
    sleep 1
    if [ -r "$PREFIX/user.reg" ] && [ -w "$PREFIX/user.reg" ]; then
        python3 "$STARRAIL_REG_FPS_SCRIPT" "$PREFIX/user.reg" "$STARRAIL_REG_FPS_VAL"
    else
        echo "[fps-reg] 无法读写 $PREFIX/user.reg"
    fi
fi

# 用户数据链接
userdata_link() {
    local game_exe="$3"
    try_link_dir "$USERDATA_LINK_SCREENSHOTS/StarRail" "$(dirname "$game_exe")/StarRail_Data/ScreenShots"
}

start_game
