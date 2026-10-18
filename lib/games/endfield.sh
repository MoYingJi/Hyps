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

# 鹰角通用替身父进程工具（详见 tools/gryph-surrogate/gryph-surrogate.c 头部注释）

GRYPH_SURROGATE_TOOL="$PROJECT_ROOT/tools/gryph-surrogate"
GRYPH_SURROGATE_DEFAULT_CC="x86_64-w64-mingw32-gcc"
GRYPH_SURROGATE_FLAGS=(-std=gnu23 -municode -mwindows -static)

gryph_surrogate_exe_path() {
    cache_bin_path gryph-surrogate.exe
}

endfield_surrogate_launcher_validate_path() {
    local launcher_path="$1"
    local filename

    launcher_path="$(realpath -m -- "$launcher_path")"
    filename="${launcher_path##*/}"
    if [[ -d "$launcher_path" ]]; then
        printf '%s\n' "$launcher_path"
    elif [[ -f "$launcher_path" && "${filename,,}" == *.exe ]]; then
        printf '%s\n' "$launcher_path"
    else
        die 1 config "配置项 'endfield.surrogate.mode = launcher' 时 'endfield.surrogate.launcher' 必须是启动器目录或 exe 文件：'$launcher_path'"
    fi
}

endfield_surrogate_validate_file() {
    local file_path="$1"
    local filename

    file_path="$(realpath -m -- "$file_path")"
    filename="${file_path##*/}"
    if [[ -f "$file_path" && "${filename,,}" == *.exe ]]; then
        printf '%s\n' "$file_path"
    else
        die 1 config "配置项 'endfield.surrogate.launcher' 必须是已有签名的 exe 文件：'$file_path'"
    fi
}

endfield_surrogate_add_exit_after() {
    local -n _exit_after_args=$1
    local exit_after
    config_read endfield.surrogate.exit_after exit_after
    [[ $exit_after =~ ^[1-9][0-9]*$ ]] \
        || die 1 config "配置项 'endfield.surrogate.exit_after' 必须是正整数秒数：'$exit_after'"
    _exit_after_args+=(--launcher-exit-after "$((exit_after * 1000))")
}

feat_endfield_surrogate_load_config() {
    local surrogate_mode
    local surrogate_src=""
    local surrogate_dir=""
    local launcher_path
    local -a surrogate_args=("$(gryph_surrogate_exe_path)")

    if ! config_has endfield.surrogate.mode; then
        for key in launcher dir keep exit_after show_info; do
            if config_has "endfield.surrogate.$key"; then
                die 1 config "配置 'endfield.surrogate.$key' 时，必须显式设置 'endfield.surrogate.mode'"
            fi
        done
        return 0
    fi

    config_read endfield.surrogate.mode surrogate_mode
    case "$surrogate_mode" in
        launcher)
            for key in keep dir; do
                if config_has "endfield.surrogate.$key"; then
                    die 1 config "配置项 'endfield.surrogate.$key' 只能用于替身模式，不能和 'endfield.surrogate.mode = launcher' 一起使用"
                fi
            done

            if ! config_has endfield.surrogate.launcher; then
                die 1 config "'endfield.surrogate.mode = launcher' 时必须设置 'endfield.surrogate.launcher'"
            fi

            config_read endfield.surrogate.launcher launcher_path
            launcher_path="$(endfield_surrogate_launcher_validate_path "$launcher_path")" || return 1
            config_set endfield.surrogate.launcher "$launcher_path"
            surrogate_args+=(--launcher "$(wine_unix_path_to_windows "$launcher_path")")
            ;;
        hardlink | copy | hardlink-or-copy)
            if config_has endfield.surrogate.launcher; then
                # 可选: 显式指定替身源文件 (默认游戏 exe 自身) 对应 CLI 的 --launcher
                config_read endfield.surrogate.launcher surrogate_src
                surrogate_src="$(endfield_surrogate_validate_file "$surrogate_src")" || return 1
                surrogate_args+=(--launcher "$(wine_unix_path_to_windows "$surrogate_src")")
            fi

            if config_has endfield.surrogate.dir; then
                # 可选: 显式指定替身目标目录 (文件名固定 Games.exe 以命中游戏侧校验)
                config_read endfield.surrogate.dir surrogate_dir
                surrogate_dir="$(realpath -m -- "$surrogate_dir")"
                mkdir -p -- "$surrogate_dir" \
                    || die 1 config "配置项 'endfield.surrogate.dir' 所指目录无法创建：'$surrogate_dir'"
                surrogate_args+=(--target "$(wine_unix_path_to_windows "$surrogate_dir")\Games.exe")
            fi

            if config_is_true endfield.surrogate.keep; then
                # 可选: 游戏退出后保留替身文件和新建的目录，默认删除
                surrogate_args+=(--keep-surrogate)
            fi
            ;;
        *) die 1 config "配置项 'endfield.surrogate.mode' 只能是 launcher / hardlink / copy / hardlink-or-copy：'$surrogate_mode'" ;;
    esac

    if config_has endfield.surrogate.exit_after; then
        endfield_surrogate_add_exit_after surrogate_args
    fi

    if config_is_true endfield.surrogate.show_info; then
        # 可选: 通过信息框显示替身的 info 日志
        surrogate_args+=(--show-info)
    fi

    surrogate_args+=(--mode "$surrogate_mode")
    WINE_SIDE_OUTER_WRAPPER+=("${surrogate_args[@]}")
    register_hook prepare feat_endfield_surrogate_prepare
}

gryph_surrogate_all_source() {
    cat "$GRYPH_SURROGATE_TOOL/gryph-surrogate.c"
    echo
    local -a flags=("${GRYPH_SURROGATE_FLAGS[@]}" "${HYPS_MINGW_CFLAGS[@]}")
    printf '%s %s\n' "${HYPS_WIN_CC:-$GRYPH_SURROGATE_DEFAULT_CC}" "$(quote_args "${flags[@]}")"
}

gryph_surrogate_verify_output() {
    [ -f "$1" ]
}

gryph_surrogate_compile() {
    local output="$1"
    local cc="${HYPS_WIN_CC:-$GRYPH_SURROGATE_DEFAULT_CC}"
    local -a flags=("${GRYPH_SURROGATE_FLAGS[@]}" "${HYPS_MINGW_CFLAGS[@]}")

    if ! command -v "$cc" > /dev/null 2>&1; then
        log_error gryph-surrogate "未找到 Windows 交叉编译器 '$cc'，请检查 compile.mingw.CC 配置或安装 mingw-w64"
        return 1
    fi

    mkdir -p "$(dirname "$output")" || return 1
    run_and_log DEBUG gryph-surrogate "编译命令" \
        "$cc" "${flags[@]}" \
        -o "$output" "$GRYPH_SURROGATE_TOOL/gryph-surrogate.c" \
        || return 1
}

feat_endfield_surrogate_prepare() {
    check_cache_and_compile "gryph-surrogate" \
        "$(gryph_surrogate_exe_path)" \
        gryph_surrogate_all_source \
        gryph_surrogate_verify_output \
        gryph_surrogate_compile
}

register_hook load_config feat_endfield_surrogate_load_config
