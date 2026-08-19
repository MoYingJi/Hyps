#!/usr/bin/bash
#shellcheck disable=2034

# === 已不受支持 ===
# 目前能用，但不保证未来能用，方案多变

GAME_NAME="yuanshen"

#shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

# Overlay

overlay_auto_lower() {
    local game_exe="$1"
    dirname "$game_exe"
}

# 用户数据链接

userdata_link() {
    local game_exe="$3"
    try_link_dir "$USERDATA_LINK_SCREENSHOTS/YuanShen" "$(dirname "$game_exe")/ScreenShot"
}

# FPS 解锁

gi_fps_unlock_load_config() {
    isy "$(config_get gi.fps_unlock.enabled)" || return 0

    config_default gi.fps_unlock.val 120 >/dev/null
    config_default gi.fps_unlock.interval 5000 >/dev/null
    config_default gi.fps_unlock.fifo "$TEMP_DIR/fpsunlock_fifo" >/dev/null
    config_default gi.fps_unlock.prog "YuanShen.exe" >/dev/null
    config_default gi.fps_unlock.sleep "-" >/dev/null

    local sleep
    sleep="$(config_get gi.fps_unlock.sleep)"
    if [[ "$sleep" != "-" ]]; then
        if ! [[ "$sleep" =~ ^[0-9]+$ ]]; then
            die 1 gi-fps-unlock "gi.fps_unlock.sleep 必须是整数或 '-'"
        fi
    else
        config_set features.xwin_watch.enabled true
    fi

    register_hook prepare gi_fps_unlock_prepare
}

register_hook load_config gi_fps_unlock_load_config 50 before:feat_xwin_watch_load_config

gi_fps_unlock_prepare() {
    local tool
    tool="$PROJECT_ROOT/tools/fpsunlock"

    check_cached_compile "FPS_UNLOCK" \
        "$tool/unlocker" \
        "$tool/unlocker.c" \
        "$CACHE_DIR/unlocker.c.sha256sum"

    if [ -n "$FPS_UNLOCK_BIN" ] && [ ! -f "$FPS_UNLOCK_BIN" ] && [ -f "$FPS_UNLOCK_SRC" ]; then
        log_info gi-fps-unlock "编译 $FPS_UNLOCK_SRC"
        gcc "$FPS_UNLOCK_SRC" -o "$FPS_UNLOCK_BIN" -Wall -Wextra
    fi

    if [ ! -f "$FPS_UNLOCK_BIN" ]; then
        die 1 gi-fps-unlock "编译失败或源文件不存在"
    else
        sha256sum "$FPS_UNLOCK_SRC" | awk '{print $1}' > "$CACHE_DIR/unlocker.c.sha256sum"
    fi

    ensure_executable "$FPS_UNLOCK_BIN" gi-fps-unlock

    if [[ ! "$(getcap "$FPS_UNLOCK_BIN")" =~ cap_sys_ptrace=ep ]]; then
        sudo_request "赋予读写进程内存权限" setcap cap_sys_ptrace+ep "$FPS_UNLOCK_BIN"
    fi

    local sleep
    sleep="$(config_get gi.fps_unlock.sleep)"
    if [[ "$sleep" != "-" ]]; then
        register_hook post_start gi_fps_unlock_post_start
    else
        xwin_watch_on exists gi_fps_unlock_start
    fi

    register_hook cleanup gi_fps_unlock_cleanup
}

gi_fps_unlock_post_start() {
    local sleep
    sleep="$(config_get gi.fps_unlock.sleep)"
    log_info gi-fps-unlock "等待 $sleep 秒以确保游戏已启动"
    sleep "$sleep"
    gi_fps_unlock_start
}

gi_fps_unlock_start() {
    local pid
    local fps
    local interval
    local fifo
    local prog

    pid="$(pgrep -n -u "$USER" "$(config_get gi.fps_unlock.prog)")"
    fps="$(config_get gi.fps_unlock.val)"
    interval="$(config_get gi.fps_unlock.interval)"
    fifo="$(config_get gi.fps_unlock.fifo)"
    prog="$(config_get gi.fps_unlock.prog)"

    log_info gi-fps-unlock "PID: $pid"
    "$FPS_UNLOCK_BIN" "$pid" "$fps" "$interval" "$fifo" &
    GI_FPS_UNLOCK_PID="$!"
}

gi_fps_unlock_cleanup() {
    if [ -n "$GI_FPS_UNLOCK_PID" ]; then
        log_debug gi-fps-unlock "终止 FPS 解锁进程 $GI_FPS_UNLOCK_PID"
        kill "$GI_FPS_UNLOCK_PID" 2>/dev/null
    fi
}

# 注册表 HDR

gi_reg_hdr_load_config() {
    isy "$(config_get gi.reg_hdr.enabled)" || return 0

    config_default gi.reg_hdr.path "HKEY_CURRENT_USER\\Software\\miHoYo\\原神" >/dev/null
    config_default gi.reg_hdr.key "WINDOWS_HDR_ON_h3132281285" >/dev/null

    register_hook prepare gi_reg_hdr_prepare
}

register_hook load_config gi_reg_hdr_load_config

try_edit_prefix_reg() {
    local prefix
    local file
    local key

    prefix="$(find_wineprefix "$(config_get game.prefix)" || die 1 gi-reg-hdr "无法找到 WINEPREFIX")"
    file="$prefix/user.reg"
    key="$(config_get gi.reg_hdr.key)"

    if [ ! -f  "$file" ]; then
        log_warn gi-reg-hdr "注册表文件 $file 不存在"
        return 0
    fi

    if [ ! -r "$file" ] || [ ! -w "$file" ]; then
        die 1 gi-reg-hdr "无法读写注册表文件 $file"
    fi

    if [ "$(grep -c "$key\"=dword:" "$file")" -eq 0 ]; then
        log_warn gi-reg-hdr "注册表文件中未找到目标键值"
        return 0
    fi

    ensure_no_wineserver "$prefix" "error" "gi-reg-hdr 需要修改注册表"
    sed -i "s/\"$key\"=dword:00000000/\"$key\"=dword:00000001/g" "$file"
}

gi_reg_hdr_prepare() {
    if try_edit_prefix_reg; then
        log_info gi-reg-hdr "已设置注册表"
    else
        log_warn gi-reg-hdr "设置注册表失败，将在尝试在游戏启动前通过 wine reg 设置注册表（若第一次使用此功能，这是正常情况）"
        PREPARE_BATCH="$(cat << EOF
$PREPARE_BATCH
reg add "$(config_get gi.reg_hdr.path)" /v "$(config_get gi.reg_hdr.key)" /t REG_DWORD /d 1 /f
EOF
        )"
    fi
}

# 启动

hyps_main
