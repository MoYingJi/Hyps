#!/usr/bin/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

#shellcheck source=../features/time_record.sh
source "$SCRIPT_DIR/features/time_record.sh"

help_time_today() {
    echo "  time today  列出所有游戏的最后一次启动时间与今日日常启动状态"
}

command_time_today() {
    [ "$#" -eq 0 ] || die 1 "用法: time today"

    load_common_config

    if config_has features.time_record.today.reset; then
        log_warn time-record "不推荐在通用配置中设置 'features.time_record.today.reset'，请在游戏配置中分别设置该项"
    fi

    local dir
    config_read features.time_record.dir dir

    local game game_name last_start last_start_time reset_time day_start today_status

    {
        printf "%s\t%s\t%s\n" \
            "$(style_table_header "游戏名")" \
            "$(style_table_header "最后一次启动时间")" \
            "$(style_table_header "今天")"
        for game in "$dir"/*; do
            if [ ! -d "$game" ]; then
                log_warn "跳过非目录文件: $game"
                continue
            fi

            game_name="${game##*/}"

            reset_time="$(
                # shellcheck disable=SC2034 # 供 source 的游戏实现使用
                GAME_NAME="$game_name"
                local game_impl="$SCRIPT_DIR/games/$game_name.sh"
                #shellcheck source=/dev/null
                [ -f "$game_impl" ] && source "$game_impl"
                load_game_config "$game_name"
                local today_reset
                config_read features.time_record.today.reset today_reset
                echo "$today_reset"
            )" || {
                log_error "无法加载游戏配置: $game_name"
                continue
            }

            if [ -z "$reset_time" ] || isn "$reset_time"; then
                # 代表该游戏没有日常/不需要查看，直接跳过
                continue
            fi

            day_start="$(time_day_start "$reset_time")"

            last_start="$(time_record_last_start "$game")"
            last_start_time="$(format_time "$last_start")"

            if [ -n "$last_start" ] && [ "$last_start" -ge "$day_start" ]; then
                today_status="$(style_quote green "已启动")"
            else
                today_status="$(style_quote red "未启动")"
            fi

            printf "%s\t%s\t%s %s\n" "$(style_quote bright_blue "$game_name")" "$(style_quote bright_black "$last_start_time")" "$today_status" "$(style_quote bright_black "($reset_time)")"
        done
    } | column -t -s $'\t'
}

help_time_list() {
    echo "  time list  列出所有游戏的启动次数、总游戏时长、最后一次启动时间"
}

command_time_list() {
    [ "$#" -eq 0 ] || die 1 "用法: time list"

    load_common_config

    local dir
    config_read features.time_record.dir dir

    {
        printf "%s\t%s\t  %s\t  %s\n" \
            "$(style_table_header "游戏名")" \
            "$(style_table_header "启动次数")" \
            "$(style_table_header "总游戏时长")" \
            "$(style_table_header "最后一次启动时间")"

        for game in "$dir"/*; do
            [ -d "$game" ] || continue
            game_name="${game##*/}"

            start_count="$(time_record_count "$game")"

            last_start="$(time_record_last_start "$game")"
            last_start_time="$(format_time "$last_start")"

            total_dur="$(time_record_total_dur "$game")"
            total_dur_formatted="$(format_dur "$total_dur")"

            printf "%s\t%s\t  %s\t  %s\n" \
                "$(style_quote bright_blue "$game_name")" \
                "  $(style_quote cyan "$start_count") $(style_quote bright_black "次")" \
                "$total_dur_formatted" \
                "$(style_quote bright_black "$last_start_time")"
        done
    } | column -t -s $'\t' -o '' -R 2,3
}

help_time_report() {
    echo "  time report <游戏名>  查看指定游戏的游玩时间报告"
}

command_time_report() {
    [ "$#" -eq 1 ] || die 1 "用法: time report <游戏名>"

    local game_name="$1"

    load_common_config
    load_game_config "$game_name"

    local dir total_dur
    config_read features.time_record.dir dir
    dir="$dir/$game_name"

    total_dur="$(time_record_total_dur "$dir")"
    last_start="$(time_record_last_start "$dir")"

    {
        printf "%s\t%s\n" "$(style_quote bright_black "游戏名")"   "$(style_quote bright_blue "$game_name")"
        printf "%s\t%s\n" "$(style_quote bright_black "总时长")"   "$(format_dur "$total_dur")"
        printf "%s\t%s\n" "$(style_quote bright_black "最后启动")" "$(style_quote bright_blue "$(format_time "$last_start")")"

    } | column -t -s $'\t'
}
