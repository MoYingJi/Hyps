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

userdata_link() {
    local game_exe="$3"

    local game_dir
    game_dir="$(overlay_auto_lower "$game_exe")" || return 1

    try_link_dir "$SCREENSHOTS/WutheringWaves" "$game_dir/Client/Saved/ScreenShot"
}
