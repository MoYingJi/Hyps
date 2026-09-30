#!/usr/bin/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

command_proton_list() {
    [ "$#" -eq 0 ] || die 1 "proton list 命令不接受任何参数"

    local path proton name

    {
        printf "%s\t%s\n" "Proton 名称" "路径"
        for path in "${_PROTON_PATHS[@]}"; do
            for proton in "$path"/*; do
                if ! [ -d "$proton" ]; then
                    log_debug "无效的 Proton 路径，不是文件夹，跳过: $proton"
                    continue
                fi

                name="$(get_proton_name "$proton")"

                if [ -z "$name" ]; then
                    log_debug "无效的 Proton 路径，无法获取名称，跳过: $proton"
                    continue
                fi

                printf "%s\t%s\n" "$(style_quote bright_blue "$name")" "$(style_quote bright_black "$proton")"
            done
        done
    } | column -t -s $'\t'
}
