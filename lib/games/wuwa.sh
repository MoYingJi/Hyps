#!/hint/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

# 游戏元数据

game_display_name() {
    printf '%s\n' "鸣潮"
}

game_path_name() {
    printf '%s\n' "WutheringWaves"
}

# 游戏安装根与可执行文件

game_install_dir() {
    local game_exe="$1"
    local game_dir
    case "$game_exe" in
        */"Wuthering Waves.exe")
            path_dirname "$game_exe" game_dir
            printf '%s\n' "$game_dir"
            ;;
        */"Client/Binaries/Win64/Client-Win64-Shipping.exe") realpath -m "$game_exe/../../../..";;
        *) die 1 "overlay" "无法识别游戏路径: $game_exe";;
    esac
}

game_executable() {
    local install_dir="$1"
    printf '%s\n' "$install_dir/Client/Binaries/Win64/Client-Win64-Shipping.exe"
}

# 游戏路径声明

game_paths() {
    path_plan_declare userdata:screenshot runtime "Client/Saved/ScreenShot"
    path_plan_declare shader-cache all "Client/Saved/PSO"
}

# 日常重置时间

time_record_today_reset() {
    echo "04:00 Asia/Shanghai"
}
