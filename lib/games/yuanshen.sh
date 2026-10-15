#!/hint/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

#shellcheck source=../shared/xwin_watch.sh
source "$SCRIPT_DIR/shared/xwin_watch.sh"

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
    local game_exe="$3"
    local game_dir
    path_dirname "$game_exe" game_dir
    try_link_dir "$SCREENSHOTS/YuanShen" "$game_dir/ScreenShot"
}

# 着色器缓存

shader_cache_invalidate() {
    local userprofile="$2"
    local dir

    # 国服目录为 原神，国际服目录为 Genshin Impact（后者未经本机验证），两者都尝试清除
    for dir in "原神" "Genshin Impact"; do
        local cache="$userprofile/AppData/LocalLow/miHoYo/$dir/d3d12PSOcache"
        if [ -e "$cache" ]; then
            log_info shader-cache "清除游戏着色器缓存: $cache"
            rm -rf -- "$cache"
        fi
    done
}

# FPS 解锁

GI_FPS_UNLOCK_TOOL="$PROJECT_ROOT/tools/fpsunlock"

gi_fps_unlock_load_config() {
    config_is_true gi.fps_unlock.enabled || return 0

    config_default gi.fps_unlock.val 120
    config_default gi.fps_unlock.interval 5000
    config_default gi.fps_unlock.fifo "$TEMP_DIR/fpsunlock_fifo"
    config_default gi.fps_unlock.prog "YuanShen.exe"
    config_default gi.fps_unlock.sleep "-"

    local sleep
    config_read gi.fps_unlock.sleep sleep
    if [[ "$sleep" != "-" ]]; then
        if ! [[ "$sleep" =~ ^[0-9]+$ ]]; then
            die 1 gi-fps-unlock "gi.fps_unlock.sleep 必须是整数或 '-'"
        fi
    else
        config_set features.xwin_watch.enabled true
    fi

    register_hook prepare gi_fps_unlock_prepare
}

register_hook load_config gi_fps_unlock_load_config 50 before:feat_xwin_watch_load_config

gi_fps_unlock_all_source() {
    local line
    while IFS= read -r line; do
        printf '%s\n' "$line"
    done < "$GI_FPS_UNLOCK_TOOL/unlocker.c"
    [[ -n "$line" ]] && printf '%s' "$line"
    echo "${HYPS_CFLAGS[@]:-}"
}
gi_fps_unlock_verify_output() {
    local bin="$1"
    [ -f "$bin" ] || return 1
    [ -x "$bin" ] || return 1
    [[ "$(getcap "$bin")" =~ cap_sys_ptrace=ep ]] || return 1
}
gi_fps_unlock_compile() {
    local output="$1"
    local cc="${HYPS_CC:-gcc}"
    run_and_log DEBUG gi-fps-unlock "编译命令" \
        "$cc" ${HYPS_CFLAGS[@]+"${HYPS_CFLAGS[@]}"} "$GI_FPS_UNLOCK_TOOL/unlocker.c" -o "$output" \
        || return 1
    ensure_executable "$output" gi-fps-unlock
    sudo_request "赋予读写进程内存权限" setcap cap_sys_ptrace+ep "$output"
}

gi_fps_unlock_prepare() {
    local bin="$GI_FPS_UNLOCK_TOOL/unlocker"

    check_cache_and_compile "fpsunlock" \
        "$bin" \
        gi_fps_unlock_all_source \
        gi_fps_unlock_verify_output \
        gi_fps_unlock_compile

    local sleep
    config_read gi.fps_unlock.sleep sleep
    if [[ "$sleep" != "-" ]]; then
        register_hook post_start gi_fps_unlock_post_start
    else
        xwin_watch_on exists gi_fps_unlock_start
    fi
}

gi_fps_unlock_post_start() {
    local sleep
    config_read gi.fps_unlock.sleep sleep
    log_info gi-fps-unlock "等待 $sleep 秒以确保游戏已启动"
    sleep "$sleep"
    gi_fps_unlock_start
}

gi_fps_unlock_start() {
    local bin="$GI_FPS_UNLOCK_TOOL/unlocker"
    local prog fps interval fifo pid

    config_read gi.fps_unlock.prog prog
    config_read gi.fps_unlock.val fps
    config_read gi.fps_unlock.interval interval
    config_read gi.fps_unlock.fifo fifo

    pid="$(find_pid_by_name -n "$prog")"

    log_info gi-fps-unlock "PID: $pid"
    "$bin" "$pid" "$fps" "$interval" "$fifo" &
}

# 注册表 HDR

