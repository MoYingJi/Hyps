#!/hint/bash

[[ -n "${__SHARED_CUSTOM_BATCH_SH_LOADED:-}" ]] && return 0
__SHARED_CUSTOM_BATCH_SH_LOADED=1

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

# cmd.exe 不识别单引号，wrapper 路径可能含空格或特殊字符，因此用双引号包裹
quote_cmd_args() {
    local arg
    for arg in "$@"; do
        printf '"%s" ' "$arg"
    done
    echo
}

gen_custom_batch() {
    local script
    local content
    local game_cwd
    local game_cwd_win
    local game_exe
    script="$(mktemp "$TEMP_DIR/start-game-XXXXXXX.bat")"
    config_read game.cwd game_cwd
    config_read game.exe game_exe
    game_cwd_win="Z:${game_cwd//\//\\}"
    content="$(cat << EOF
chcp 65001
Z:
cd /d "$game_cwd_win"
$PREPARE_BATCH
$CUSTOM_BATCH_BEFORE_GAME
start "" /WAIT /B $(quote_cmd_args "${WINE_SIDE_GAME_WRAPPER[@]}") "Z:\\$game_exe" $(quote_args "${GAME_ARGS[@]}")
$CUSTOM_BATCH_AFTER_GAME
EOF
    )"
    echo "$content" > "$script" || die 1 custom-batch "无法写入自定义批处理文件: '$script'"
    echo "$script"
}

run_prepare_batch() {
    [ -z "$PREPARE_BATCH" ] && return 0
    script="$(mktemp "$TEMP_DIR/prepare-XXXXXXX.bat")"
    content="$(cat << EOF
chcp 65001
$PREPARE_BATCH
EOF
    )"
    echo "$content" > "$script" || die 1 custom-batch "无法写入准备批处理文件: '$script'"
    local -a cmd=()
    local runner_exe
    config_read runner.exe runner_exe
    cmd+=("$runner_exe")
    cmd+=("cmd" "/c" "$script")
    log_info custom-batch "运行准备批处理脚本: $(quote_args "${cmd[@]}")"
    "${cmd[@]}" &
    local prepare_pid="$!"
    wait "$prepare_pid"
}

#shellcheck disable=SC2034
feat_custom_batch_prepare() {
    if isy "$NEEDS_CUSTOM_BATCH"; then
        if isy "$UMU_USE_STEAM"; then
            log_error custom-batch "使用自定义批处理脚本时，UMU_USE_STEAM=1 时将不起作用。请检查配置中哪里出现了问题！"
        fi

        local wrapper_arg
        for wrapper_arg in "${WINE_SIDE_GAME_WRAPPER[@]}"; do
            [[ "$wrapper_arg" == *\"* ]] && die 1 custom-batch "包装程序参数不能包含双引号: '$wrapper_arg'"
        done

        CUSTOM_BATCH_SCRIPT="$(gen_custom_batch)"
    else
        # 如果使用自定义批处理，则不再单独运行准备批处理
        run_prepare_batch
    fi
}

register_hook prepare feat_custom_batch_prepare 100
