#!/hint/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

# Overlay

overlay_auto_lower() {
    local game_exe="$1"
    local game_dir
    path_dirname "$game_exe" game_dir
    printf '%s\n' "$game_dir"
}

# 日常重置时间

feat_time_record_today_reset() {
    echo "04:00 Asia/Shanghai"
}

# 用户数据链接

userdata_link() {
    local userprofile="$2"
    try_link_dir "$SCREENSHOTS/Endfield" "$userprofile/Pictures/ENDFIELD"
}

# 着色器缓存

shader_cache_invalidate() {
    local userprofile="$2"
    local dir file

    # 国服目录为 Hypergryph，国际服目录为 Gryphline（后者未经本机验证），两者都尝试清除
    for dir in "Hypergryph" "Gryphline"; do
        for file in vulkan_pso_cache.bin dx11_pso_cache.bin; do
            local cache="$userprofile/AppData/LocalLow/$dir/Endfield/$file"
            if [ -e "$cache" ]; then
                log_info shader-cache "清除游戏着色器缓存: $cache"
                rm -f -- "$cache"
            fi
        done
    done
}

# 终末地启动器

ENDFIELD_LAUNCHER_TOOL="$PROJECT_ROOT/tools/endfield-launcher"
ENDFIELD_LAUNCHER_DEFAULT_CC="x86_64-w64-mingw32-gcc"
ENDFIELD_LAUNCHER_FLAGS=(-std=gnu23 -municode -mwindows -static)

endfield_launcher_exe_path() {
    cache_bin_path endfield-launcher.exe
}

endfield_launcher_validate_path() {
    local launcher_path="$1"
    local filename

    launcher_path="$(realpath -m -- "$launcher_path")"
    filename="${launcher_path##*/}"
    if [[ -d "$launcher_path" ]]; then
        printf '%s\n' "$launcher_path"
    elif [[ -f "$launcher_path" && "${filename,,}" == *.exe ]]; then
        printf '%s\n' "$launcher_path"
    else
        die 1 config "配置项 'endfield.launcher' 必须是启动器目录或 exe 文件：'$launcher_path'"
    fi
}

feat_endfield_launcher_load_config() {
    config_has endfield.launcher || return 0

    local launcher_linux launcher_win
    config_read endfield.launcher launcher_linux
    launcher_linux="$(endfield_launcher_validate_path "$launcher_linux")" || return 1
    config_set endfield.launcher "$launcher_linux"
    launcher_win="$(wine_unix_path_to_windows "$launcher_linux")"

    WINE_SIDE_OUTER_WRAPPER+=("$(endfield_launcher_exe_path)" "$launcher_win")

    register_hook prepare feat_endfield_launcher_prepare
}

endfield_launcher_all_source() {
    cat "$ENDFIELD_LAUNCHER_TOOL/endfield-launcher.c"
    echo
    local -a flags=("${ENDFIELD_LAUNCHER_FLAGS[@]}" "${HYPS_MINGW_CFLAGS[@]}")
    printf '%s %s\n' "${HYPS_WIN_CC:-$ENDFIELD_LAUNCHER_DEFAULT_CC}" "$(quote_args "${flags[@]}")"
}

endfield_launcher_verify_output() {
    [ -f "$1" ]
}

endfield_launcher_compile() {
    local output="$1"
    local cc="${HYPS_WIN_CC:-$ENDFIELD_LAUNCHER_DEFAULT_CC}"
    local -a flags=("${ENDFIELD_LAUNCHER_FLAGS[@]}" "${HYPS_MINGW_CFLAGS[@]}" "-std=gnu23")

    if ! command -v "$cc" > /dev/null 2>&1; then
        log_error endfield-launcher "未找到 Windows 交叉编译器 '$cc'，请检查 compile.mingw.CC 配置或安装 mingw-w64"
        return 1
    fi

    mkdir -p "$(dirname "$output")" || return 1
    run_and_log DEBUG endfield-launcher "编译命令" \
        "$cc" "${flags[@]}" \
        -o "$output" "$ENDFIELD_LAUNCHER_TOOL/endfield-launcher.c" \
        || return 1
}

feat_endfield_launcher_prepare() {
    check_cache_and_compile "endfield-launcher" \
        "$(endfield_launcher_exe_path)" \
        endfield_launcher_all_source \
        endfield_launcher_verify_output \
        endfield_launcher_compile
}

register_hook load_config feat_endfield_launcher_load_config
