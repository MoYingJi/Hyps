#!/hint/bash

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

overlay_auto_lower() {
    local game_exe="$1"

    case "$game_exe" in
        */"Wuthering Waves.exe") dirname "$game_exe";;
        */"Client/Binaries/Win64/Client-Win64-Shipping.exe") realpath -m "$game_exe/../../../..";;
        *) die 1 "overlay" "无法识别游戏路径: $game_exe";;
    esac
}

feat_time_record_today_reset() {
    echo "04:00 Asia/Shanghai"
}

userdata_link() {
    local game_exe="$3"

    local game_dir
    game_dir="$(overlay_auto_lower "$game_exe")" || return 1

    try_link_dir "$SCREENSHOTS/WutheringWaves" "$game_dir/Client/Saved/ScreenShot"
}

shader_cache_invalidate() {
    local game_exe="$3"

    local game_dir
    game_dir="$(overlay_auto_lower "$game_exe")" || return 1

    local cache="$game_dir/Client/Saved/PSO"
    if [ -e "$cache" ]; then
        log_info shader-cache "清除游戏着色器缓存: $cache"
        rm -rf -- "$cache"
    fi
}
