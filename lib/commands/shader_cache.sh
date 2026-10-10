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

    local game_impl="$SCRIPT_DIR/games/$GAME_NAME.sh"
    if [ -f "$game_impl" ]; then
        #shellcheck source=/dev/null
        source "$game_impl"
    fi

    load_common_config
    load_game_config "$GAME_NAME"

    local has_game_fn=0
    if [ "$(type -t shader_cache_invalidate)" = "function" ]; then
        has_game_fn=1
    else
        log_warn shader-cache "未定义 shader_cache_invalidate 函数，跳过游戏特定的着色器缓存清除"
    fi

    local prefix drive_c userprofile game_exe
    prefix="$(config_get game.prefix)"

    ensure_no_wineserver "$prefix" error "清除着色器缓存前需要先关闭游戏"

    if [ "$has_game_fn" -eq 1 ]; then
        wine_resolve_user_dirs shader-cache "$prefix" drive_c userprofile
        game_exe="$(config_get game.exe)"
    fi

    local answer
    read -r -p "将清除 $GAME_NAME 的着色器缓存，是否继续？[y/N] " answer || answer=""
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        log_info shader-cache "已取消"
        return 0
    fi

    feat_program_cache_invalidate

    if [ "$has_game_fn" -eq 1 ]; then
        shader_cache_invalidate "$drive_c" "$userprofile" "$game_exe"
    fi

    log_info shader-cache "着色器缓存清除完成"
}
