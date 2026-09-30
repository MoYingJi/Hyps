#!/usr/bin/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

#shellcheck source=../features/time_record.sh
source "$SCRIPT_DIR/features/time_record.sh"

command_time_today() {
    [ "$#" -eq 0 ] || die 1 "time today 命令不接受任何参数"

    load_common_config
    feat_time_record_load_config

    local dir day_start
    dir="$(config_get features.time_record.dir)"
    day_start="$(time_day_start)"

    local game game_name last_start last_start_time today_status

    {
        printf "%s\t%s\t%s\n" "游戏名" "最后一次启动时间" "今天 (04:00)"
        for game in "$dir"/*; do
            game_name="$(basename "$game")"
            last_start="$(time_record_last_start "$game")"
            last_start_time="$(format_time "$last_start")"

            if [ -n "$last_start" ] && [ "$last_start" -ge "$day_start" ]; then
                today_status="$(style_quote green "已启动")"
            else
                today_status="$(style_quote red "未启动")"
            fi

            printf "%s\t%s\t%s\n" "$(style_quote bright_blue "$game_name")" "$(style_quote bright_black "$last_start_time")" "$today_status"
        done
    } | column -t -s $'\t'
}

command_time_list() {
    [ "$#" -eq 0 ] || die 1 "time list 命令不接受任何参数"

    load_common_config
    feat_time_record_load_config

    local dir
    dir="$(config_get features.time_record.dir)"

    {
        printf "%s\t%s\t    %s\t  %s\n" "游戏名" "启动次数" "总游戏时长" "最后一次启动时间"

        for game in "$dir"/*; do
            game_name="$(basename "$game")"

            start_count="$(time_record_count "$game")"

            last_start="$(time_record_last_start "$game")"
            last_start_time="$(format_time "$last_start")"

            total_dur="$(time_record_total_dur "$game")"
            total_dur_formatted="$(format_dur "$total_dur")"

            printf "%s\t%s\t    %s\t  %s\n" "$(style_quote bright_blue "$game_name")" "$(style_quote cyan "$start_count")" "$total_dur_formatted" "$(style_quote bright_black "$last_start_time")"
        done
    } | column -t -s $'\t' -o '' -R 2,3
}

command_time_report() {
    [ "$#" -eq 1 ] || die 1 "time report 命令接受 1 个 game_name 参数"

    local game_name="$1"

    load_common_config
    load_game_config "$game_name"
    feat_time_record_load_config

    local dir total_dur
    dir="$(config_get features.time_record.dir)/$game_name"

    total_dur="$(time_record_total_dur "$dir")"
    last_start="$(time_record_last_start "$dir")"

    {
        printf "%s\t%s\n" "$(style_quote bright_black "游戏名")" "$(style_quote bright_blue "$game_name")"
        printf "%s\t%s\n" "$(style_quote bright_black "总时长")" "$(format_dur "$total_dur")"
        printf "%s\t%s\n" "$(style_quote bright_black "最后启动")" "$(style_quote bright_blue "$(format_time "$last_start")")"

    } | column -t -s $'\t'
}
