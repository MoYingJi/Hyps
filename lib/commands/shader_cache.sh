#!/usr/bin/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

#shellcheck source=../features/program_cache.sh
source "$SCRIPT_DIR/features/program_cache.sh"

help_shader_cache_invalidate() {
    echo "  shader-cache invalidate <游戏名>  清除指定游戏的着色器缓存（执行前需确认，游戏运行时拒绝执行）"
}

command_shader_cache_invalidate() {
    [ "$#" -eq 1 ] || die 1 "用法: shader-cache invalidate <游戏名>"

    GAME_NAME="$1"
    [[ "$GAME_NAME" =~ ^[[:alnum:]_-]+$ ]] || die 1 "无效的游戏名: $GAME_NAME"

    local game_impl="$SCRIPT_DIR/games/$GAME_NAME.sh"
    if [ -f "$game_impl" ]; then
        #shellcheck source=/dev/null
        source "$game_impl"
    fi

    load_common_config
    load_game_config "$GAME_NAME"

    # 本命令是离线操作：只解析路径，不挂载 overlay
    game_fs_init || die 1 shader-cache "初始化游戏环境失败"
    game_fs_set_phase offline || die 1 shader-cache "设置离线阶段失败"
    game_fs_require_offline || die 1 shader-cache "overlay 挂载期间不能清除着色器缓存"

    local has_game_fn=0
    if [ "$(type -t shader_cache_invalidate)" = "function" ]; then
        has_game_fn=1
    else
        log_warn shader-cache "未定义 shader_cache_invalidate 函数，跳过游戏特定的着色器缓存清除"
    fi

    local prefix="${GAME_FS[prefix]}"

    ensure_no_wineserver "$prefix" error "清除着色器缓存前需要先关闭游戏"

    local answer
    read -r -p "将清除 $GAME_NAME 的着色器缓存，是否继续？[y/N] " answer || answer=""
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        log_info shader-cache "已取消"
        return 0
    fi

    # 确认期间可能有人挂载 overlay
    game_fs_require_offline || die 1 shader-cache "overlay 挂载期间不能清除着色器缓存"

    feat_program_cache_invalidate

    if [ "$has_game_fn" -eq 1 ]; then
        if game_fs_resolve_user_dirs shader-cache; then
            shader_cache_invalidate
        else
            log_error shader-cache "解析用户目录失败，跳过游戏特定的着色器缓存清除"
        fi
    fi

    log_info shader-cache "着色器缓存清除完成"
}
