#!/usr/bin/bash
#shellcheck source=_Lib.sh disable=2034

# === 已不受支持 ===
# 目前能用，但不保证未来能用，方案多变

GAME_NAME="yuanshen"

# FPS 解锁
check_fps_unlock() {
    [ ! "$FPS_UNLOCK" = "y" ] && return 0

    [ -z "$FPS_UNLOCK_PATH" ] && FPS_UNLOCK_PATH="./Tools/fpsunlock"

    check_cached_compile "FPS_UNLOCK" \
        "$FPS_UNLOCK_PATH/unlocker" \
        "$FPS_UNLOCK_PATH/unlocker.c" \
        "$CACHE_DIR/unlocker.c.sha256sum"

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
    [ -z "$FPS_UNLOCK_FIFO" ] && FPS_UNLOCK_FIFO="$TEMP_DIR/fpsunlock_fifo"

    [ -z "$FPS_UNLOCK_PROG" ] && FPS_UNLOCK_PROG="YuanShen.exe"

    if [ "$FPS_UNLOCK_XWIN_WATCH" = "y" ]; then
        # PID
        [ -z "$FPS_UNLOCK_PID" ] && FPS_UNLOCK_PID="\$(pgrep -n -u \"$USER\" \"$FPS_UNLOCK_PROG\")"

        # 调用 XWin Watch
        XWIN_WATCH_ON_EXISTS="$(cat << EOF
$XWIN_WATCH_ON_EXISTS
game_pid="$FPS_UNLOCK_PID"
echo "[fpsunlock] PID: \$game_pid"
"$FPS_UNLOCK_BIN" "\$game_pid" "$FPS_UNLOCK_FPS" "$FPS_UNLOCK_INTERVAL" "$FPS_UNLOCK_FIFO" &
EOF
        )"
        XWIN_WATCH="y"
    fi
}

after_start_game() {
    if [ ! "$FPS_UNLOCK" = "y" ] || [ "$FPS_UNLOCK_XWIN_WATCH" = "y" ]; then
        return 0
    fi

    if [ -n "$FPS_UNLOCK_SLEEP" ]; then
        echo "[fpsunlock] 等待 $FPS_UNLOCK_SLEEP 秒以确保游戏已启动"
        sleep "$FPS_UNLOCK_SLEEP"
    fi

    [ -z "$FPS_UNLOCK_PID" ] && FPS_UNLOCK_PID="$(pgrep -n -u "$USER" "$FPS_UNLOCK_PROG")"

    echo "[fpsunlock] PID: $FPS_UNLOCK_PID"
    "$FPS_UNLOCK_BIN" "$FPS_UNLOCK_PID" "$FPS_UNLOCK_FPS" "$FPS_UNLOCK_INTERVAL" "$FPS_UNLOCK_FIFO" &
}

before_xwin_watch() {
    check_fps_unlock
}

source _Lib.sh

if isy "$PREPARE_HDR_REG"; then
    [ -z "$PREPARE_HDR_REG_PATH" ] && PREPARE_HDR_REG_PATH="HKEY_CURRENT_USER\\Software\\miHoYo\\原神"
    [ -z "$PREPARE_HDR_REG_KEY" ] && PREPARE_HDR_REG_KEY="WINDOWS_HDR_ON_h3132281285"
    [ -z "$PREPARE_HDR_REG_FILE" ] && PREPARE_HDR_REG_FILE="user.reg"
fi

try_edit_prefix_reg() {
    if [ ! -r "$PREFIX/$PREPARE_HDR_REG_FILE" ] || [ ! -w "$PREFIX/$PREPARE_HDR_REG_FILE" ]; then
        echo "[GI-HDR] 无法读取或写入注册表文件"
        return 1
    fi

    if [ "$(grep -c "$PREPARE_HDR_REG_KEY\"=dword:" "$PREFIX/$PREPARE_HDR_REG_FILE")" -eq 0 ]; then
        echo "[GI-HDR] 注册表文件中未找到目标键值"
        return 1
    fi

    sed -i "s/\"$PREPARE_HDR_REG_KEY\"=dword:00000000/\"$PREPARE_HDR_REG_KEY\"=dword:00000001/g" "$PREFIX/$PREPARE_HDR_REG_FILE"
}

if isy "$PREPARE_HDR_REG"; then
    if try_edit_prefix_reg; then
        echo "[GI-HDR] 已设置注册表"
    else
        echo "[GI-HDR] 设置注册表失败，将在尝试在游戏启动前通过 wine reg 设置注册表（若第一次使用此功能，这是正常情况）"

        PREPARE_BATCH="$(cat << EOF
$PREPARE_BATCH
reg add "$PREPARE_HDR_REG_PATH" /v "$PREPARE_HDR_REG_KEY" /t REG_DWORD /d 1 /f
EOF
        )"
    fi
fi

# 启动

start_game