gi_reg_hdr_load_config() {
    config_is_true gi.reg_hdr.enabled || return 0

    config_default gi.reg_hdr.path "HKEY_CURRENT_USER\\Software\\miHoYo\\原神"
    config_default gi.reg_hdr.key "WINDOWS_HDR_ON_h3132281285"

    register_hook prepare gi_reg_hdr_prepare
}

register_hook load_config gi_reg_hdr_load_config

try_edit_prefix_reg() {
    local prefix file key game_prefix

    config_read game.prefix game_prefix
    prefix="$(find_wineprefix "$game_prefix" || die 1 gi-reg-hdr "无法找到 WINEPREFIX")"
    file="$prefix/user.reg"
    config_read gi.reg_hdr.key key

    if [ ! -f  "$file" ]; then
        log_warn gi-reg-hdr "注册表文件 $file 不存在"
        return 0
    fi

    if [ ! -r "$file" ] || [ ! -w "$file" ]; then
        die 1 gi-reg-hdr "无法读写注册表文件 $file"
    fi

    if [ "$(grep -c "$key\"=dword:" "$file")" -eq 0 ]; then
        log_warn gi-reg-hdr "注册表文件中未找到目标键值"
        return 0
    fi

    ensure_no_wineserver "$prefix" "error" "gi-reg-hdr 需要修改注册表"
    sed -i "s/\"$key\"=dword:00000000/\"$key\"=dword:00000001/g" "$file"
}

gi_reg_hdr_prepare() {
    if try_edit_prefix_reg; then
        log_info gi-reg-hdr "已设置注册表"
    else
        log_warn gi-reg-hdr "设置注册表失败，将在尝试在游戏启动前通过 wine reg 设置注册表（若第一次使用此功能，这是正常情况）"
        local reg_path reg_key
        config_read gi.reg_hdr.path reg_path
        config_read gi.reg_hdr.key reg_key
        WINE_SIDE_PREPARE_BATCH="$(cat << EOF
$WINE_SIDE_PREPARE_BATCH
reg add "$reg_path" /v "$reg_key" /t REG_DWORD /d 1 /f
EOF
        )"
    fi
}

# 强制 D3D12

gi_patch_d3d12_load_config() {
    config_is_true gi.patch_d3d12.enabled || return 0

    # unitypy: 使用 UnityPy 重新序列化文件（默认）
    # bytes:   仅标准库，只改写 m_GraphicsAPIs 的 4 字节
    config_read gi.patch_d3d12.impl GI_PATCH_D3D12_IMPL unitypy
    case "$GI_PATCH_D3D12_IMPL" in
        unitypy) GI_PATCH_D3D12_PATCHER="patch-unitypy.py" ;;
        bytes) GI_PATCH_D3D12_PATCHER="patch-bytes.py" ;;
        *) die 1 gi-patch-d3d12 "未知的 gi.patch_d3d12.impl: $GI_PATCH_D3D12_IMPL（可选 unitypy 或 bytes）" ;;
    esac

    register_hook prepare gi_patch_d3d12_prepare
}

register_hook load_config gi_patch_d3d12_load_config

