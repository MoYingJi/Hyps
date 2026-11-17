#!/hint/bash
#shellcheck disable=SC2034 # 游戏元数据由通用模块读取

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

#shellcheck source=../integrations/hyp.sh
source "$SCRIPT_DIR/integrations/hyp.sh"

# 游戏元数据

GAME_DISPLAY_NAME="崩坏：星穹铁道"
GAME_PATH_NAME="StarRail"
GAME_DAILY_RESET="04:00 Asia/Shanghai"

# 游戏安装根与可执行文件

game_install_dir() {
    local game_exe="$1"
    local game_dir
    path_dirname "$game_exe" game_dir
    printf '%s\n' "$game_dir"
}

game_executable() {
    printf '%s\n' "$1/StarRail.exe"
}

# 游戏路径声明

game_paths() {
    path_plan_declare userdata:screenshot runtime "StarRail_Data/ScreenShots"
}

# 游戏版本

game_version_local() {
    integration_hyp_get_game_version_local "$@"
}

game_version_variant_human_readable() {
    integration_hyp_variant_human_readable "$1"
}

game_version_remote() {
    integration_hyp_get_game_version_remote "starrail" "${1:-cn}"
}

game_version_predownload_remote() {
    integration_hyp_get_game_predownload_remote "starrail" "${1:-cn}"
}

# 注册表解锁帧率

starrail_reg_fps_load_config() {
    config_is_true starrail.reg_fps.enabled || return 0

    command_exists python3 || die 1 starrail-reg-fps "未安装 python3，无法注册表解锁帧率"

    config_default starrail.reg_fps.val 120

    register_hook prepare starrail_reg_fps_prepare
}

register_hook load_config starrail_reg_fps_load_config

starrail_reg_fps_prepare() {
    local prefix
    local file
    local game_prefix
    local reg_fps_val

    config_read game.prefix game_prefix
    prefix="$(find_wineprefix "$game_prefix")"
    file="$prefix/user.reg"

    if [ ! -f "$file" ]; then
        log_warn starrail-reg-fps "注册表文件 $file 不存在"
        return 0
    fi

    if [ ! -r "$file" ] || [ ! -w "$file" ]; then
        die 1 starrail-reg-fps "无法读写注册表文件 $file"
    fi

    ensure_no_wineserver "$prefix" error "'starrail.reg_fps.enabled' 已启用"

    config_read starrail.reg_fps.val reg_fps_val
    python3 "$PROJECT_ROOT/tools/starrail-fps.py" "$file" "$reg_fps_val" || {
        log_error starrail-reg-fps "注册表解锁帧率失败"
        return 0 # 仅记录错误，不影响游戏运行
    }
}
