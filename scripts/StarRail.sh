#!/usr/bin/bash
#shellcheck disable=2034

GAME_NAME="starrail"

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
    try_link_dir "$SCREENSHOTS/StarRail" "$(dirname "$game_exe")/StarRail_Data/ScreenShots"
}

# 注册表解锁帧率

starrail_reg_fps_load_config() {
    isy "$(config_get starrail.reg_fps.enabled)" || return 0

    command_exists python3 || die 1 starrail-reg-fps "未安装 python3，无法注册表解锁帧率"

    config_default starrail.reg_fps.val 120 >/dev/null

    register_hook prepare starrail_reg_fps_prepare
}

register_hook load_config starrail_reg_fps_load_config

starrail_reg_fps_prepare() {
    local prefix
    local file

    prefix="$(find_wineprefix "$(config_get game.prefix)")"
    file="$prefix/user.reg"

    if [ ! -f "$file" ]; then
        log_warn starrail-reg-fps "注册表文件 $file 不存在"
        return 0
    fi

    if [ ! -r "$file" ] || [ ! -w "$file" ]; then
        die 1 starrail-reg-fps "无法读写注册表文件 $file"
    fi

    ensure_no_wineserver "$prefix" error "'starrail.reg_fps.enabled' 已启用"

    python3 "$PROJECT_ROOT/tools/starrail-fps.py" "$file" "$(config_get starrail.reg_fps.val)" || {
        log_error starrail-reg-fps "注册表解锁帧率失败"
        return 0 # 仅记录错误，不影响游戏运行
    }
}

hyps_main