gi_patch_d3d12_prepare() {
    GI_PATCH_D3D12_MODE="" # overlay | in-place
    GI_PATCH_D3D12_TARGET_GGM="" # 本次运行中已替换的 globalgamemanagers，为空表示未替换

    local game game_dir data_dir ggm_path ggm_remote_path overlay_upper

    if config_is_true overlay.enabled; then
        GI_PATCH_D3D12_MODE="overlay"
        game="$OVERLAY_ORIGINAL_GAME"
        config_read overlay.upper overlay_upper
    else
        log_warn gi-patch-d3d12 "当前未开启 overlay，使用 in-place 模式！"
        GI_PATCH_D3D12_MODE="in-place"
        config_read game.exe game
    fi

    path_dirname "$game" game_dir

    for data_dir in "YuanShen_Data" "GenshinImpact_Data"; do
        if [ -d "$game_dir/$data_dir" ]; then
            ggm_path="$game_dir/$data_dir/globalgamemanagers"
            ggm_remote_path="$data_dir/globalgamemanagers"
            [ -f "$ggm_path" ] || die 1 gi-patch-d3d12 "未找到 globalgamemanagers 文件"
            break
        fi
    done
    [ -z "$ggm_path" ] && die 1 gi-patch-d3d12 "未找到 YuanShen_Data 或 GenshinImpact_Data 文件夹"

    local pkg_version_file="$game_dir/pkg_version"
    [ -f "$pkg_version_file" ] || die 1 gi-patch-d3d12 "未找到 pkg_version 文件"

    #shellcheck disable=SC2153
    local cache_dir="$CACHE_DIR/gi-patch-d3d12"
    mkdir -p "$cache_dir" || die 1 gi-patch-d3d12 "无法创建缓存目录 $cache_dir"

    local cached_ggm_official="$cache_dir/globalgamemanagers_official"
    local cached_ggm_temp="$cache_dir/globalgamemanagers_temp"
    local cached_ggm_patched="$cache_dir/globalgamemanagers_patched"
    local cached_patcher_key="$cache_dir/patcher_key"
    local applied_marker="$cache_dir/applied"
    local patcher_file="$PROJECT_ROOT/tools/genshin-d3d12/$GI_PATCH_D3D12_PATCHER"

    # 上次异常退出可能遗留了补丁，必须先恢复，否则下面的校验会因 md5 不符而拒绝启动
    gi_patch_d3d12_recover "$applied_marker" "$cached_ggm_official"

    verify_file_with_pkg_version "$pkg_version_file" "$ggm_remote_path" "$ggm_path" \
        || die 1 gi-patch-d3d12 "globalgamemanagers 文件校验失败，拒绝执行"

    local patcher_key cached_key=""
    patcher_key="$(md5sum "$patcher_file")" || die 1 gi-patch-d3d12 "无法读取补丁脚本: $patcher_file"
    patcher_key="${patcher_key%% *}"
    [ -f "$cached_patcher_key" ] && cached_key="$(cat "$cached_patcher_key")"

    if [ ! -f "$cached_ggm_official" ] || [ ! -f "$cached_ggm_patched" ] \
        || [ "$cached_key" != "$patcher_key" ] || ! cmp -s "$ggm_path" "$cached_ggm_official"; then
        log_info gi-patch-d3d12 "缓存已失效（游戏文件或补丁脚本已变化），将更新缓存"
        # 先删除旧缓存，避免失败后误用与当前版本不一致的文件
        rm -f "$cached_ggm_patched" "$cached_ggm_temp" "$cached_patcher_key"
        cp "$ggm_path" "$cached_ggm_official" || die 1 gi-patch-d3d12 "无法更新缓存的 globalgamemanagers_official 文件"
        pushd "$PROJECT_ROOT/tools/genshin-d3d12" >/dev/null || die 1 gi-patch-d3d12 "无法进入工具目录"
        cp "$cached_ggm_official" "$cached_ggm_temp" || die 1 gi-patch-d3d12 "无法创建临时缓存文件"
        if [ "$GI_PATCH_D3D12_IMPL" = "bytes" ]; then
            command_exists python3 || die 1 gi-patch-d3d12 "bytes 实现需要 python3"
            python3 "$GI_PATCH_D3D12_PATCHER" "$cached_ggm_temp" --mode d3d12 || die 1 gi-patch-d3d12 "使用 bytes 实现更新缓存失败"
        elif command_exists uv; then
            # 只使用系统解释器：uv 默认可能选中 free-threaded 版 Python，而 UnityPy 的依赖 astc-encoder-py 在其上无法安装
            uv run --no-managed-python "$GI_PATCH_D3D12_PATCHER" "$cached_ggm_temp" --mode d3d12 || die 1 gi-patch-d3d12 "使用 uv 更新缓存失败"
        elif command_exists python3 && python3 -c "import UnityPy" 2>/dev/null; then
            log_debug gi-patch-d3d12 "未找到 uv，使用已安装 UnityPy 的系统 Python"
            python3 "$GI_PATCH_D3D12_PATCHER" "$cached_ggm_temp" --mode d3d12 || die 1 gi-patch-d3d12 "使用系统 Python 更新缓存失败"
        else
            die 1 gi-patch-d3d12 "更新缓存需要 uv，或已安装 UnityPy 的 python3，请先安装 uv"
        fi
        mv "$cached_ggm_temp" "$cached_ggm_patched" || die 1 gi-patch-d3d12 "无法更新缓存的 globalgamemanagers_patched 文件"
        printf '%s\n' "$patcher_key" > "$cached_patcher_key" || die 1 gi-patch-d3d12 "无法写入补丁脚本版本记录"
        popd >/dev/null || die 1 gi-patch-d3d12 "无法返回原目录"
    fi

    [ -f "$cached_ggm_patched" ] || die 1 gi-patch-d3d12 "缓存的 globalgamemanagers_patched 文件不存在"

    local target_ggm target_dir
    if [ "$GI_PATCH_D3D12_MODE" = "overlay" ]; then
        local ggm_rel_path overlay_lower
        config_read overlay.lower overlay_lower
        ggm_rel_path="$(realpath --relative-to="$overlay_lower" "$ggm_path")"
        target_ggm="$overlay_upper/$ggm_rel_path"
        [ -f "$target_ggm" ] && die 1 gi-patch-d3d12 "目标 globalgamemanagers 文件已存在: $target_ggm"
        path_dirname "$target_ggm" target_dir
        mkdir -p "$target_dir" || die 1 gi-patch-d3d12 "无法创建 overlay 目标目录: $target_dir"
    elif [ "$GI_PATCH_D3D12_MODE" = "in-place" ]; then
        target_ggm="$ggm_path"
    else
        die 1 gi-patch-d3d12 "未知的 GI_PATCH_D3D12_MODE 模式: $GI_PATCH_D3D12_MODE"
    fi

    # 先登记 cleanup 并写入标记，再替换文件：替换中途失败也能被还原
    GI_PATCH_D3D12_TARGET_GGM="$target_ggm"
    register_hook cleanup gi_patch_d3d12_cleanup

    local patched_md5
    patched_md5="$(md5sum "$cached_ggm_patched")" || die 1 gi-patch-d3d12 "无法计算缓存文件 md5"
    printf '%s\t%s\t%s\n' "$GI_PATCH_D3D12_MODE" "$target_ggm" "${patched_md5%% *}" > "$applied_marker" \
        || die 1 gi-patch-d3d12 "无法写入补丁状态记录: $applied_marker"

    cp "$cached_ggm_patched" "$target_ggm" || die 1 gi-patch-d3d12 "无法将缓存的 globalgamemanagers_patched 文件复制到目标位置"
}

