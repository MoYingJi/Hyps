#!/usr/bin/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

#shellcheck source=../features/program_cache.sh
source "$SCRIPT_DIR/features/program_cache.sh"

help_shader_cache_list() {
    echo "  shader-cache list <游戏名>      列出游戏声明的着色器缓存，以及 Hyps 提供的 program cache"
}

help_shader_cache_invalidate() {
    echo "  shader-cache invalidate <游戏名>  清除指定游戏的着色器缓存（执行前需确认，游戏运行时拒绝执行）"
}

_shader_cache_load_game() {
    local game_name="$1"

    GAME_NAME="$game_name"
    [[ "$GAME_NAME" =~ ^[[:alnum:]_-]+$ ]] || die 1 "无效的游戏名: $GAME_NAME"

    local game_impl="$SCRIPT_DIR/games/$GAME_NAME.sh"
    if [ -f "$game_impl" ]; then
        #shellcheck source=/dev/null
        source "$game_impl"
    fi

    load_common_config
    load_game_config "$GAME_NAME"

    game_fs_init || die 1 shader-cache "初始化游戏环境失败"
    game_fs_set_phase offline || die 1 shader-cache "设置离线阶段失败"
}

_shader_cache_render_plan() {
    local rc
    SHADER_CACHE_PLAN_OK=1

    printf '游戏声明:\n'
    path_plan_collect shader-cache
    rc=$?
    case "$rc" in
        0)
            if ! path_plan_render shader-cache; then
                printf '  无法解析游戏缓存\n'
                SHADER_CACHE_PLAN_OK=0
            fi
            ;;
        3) printf '  未声明着色器缓存\n' ;;
        4) printf '  游戏未实现路径声明\n' ;;
        *)
            log_warn shader-cache "无法解析游戏声明的着色器缓存，将只处理 program cache"
            printf '  无法解析游戏缓存\n'
            SHADER_CACHE_PLAN_OK=0
            ;;
    esac

    printf '\n'
    program_cache_render
    [ "$SHADER_CACHE_PLAN_OK" -eq 1 ]
}

_shader_cache_apply_plan() {
    local plan
    local kind view path scope
    local failures=0

    plan="$(path_plan_paths shader-cache)" || return 1
    while IFS=$'\t' read -r kind view path scope; do
        [ "$kind" = "delete" ] || continue
        if ! game_fs_assert_mutation "$scope"; then
            failures=$((failures + 1))
            continue
        fi
        if [ -e "$path" ] || [ -L "$path" ]; then
            log_info shader-cache "清除游戏着色器缓存 ($view): $path"
            if ! rm -rf -- "$path"; then
                log_warn shader-cache "清除失败 ($view): $path"
                failures=$((failures + 1))
            fi
        fi
    done <<<"$plan"

    [ "$failures" -eq 0 ]
}

command_shader_cache_list() {
    [ "$#" -eq 1 ] || die 1 "用法: shader-cache list <游戏名>"

    _shader_cache_load_game "$1"
    _shader_cache_render_plan || log_warn shader-cache "游戏缓存预览不完整"
}

command_shader_cache_invalidate() {
    [ "$#" -eq 1 ] || die 1 "用法: shader-cache invalidate <游戏名>"

    _shader_cache_load_game "$1"

    # 本命令是离线操作
    game_fs_require_offline || die 1 shader-cache "overlay 挂载期间不能清除着色器缓存"

    local prefix="${GAME_FS[prefix]}"

    ensure_no_wineserver "$prefix" error "清除着色器缓存前需要先关闭游戏"

    _shader_cache_render_plan || log_warn shader-cache "游戏缓存计划不可用，继续处理 program cache"

    local answer
    read -r -p "将清除 $GAME_NAME 的着色器缓存，是否继续？[y/N] " answer || answer=""
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        log_info shader-cache "已取消"
        return 0
    fi

    # 确认期间可能有人挂载 overlay
    game_fs_require_offline || die 1 shader-cache "overlay 挂载期间不能清除着色器缓存"

    if [ "${SHADER_CACHE_PLAN_OK:-0}" = "1" ]; then
        if ! _shader_cache_apply_plan; then
            log_error shader-cache "部分游戏着色器缓存清除失败"
        fi
    fi

    feat_program_cache_invalidate

    log_info shader-cache "着色器缓存清除完成"
}
