#!/usr/bin/bash
#shellcheck source=_Lib.sh disable=2034

GAME_NAME="arknights"

if [ "$UID" -eq 0 ]; then
    echo "正在以管理员身份运行（bushi"
    echo "这只是一个公开的彩蛋罢了，不要日常使用（"
    sudo -u "$SUDO_USER" bash -c "\$(dirname \"\$(realpath \"$0\")\")/Endfield.sh"
    exit 1
fi

source _Lib.sh

start_game