# 恢复上次异常退出遗留的补丁状态。只处理标记文件记录的路径，且 in-place 仅在文件仍是我们写入的补丁版本时才还原。
gi_patch_d3d12_recover() {
    local marker="$1"
    local cached_ggm_official="$2"

    [ -f "$marker" ] || return 0

    local prev_mode prev_target prev_md5
    IFS=$'\t' read -r prev_mode prev_target prev_md5 < "$marker" || true

    case "$prev_mode" in
        overlay)
            log_warn gi-patch-d3d12 "删除上次遗留的 overlay 文件: $prev_target"
            rm -f "$prev_target" || die 1 gi-patch-d3d12 "无法删除上次遗留的 overlay 文件: $prev_target"
            ;;
        in-place)
            local current_md5=""
            if [ -f "$prev_target" ]; then
                current_md5="$(md5sum "$prev_target")"
                current_md5="${current_md5%% *}"
            fi
            if [ "$current_md5" = "$prev_md5" ]; then
                log_warn gi-patch-d3d12 "检测到上次异常退出遗留的补丁，正在还原: $prev_target"
                [ -f "$cached_ggm_official" ] || die 1 gi-patch-d3d12 "缓存的官方 globalgamemanagers 文件不存在，无法还原: $cached_ggm_official"
                cp "$cached_ggm_official" "$prev_target" || die 1 gi-patch-d3d12 "无法还原上次遗留的补丁: $prev_target"
            else
                log_warn gi-patch-d3d12 "上次记录的补丁文件已变化，跳过还原: $prev_target"
            fi
            ;;
        *)
            log_warn gi-patch-d3d12 "无法识别的补丁状态记录，已忽略: $prev_mode"
            ;;
    esac

    rm -f "$marker"
}

gi_patch_d3d12_cleanup() {
    [ -n "$GI_PATCH_D3D12_TARGET_GGM" ] || return 0

    local marker="$CACHE_DIR/gi-patch-d3d12/applied"
    local cached_ggm_official="$CACHE_DIR/gi-patch-d3d12/globalgamemanagers_official"

    if [ "$GI_PATCH_D3D12_MODE" = "overlay" ]; then
        rm -f "$GI_PATCH_D3D12_TARGET_GGM" || { log_error gi-patch-d3d12 "无法删除 overlay 文件，下次启动时将自动清理: $GI_PATCH_D3D12_TARGET_GGM"; return 0; }
    elif [ "$GI_PATCH_D3D12_MODE" = "in-place" ]; then
        if [ ! -f "$cached_ggm_official" ]; then
            log_error gi-patch-d3d12 "缓存的官方 globalgamemanagers 文件不存在，无法还原: $GI_PATCH_D3D12_TARGET_GGM"
            return 0
        fi
        cp "$cached_ggm_official" "$GI_PATCH_D3D12_TARGET_GGM" || { log_error gi-patch-d3d12 "无法还原 globalgamemanagers，下次启动时将自动还原: $GI_PATCH_D3D12_TARGET_GGM"; return 0; }
    else
        log_error gi-patch-d3d12 "未知的 GI_PATCH_D3D12_MODE 模式: $GI_PATCH_D3D12_MODE"
        return 0
    fi

    rm -f "$marker"
}
