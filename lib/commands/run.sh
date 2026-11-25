#!/usr/bin/bash

help_run() {
    echo "用法: _Hyps run <游戏名>"
    echo "  使用 games/<游戏名>.conf 启动游戏"
}

command_run() {
    if [ "$#" -ne 1 ]; then
        help_run >&2
        return 1
    fi

    GAME_NAME="$1"
    #shellcheck source=../common.sh
    source "$SCRIPT_DIR/common.sh" || return $?
    hyps_main
}
