#!/hint/bash
#shellcheck disable=SC2034 # 游戏元数据由通用模块读取

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

#shellcheck source=../integrations/hyp.sh
source "$SCRIPT_DIR/integrations/hyp.sh"

# 游戏元数据

GAME_DISPLAY_NAME="绝区零"
GAME_PATH_NAME="ZenlessZoneZero"
GAME_DAILY_RESET="04:00 Asia/Shanghai"

# 游戏安装根与可执行文件

game_install_dir() {
    local game_exe="$1"
    local game_dir
    path_dirname "$game_exe" game_dir
    printf '%s\n' "$game_dir"
}

game_executable() {
    printf '%s\n' "$1/ZenlessZoneZero.exe"
}

# 游戏路径声明

game_paths() {
    path_plan_declare userdata:screenshot runtime "ScreenShot"
    path_plan_note shader-cache "清除着色器缓存后，游戏并不会重新预编译着色器"
    path_plan_note shader-cache "需要启动游戏，在启动页（「点击进入游戏」那个界面）点击右下角四"
    path_plan_note shader-cache "个图标中的扳手图标，点击「确认修复」，重新触发着色器编译，见："
    path_plan_note shader-cache "https://www.miyoushe.com/zzz/article/76056101"
}

# 游戏版本

game_version_local() {
    integration_hyp_get_game_version_local "$@"
}

game_version_variant_human_readable() {
    integration_hyp_variant_human_readable "$1"
}

game_version_remote() {
    integration_hyp_get_game_version_remote "zenless" "${1:-cn}" "$2" "$3" "$4"
}
