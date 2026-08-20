#!/hint/bash

[[ -n "${__FEATURES_CUSTOM_BATCH_SH_LOADED:-}" ]] && return 0
__FEATURES_CUSTOM_BATCH_SH_LOADED=1

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

use_custom_batch() {
    if isy "$UMU_USE_STEAM" && isy "$NEEDS_CUSTOM_BATCH"; then
        log_error custom-batch "使用自定义批处理脚本时，UMU_USE_STEAM=1 时将不起作用。请检查配置中哪里出现了问题！"
    fi

    needs_custom_batch
    return $?
}

gen_custom_batch() {
    local script
    local content
    script="$(mktemp "$TEMP_DIR/start-game-XXXXXXX.bat")"
    content="$(cat << EOF
chcp 65001
Z:
$PREPARE_BATCH
$CUSTOM_BATCH_BEFORE_GAME
start "" $(quote_args "${WINE_SIDE_GAME_WRAPPER[@]}") "Z:\\$(config_get game.exe)" $(quote_args "${GAME_ARGS[@]}")
$CUSTOM_BATCH_AFTER_GAME
EOF
    )"
    echo "$content" > "$script" || die 1 custom-batch "无法写入自定义批处理文件: '$script'"
    echo "$script"
}

run_prepare_batch() {
    isy "$NEEDS_CUSTOM_BATCH" && return 0 # 如果使用自定义批处理，则不再单独运行准备批处理
    [ -z "$PREPARE_BATCH" ] && return 0
    script="$(mktemp "$TEMP_DIR/prepare-XXXXXXX.bat")"
    content="$(cat << EOF
chcp 65001
$PREPARE_BATCH
EOF
    )"
    echo "$content" > "$script" || die 1 custom-batch "无法写入准备批处理文件: '$script'"
    local -a cmd=()
    cmd+=("$(config_get runner.exe)")
    cmd+=("$script")
    log_info custom-batch "运行准备批处理脚本: $(quote_args "${cmd[@]}")"
    "${cmd[@]}" &
    local prepare_pid="$!"
    wait "$prepare_pid"
}


feat_custom_batch_prepare() {
    run_prepare_batch
}

#shellcheck disable=SC2034
feat_custom_batch_pre_start() {
    if isy "$NEEDS_CUSTOM_BATCH"; then
        CUSTOM_BATCH_SCRIPT="$(gen_custom_batch)"
    fi
}

register_hook prepare feat_custom_batch_prepare 100
register_hook pre_start feat_custom_batch_pre_start 100
