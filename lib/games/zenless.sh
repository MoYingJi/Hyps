#!/hint/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

overlay_auto_lower() {
    local game_exe="$1"
    local game_dir
    path_dirname "$game_exe" game_dir
    printf '%s\n' "$game_dir"
}

feat_time_record_today_reset() {
    echo "04:00 Asia/Shanghai"
}

userdata_link() {
    local game_exe="$3"
    local game_dir
    path_dirname "$game_exe" game_dir
    try_link_dir "$SCREENSHOTS/ZenlessZoneZero" "$game_dir/ScreenShot"
}

shader_cache_invalidate() {
    log_warn shader-cache "清除着色器缓存后，游戏并不会重新预编译着色器"
    log_warn shader-cache "需要启动游戏，在启动页（「点击进入游戏」那个界面）点击右下角四"
    log_warn shader-cache "个图标中的扳手图标，点击「确认修复」，重新触发着色器编译，见："
    log_warn shader-cache "https://www.miyoushe.com/zzz/article/76056101"
}
