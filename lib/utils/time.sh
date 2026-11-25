#!/hint/bash

#shellcheck source=../core/console.sh
source "$SCRIPT_DIR/core/console.sh"

[[ -n "${__UTILS_TIME_SH_LOADED:-}" ]] && return 0
__UTILS_TIME_SH_LOADED=1

# 输出当前游戏日的起始时间戳，参数为每日刷新时间，如 04:00、04:00 +0800、04:00 Asia/Shanghai
time_day_start() {
    local reset_time="$1" tz=""
    local now start

    # date -d 不认 IANA 时区名，拆出来通过 TZ 传入
    if [[ "$reset_time" =~ ^(.+)[[:space:]]+([A-Za-z_]+/[A-Za-z0-9_+/-]+)$ ]]; then
        reset_time="${BASH_REMATCH[1]}"
        tz="${BASH_REMATCH[2]}"
    fi

    printf -v now '%(%s)T' -1
    start="$(
        [ -z "$tz" ] || export TZ="$tz"
        date -d "today $reset_time" +%s 2>/dev/null
    )" || return 1
    [ -n "$start" ] || return 1

    # 带时区时 today 可能与目标时区的日期差一天，对齐到不晚于现在的最近一次刷新
    while [ "$start" -gt "$now" ]; do
        start=$((start - 86400))
    done
    while [ $((start + 86400)) -le "$now" ]; do
        start=$((start + 86400))
    done

    echo "$start"
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

# 不用 $(style_quote ...)，每次调用会多 5 个子 shell
# 实测单次约 3.9ms 降到 0.02ms，30 个游戏的 time list 约省 116ms
format_dur() {
    local dur_sec="$1" hours minutes secs
    hours=$((dur_sec / 3600))
    minutes=$(((dur_sec % 3600) / 60))
    secs=$((dur_sec % 60))
    printf -v minutes '%02d' "$minutes"
    printf -v secs '%02d' "$secs"

    local style="" reset=""
    if use_color; then
        style="${_CONSOLE_STYLES[bright_blue]}"
        reset="${_CONSOLE_STYLES[reset]}"
    fi

    printf '%s%s%s 时 %s%s%s 分 %s%s%s 秒' \
        "$style" "$hours" "$reset" \
        "$style" "$minutes" "$reset" \
        "$style" "$secs" "$reset"
}

format_time() {
    local timestamp="$1"
    date -d "@$timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo ""
}
