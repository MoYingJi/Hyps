#!/hint/bash
#shellcheck disable=SC2034 # 游戏元数据由通用模块读取

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

# 游戏元数据

GAME_DISPLAY_NAME="鸣潮"
GAME_PATH_NAME="WutheringWaves"
GAME_DAILY_RESET="04:00 Asia/Shanghai"

# 游戏安装根与可执行文件

game_install_dir() {
    local game_exe="$1"
    local game_dir
    case "$game_exe" in
        */"Wuthering Waves.exe")
            path_dirname "$game_exe" game_dir
            printf '%s\n' "$game_dir"
            ;;
        */"Client/Binaries/Win64/Client-Win64-Shipping.exe")
            realpath -m "$game_exe/../../../.."
            ;;
        *)
            log_error game-fs "无法识别游戏路径: $game_exe"
            return 1
            ;;
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
