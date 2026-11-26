#!/usr/bin/bash

#shellcheck source=../modules.sh
source "$SCRIPT_DIR/modules.sh"

help_time_today() {
    echo "  time today  列出所有游戏的最后一次启动时间与今日日常启动状态"
}

command_time_today() {
    [ "$#" -eq 0 ] || die 1 "用法: time today"

    hyps_load_modules || return $?
    load_global_config || return $?

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
            game_name_valid "$game_name" || continue

            reset_time="$(
                # shellcheck disable=SC2034 # 供 source 的游戏实现使用
                GAME_NAME="$game_name"
                local game_impl="$SCRIPT_DIR/games/$game_name.sh"
                if [ -f "$game_impl" ]; then
                    #shellcheck source=/dev/null
                    source "$game_impl" || return $?
                fi
                load_game_config "$game_name" || return $?
                local today_reset
                config_read features.time_record.today.reset today_reset || return $?
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

    hyps_load_modules || return $?
    load_global_config || return $?

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
            game_name_valid "$game_name" || continue

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
    echo "  time report <游戏名>  查看指定游戏的游玩时间报告与最近 12 周热力图"
}

# 终端是否支持 256 色，用于热力图的配色档位
_time_report_supports_256() {
    local colors
    colors="$(tput colors 2>/dev/null)" || return 1
    [[ "$colors" =~ ^[0-9]+$ ]] && [ "$colors" -ge 256 ]
}

