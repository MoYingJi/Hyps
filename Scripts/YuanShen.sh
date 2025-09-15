#!/usr/bin/bash
#shellcheck source=_Lib.sh disable=2034,2164

GAME_NAME="yuanshen"

source _Lib.sh

# FPS 解锁
if [ -n "$FPS_UNLOCKER_PATH" ]; then
    FPS_UNLOCKER_PATH="$(realpath "$FPS_UNLOCKER_PATH")"
    FPS_UNLOCKER_RUN_PATH="$(dirname "$FPS_UNLOCKER_PATH")"
    FPS_UNLOCKER_RUN_NAME="$(basename "$FPS_UNLOCKER_PATH")"

    [ -z "$FPS_UNLOCKER_FPS" ] && FPS_UNLOCKER_FPS="240"
    [ -z "$FPS_UNLOCKER_INTERVAL" ] && FPS_UNLOCKER_INTERVAL="5000"
    [ -z "$FPS_UNLOCKER_DELAY" ] && FPS_UNLOCKER_DELAY="2000"

    FPS_UNLOCKER_CMD="$FPS_UNLOCKER_RUN_NAME $FPS_UNLOCKER_FPS $FPS_UNLOCKER_INTERVAL"
    FPS_UNLOCKER_DELAY_VBS="$(delay_vbs "$FPS_UNLOCKER_DELAY")"

    BEFORE_GAME="$(cat << EOF
$BEFORE_GAME
cd "$FPS_UNLOCKER_RUN_PATH"
start /B cmd /c "start /B /wait \\"$FPS_UNLOCKER_DELAY_VBS\\" & $FPS_UNLOCKER_CMD"
del $FPS_UNLOCKER_DELAY_VBS
EOF
    )"
fi

# 启动

start_game
