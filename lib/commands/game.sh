#!/usr/bin/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

command_game_list() {
    [ "$#" -eq 0 ] || die 1 "game list 命令不接受任何参数"

    load_common_config

    local print_no_config_game="true"

    local sh basename name exe_path basename_style name_style exe_path_style

    {
        printf "%s\t%s\t%s\n" "脚本" "游戏名" "游戏可执行文件"
        for sh in "$SCRIPTS_DIR"/*; do
            basename="$(basename "$sh")"
            [[ "$basename" == _* ]] && continue

            basename_style="green,bold"

            name="$(
                #shellcheck disable=SC1090
                source "$sh"
                #shellcheck disable=SC2153
                echo "$GAME_NAME"
            )"

            if [ -z "$name" ]; then
                name="无效"
                name_style="red"

                exe_path="无效"
                exe_path_style="red"
            else
                name_style="bright_blue"

                local has_config config_has_game_exe
                IFS=$'\t' read -r has_config config_has_game_exe exe_path <<< "$(
                    if [ ! -f "$CONFIG_DIR/games/${name}.conf" ]; then
                        echo "false"
                        return 0
                    fi

                    if log_should_output DEBUG; then
                        load_game_config "$name"
                    else
                        load_game_config "$name" 2>/dev/null
                    fi

                    printf "%s\t%s\t%s" "true" "$(bool_str config_has game.exe)" "$(config_get game.exe)"
                )"

                if [ "$has_config" = "false" ]; then
                    if [ "$print_no_config_game" = "true" ]; then
                        exe_path="未配置"
                        exe_path_style="bright_black"
                        name_style="bright_black"
                        basename_style="bright_black"
                    else
                        continue
                    fi
                elif [ "$config_has_game_exe" = "true" ]; then
                    if [ -f "$(realpath -m "$exe_path")" ]; then
                        exe_path_style="bright_black"
                    else
                        exe_path_style="red"
                    fi
                else
                    exe_path="无效"
                    exe_path_style="red"
                fi
            fi

            printf "%s\t%s\t%s\n" "$(style_quote "$basename_style" "$basename")" "$(style_quote "$name_style" "$name")" "$(style_quote "$exe_path_style" "$exe_path")"
        done
    } | column -t -s $'\t'
}