# 渲染最近 days 天的游戏日热力图
# 每格一个「▀ + 空格」，行是星期，列是周
# 支持 256 色时用绿色渐变，否则用 16 色，无颜色时退回字符密度
# 用法: _time_report_heatmap <天数> <今天星期几> <边界数组名> <每日时长数组名> [时区]
_time_report_heatmap() {
    local days="$1"
    local today_wday="$2"
    local -n _heat_bounds="$3"
    local -n _heat_daily="$4"
    local tz="${5:-}"
    local -a weekday_name=(日 一 二 三 四 五 六)
    local -a level_char=("··" "░░" "▒▒" "▓▓" "██")
    local cell_glyph="██" blank_cell="  "
    local -A cell_level=()
    local -A cell_used=()
    local i day_index secs level idx row col

    # 第一天的星期决定第一列从哪一行开始，之后按 7 天一列排下去
    local first_wday=$(( (today_wday - (days - 1)) % 7 ))
    [ "$first_wday" -ge 0 ] || first_wday=$((first_wday + 7))
    local total_cols=$(( (first_wday + days + 6) / 7 ))

    for ((i = 0; i < days; i++)); do
        day_index=$((i + 1))
        secs="${_heat_daily[$day_index]:-0}"
        if [ "$secs" -eq 0 ]; then
            level=0
        elif [ "$secs" -lt 1800 ]; then
            level=1
        elif [ "$secs" -lt 5400 ]; then
            level=2
        elif [ "$secs" -lt 10800 ]; then
            level=3
        else
            level=4
        fi

        idx=$((first_wday + i))
        row=$((idx % 7))
        col=$((idx / 7))
        cell_level["$row,$col"]="$level"
        cell_used["$row,$col"]=1
    done

    # 256 色时用两个 7/8 块 ▇ 绘制格子
    # ▇ 的墨迹恒为满宽、7/8 行高，所有字体一致，不依赖字形留白
    # 两列宽约等于行高，接近正方形，比单个 ▀ 大 3.5 倍
    # 16 色时绿色档位不够分，保留字符密度
    local -a cell_style=("" "" "" "" "")
    local color_mode=none creset=""
    if use_color; then
        creset="${_CONSOLE_STYLES[reset]}"
        if _time_report_supports_256; then
            color_mode=256
            cell_glyph="▇▇"
            cell_style[0]=$'\033[38;5;236m'
            cell_style[1]=$'\033[38;5;22m'
            cell_style[2]=$'\033[38;5;28m'
            cell_style[3]=$'\033[38;5;34m'
            cell_style[4]=$'\033[38;5;40m'
        else
            color_mode=16
            cell_style[0]="${_CONSOLE_STYLES[bright_black]}"
            cell_style[1]="${_CONSOLE_STYLES[dim]}${_CONSOLE_STYLES[green]}"
            cell_style[2]="${_CONSOLE_STYLES[green]}"
            cell_style[3]="${_CONSOLE_STYLES[bright_green]}"
            cell_style[4]="${_CONSOLE_STYLES[bold]}${_CONSOLE_STYLES[bright_green]}"
        fi
    fi

    # 月份标尺：每列占 3 个显示列（2 宽格子 + 1 分隔），只在月份变化时写数字
    local cell_width=3
    local header="" prev_month="" ts month pad
    for ((col = 0; col < total_cols; col++)); do
        month=""
        idx=$(( col * 7 - first_wday ))
        [ "$idx" -ge 0 ] || idx=0
        ts="${_heat_bounds[$idx]:-}"
        if [ -n "$ts" ]; then
            if [ -n "$tz" ]; then
                TZ="$tz" printf -v month '%(%m)T' "$ts" 2>/dev/null || month=""
            else
                printf -v month '%(%m)T' "$ts" 2>/dev/null || month=""
            fi
            [ "$month" != "$prev_month" ] || month=""
            [ -z "$month" ] || prev_month="$month"
        fi
        if [ -n "$month" ]; then
            header+="$month"
            printf -v pad '%*s' "$(( cell_width - 2 ))" ''
            header+="$pad"
        else
            printf -v pad '%*s' "$cell_width" ''
            header+="$pad"
        fi
    done

    local first_ts="${_heat_bounds[0]:-}"
    # 最后一行边界是下一次刷新，回退一秒得到今天游戏日的末尾
    local last_ts=""
    [ -z "${_heat_bounds[$days]:-}" ] || last_ts=$(( _heat_bounds[days] - 1 ))
    local range="" first_day last_day
    if [ -n "$first_ts" ] && [ -n "$last_ts" ]; then
        if [ -n "$tz" ]; then
            TZ="$tz" printf -v first_day '%(%m-%d)T' "$first_ts"
            TZ="$tz" printf -v last_day '%(%m-%d)T' "$last_ts"
        else
            printf -v first_day '%(%m-%d)T' "$first_ts"
            printf -v last_day '%(%m-%d)T' "$last_ts"
        fi
        range="  $first_day ~ $last_day"
    fi

    printf '最近 %d 天%s\n' "$days" "$range"
    while [[ "$header" == *" " ]]; do header="${header% }"; done
    # 行首是 2 空格 + 宽度 2 的星期 + 1 空格，标尺对齐到同一列
    printf '     %s\n' "$(style_quote bright_black "$header")"

    local line label last_col
    for ((row = 0; row < 7; row++)); do
        # 只标一/三/五，减少左侧噪音
        case "$row" in
            1 | 3 | 5) label="${weekday_name[$row]}" ;;
            *) label="  " ;;
        esac

        # 只渲染到本行最后一个有数据的列，避免行尾留白
        last_col=-1
        for ((col = total_cols - 1; col >= 0; col--)); do
            if [ -n "${cell_used["$row,$col"]:-}" ]; then
                last_col=$col
                break
            fi
        done

        # 格子之间用空格分隔，首列不加，这样行尾不会留白
        line=""
        for ((col = 0; col <= last_col; col++)); do
            [ "$col" -eq 0 ] || line+=" "
            if [ -z "${cell_used["$row,$col"]:-}" ]; then
                line+="${blank_cell}"
                continue
            fi
            level="${cell_level["$row,$col"]}"
            if [ "$color_mode" = 256 ]; then
                line+="${cell_style[$level]}${cell_glyph}${creset}"
            else
                line+="${level_char[$level]}"
            fi
        done
        printf '  %s %s\n' "$(style_quote bright_black "$label")" "$line"
    done

    # 图例与格子使用同一套字形和配色
    local legend="" legend_glyph
    for ((level = 0; level < 5; level++)); do
        if [ "$color_mode" = 256 ]; then
            legend_glyph="▇▇"
        else
            legend_glyph="${level_char[$level]}"
        fi
        legend+="${cell_style[$level]}${legend_glyph}${creset} "
        [ "$level" -eq 0 ] && legend+="无记录  "
    done
    printf '  %s %s少到多\n' "$(style_quote bright_black "图例")" "$legend"
}

