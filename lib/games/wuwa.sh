#!/hint/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

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

time_record_today_reset() {
    echo "04:00 Asia/Shanghai"
}

userdata_link() {
    local target
    target="$(game_fs_write_path runtime "Client/Saved/ScreenShot")" || return 1
    try_link_dir "$SCREENSHOTS/WutheringWaves" "$target"
}

shader_cache_invalidate() {
    local view path
    local found=0

    # 离线执行，同时清 lower/upper
    while IFS=$'\t' read -r view path; do
        found=1
        if [ -e "$path" ]; then
            log_info shader-cache "清除游戏着色器缓存 ($view): $path"
            rm -rf -- "$path" || log_warn shader-cache "清除失败 ($view): $path"
        fi
    done < <(game_fs_write_paths all "Client/Saved/PSO")

    [ "$found" -eq 1 ] || log_warn shader-cache "无法解析游戏着色器缓存路径"
}
