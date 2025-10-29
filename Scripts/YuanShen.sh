#!/usr/bin/bash
#shellcheck source=_Lib.sh disable=2034,2164

GAME_NAME="yuanshen"

source _Lib.sh

# FPS 解锁

# 方法 1
if [ -n "$FPS_UNLOCKER_PATH" ]; then
    FPS_UNLOCKER_PATH="$(realpath "$FPS_UNLOCKER_PATH")"
    FPS_UNLOCKER_RUN_PATH="$(dirname "$FPS_UNLOCKER_PATH")"
    FPS_UNLOCKER_RUN_NAME="$(basename "$FPS_UNLOCKER_PATH")"

    if [ -z "$FPS_UNLOCK_FPS" ]; then
        echo "[fpsunlocker] 缺少 FPS 参数"
        exit 1
    fi

    [ -z "$FPS_UNLOCK_INTERVAL" ] && FPS_UNLOCK_INTERVAL="5000"

    AFTER_GAME="$(cat << EOF
$AFTER_GAME
cd "$FPS_UNLOCKER_RUN_PATH"
start $FPS_UNLOCKER_RUN_NAME $FPS_UNLOCK_FPS $FPS_UNLOCK_INTERVAL
EOF
    )"
fi

# 方法 2
if [ "$FPS_UNLOCKER_NATIVE" = "y" ]; then
    [ -z "$FPS_UNLOCK_PATH" ] && FPS_UNLOCK_PATH="./Tools/fpsunlock"

    check_cached_compile "FPS_UNLOCK" \
        "$FPS_UNLOCK_PATH/unlocker" \
        "$FPS_UNLOCK_PATH/unlocker.c" \
        "$CACHE_DIR/unlocker.c.sha256"

    if [ -n "$FPS_UNLOCK_BIN" ] && [ ! -f "$FPS_UNLOCK_BIN" ] && [ -f "$FPS_UNLOCK_SRC" ]; then
        echo "[fpsunlock] 编译 $FPS_UNLOCK_SRC"
        gcc "$FPS_UNLOCK_SRC" -o "$FPS_UNLOCK_BIN" -Wall -Wextra
    fi

    if [ ! -f "$FPS_UNLOCK_BIN" ]; then
        echo "[fpsunlock] 编译失败或源文件不存在"
        exit 1
    else
        sha256sum "$FPS_UNLOCK_SRC" | awk '{print $1}' > "$FPS_UNLOCK_SHA256_FILE"
    fi

    # 确保可执行
    set_executable "$FPS_UNLOCK_BIN"

    # 权限
    if [[ ! "$(getcap "$FPS_UNLOCK_BIN")" =~ cap_sys_ptrace=ep  ]]; then
        echo "[sudo 请求] 赋予读写进程内存权限 需要 root 权限"
        sudo setcap cap_sys_ptrace+ep "$FPS_UNLOCK_BIN"
    fi

    # 参数
    if [ -z "$FPS_UNLOCK_FPS" ]; then
        echo "[fpsunlock] 缺少 FPS 参数"
        exit 1
    fi

    [ -z "$FPS_UNLOCK_INTERVAL" ] && FPS_UNLOCK_INTERVAL="5000"
    [ -z "$FPS_UNLCOK_FIFO" ] && FPS_UNLCOK_FIFO="$TEMP_DIR/fpsunlock_fifo"

    # PID
    if [ -z "$FPS_UNLOCK_PID" ]; then
        [ -z "$FPS_UNLOCK_PROG" ] && FPS_UNLOCK_PROG="YuanShen.exe"
        FPS_UNLOCK_PID="\$(pgrep -f \"$FPS_UNLOCK_PROG\")"
    fi

    # 调用 XWin Watch
    XWIN_WATCH_ON_EXISTS="$(cat << EOF
$XWIN_WATCH_ON_EXISTS
game_pid="$FPS_UNLOCK_PID"
echo "[fpsunlock] PID: \$game_pid"
"$FPS_UNLOCK_BIN" "\$game_pid" "$FPS_UNLOCK_FPS" "$FPS_UNLOCK_INTERVAL" "$FPS_UNLCOK_FIFO" &
EOF
    )"
fi

# 启动

start_game