command_time_report() {
    [ "$#" -eq 1 ] || die 1 "用法: time report <游戏名>"

    local game_name="$1"
    game_name_valid "$game_name" || die 1 "无效的游戏名: $game_name"

    hyps_load_modules || return $?
    load_global_config || return $?

    local dir
    config_read features.time_record.dir dir
    dir="$dir/$game_name"

    # 记录与游戏配置解耦，没有配置或实现时也能查看历史
    local game_impl="$SCRIPT_DIR/games/$game_name.sh"
    if [ -f "$game_impl" ]; then
        #shellcheck disable=SC2034 # 供 source 的游戏实现使用
        GAME_NAME="$game_name"
        #shellcheck source=/dev/null
        source "$game_impl"
    fi
    if [ -f "$CONFIG_DIR/games/$game_name.conf" ]; then
        load_game_config "$game_name" || die 1 time-report "游戏配置加载失败: $game_name"
    fi

    # 未设置每日刷新时不展示日常相关项，统计日固定为本地 00:00
    local has_daily=0 report_reset reset_display reset_expr
    config_read features.time_record.today.reset report_reset 2>/dev/null || true
    if [ -n "$report_reset" ] && ! isn "$report_reset"; then
        has_daily=1
        reset_display="$report_reset"
        reset_expr="$report_reset"
    else
        reset_display="未设置（按本地 00:00 统计）"
        reset_expr="00:00"
    fi

    if [ ! -f "$dir/history" ]; then
        {
            printf '%s\t%s\n' "$(style_quote bright_black "游戏名")" "$(style_quote bright_blue "$game_name")"
            printf '%s\t%s\n' "$(style_quote bright_black "记录")" "$(style_quote bright_black "暂无记录")"
        } | column -t -s $'\t'
        return 0
    fi

    local total_dur last_start count
    total_dur="$(time_record_total_dur "$dir")"
    last_start="$(time_record_last_start "$dir")"
    count="$(time_record_count "$dir")"

    local now day_start next_start today_status today_count today_dur countdown
    local days=$(( 12 * 7 ))
    local -a bounds=()
    local -A daily=()
    printf -v now '%(%s)T' -1
    day_start="$(time_day_start "$reset_expr")" || day_start=""

    if [ -n "$day_start" ]; then
        # 一次算齐最近 12 周的边界，顺带得到下次刷新和今天时长
        mapfile -t bounds < <(time_day_boundaries "$reset_expr" "$day_start" "$days")

        if [ "${#bounds[@]}" -eq $((days + 1)) ]; then
            next_start="${bounds[$days]}"
            local bounds_csv="" b
            for b in "${bounds[@]}"; do
                bounds_csv+="${bounds_csv:+,}$b"
            done
            local idx secs
            while IFS=$'\t' read -r idx secs; do
                #shellcheck disable=SC2034 # 通过 nameref 传给热力图
                [ -n "$idx" ] && daily[$idx]="$secs"
            done < <(time_record_daily_durations "$dir" "$bounds_csv")
            today_dur="${daily[$days]:-0}"
        else
            next_start="$(time_day_boundaries "$reset_expr" "$day_start" 1 | tail -n 1)"
            today_dur=0
        fi

        today_count="$(time_record_count_since "$dir" "$day_start")"
        countdown=$((next_start - now))
        [ "$countdown" -ge 0 ] || countdown=0
        if [ -n "$last_start" ] && [ "$last_start" -ge "$day_start" ]; then
            today_status="$(style_quote green "已启动")"
        else
            today_status="$(style_quote red "未启动")"
        fi
    else
        next_start=""
        today_count=0
        today_dur=0
        countdown=""
        today_status="$(style_quote bright_black "-")"
    fi

    local last_start_display="-"
    [ -z "$last_start" ] || last_start_display="$(format_time "$last_start")"

    {
        printf '%s\t%s\n' "$(style_quote bright_black "游戏名")" "$(style_quote bright_blue "$game_name")"
        printf '%s\t%s\n' "$(style_quote bright_black "总时长")" "$(format_dur "$total_dur")"
        printf '%s\t%s\n' "$(style_quote bright_black "启动次数")" "$(style_quote cyan "$count")"
        printf '%s\t%s\n' "$(style_quote bright_black "最后启动")" "$(style_quote bright_blue "$last_start_display")"
        printf '%s\t%s\n' "$(style_quote bright_black "每日刷新")" "$(style_quote cyan "$reset_display")"
        [ "$has_daily" -eq 0 ] || printf '%s\t%s\n' \
            "$(style_quote bright_black "今天")" "$today_status"
        printf '%s\t%s\n' "$(style_quote bright_black "今天启动")" "$(style_quote cyan "$today_count") $(style_quote bright_black "次")"
        printf '%s\t%s\n' "$(style_quote bright_black "今天时长")" "$(format_dur "$today_dur")"
        [ "$has_daily" -eq 0 ] || printf '%s\t%s\n' \
            "$(style_quote bright_black "下次刷新")" "$(style_quote bright_blue "$(format_time "$next_start")")"
        [ "$has_daily" -eq 0 ] || printf '%s\t%s\n' \
            "$(style_quote bright_black "距下次刷新")" "$(format_dur "$countdown")"
    } | column -t -s $'\t'

    if [ "${#bounds[@]}" -eq $((days + 1)) ] && [ -n "$day_start" ]; then
        local today_wday heat_tz=""
        today_wday="$(time_day_weekday "$reset_expr" "$day_start")"
        [ -n "$today_wday" ] || today_wday=0
        if [[ "$reset_expr" =~ ^(.+)[[:space:]]+([A-Za-z_]+/[A-Za-z0-9_+/-]+)$ ]]; then
            heat_tz="${BASH_REMATCH[2]}"
        fi
        printf '\n'
        _time_report_heatmap "$days" "$today_wday" bounds daily "$heat_tz"
    fi
}
