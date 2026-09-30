#!/hint/bash

[[ -n "${__UTILS_TIME_SH_LOADED:-}" ]] && return 0
__UTILS_TIME_SH_LOADED=1

# 输出当前游戏日（以 04:00 为界）的起始时间戳
time_day_start() {
    local today_date now today_4am
    today_date="$(date +%Y-%m-%d)"
    now="$(date +%s)"
    today_4am="$(date -d "$today_date 04:00:00" +%s 2>/dev/null)"

    if [ "$now" -lt "$today_4am" ]; then
        date -d "$(date -d "$today_date -1 day" +%Y-%m-%d) 04:00:00" +%s 2>/dev/null
    else
        echo "$today_4am"
    fi
}

# 以下 time_record_* 的参数均为某个游戏的记录目录
time_record_last_start() {
    awk 'END {print $1}' "$1/history" 2>/dev/null || echo ""
}

time_record_total_dur() {
    awk '{sum += $2 - $1} END {print sum + 0}' "$1/history" 2>/dev/null || echo "0"
}

time_record_count() {
    wc -l < "$1/history" 2>/dev/null || echo "0"
}

format_dur() {
    local dur_sec="$1" hours minutes secs
    hours=$((dur_sec / 3600))
    minutes=$(((dur_sec % 3600) / 60))
    secs=$((dur_sec % 60))
    printf "%s%d%s 时 %s%02d%s 分 %s%02d%s 秒" "$(style bright_blue)" "$hours" "$(style bright_black)" "$(style bright_blue)" "$minutes" "$(style bright_black)" "$(style bright_blue)" "$secs" "$(style bright_black)"
}

format_time() {
    local timestamp="$1"
    date -d "@$timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo ""
}
