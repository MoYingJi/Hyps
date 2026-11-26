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

# 输出最近 days 个游戏日的边界时间戳，每行一个，共 days+1 行
# 第一行是最早游戏日的起点，倒数第二行是今天游戏日的起点，最后一行是下一次刷新
# 用法: time_day_boundaries <每日刷新时间> <今天游戏日起点> <days>
time_day_boundaries() {
    local reset_time="$1"
    local day_start="$2"
    local days="$3"
    local tz=""
    local reset="$reset_time"
    local base_date i

    if [[ "$reset_time" =~ ^(.+)[[:space:]]+([A-Za-z_]+/[A-Za-z0-9_+/-]+)$ ]]; then
        reset="${BASH_REMATCH[1]}"
        tz="${BASH_REMATCH[2]}"
    fi

    if [ -n "$tz" ]; then
        base_date="$(TZ="$tz" date -d "@$day_start" +%Y-%m-%d 2>/dev/null)" || return 1
        for ((i = days - 1; i >= 0; i--)); do
            TZ="$tz" date -d "$base_date -$i days $reset" +%s 2>/dev/null || return 1
        done
        TZ="$tz" date -d "$base_date +1 day $reset" +%s 2>/dev/null || return 1
    else
        base_date="$(date -d "@$day_start" +%Y-%m-%d 2>/dev/null)" || return 1
        for ((i = days - 1; i >= 0; i--)); do
            date -d "$base_date -$i days $reset" +%s 2>/dev/null || return 1
        done
        date -d "$base_date +1 day $reset" +%s 2>/dev/null || return 1
    fi
}

# 输出游戏日的星期几，0 表示周日
# 用法: time_day_weekday <每日刷新时间> <游戏日起点>
time_day_weekday() {
    local reset_time="$1"
    local day_start="$2"
    local tz=""

    if [[ "$reset_time" =~ ^(.+)[[:space:]]+([A-Za-z_]+/[A-Za-z0-9_+/-]+)$ ]]; then
        tz="${BASH_REMATCH[2]}"
    fi

    if [ -n "$tz" ]; then
        TZ="$tz" date -d "@$day_start" +%w 2>/dev/null
    else
        date -d "@$day_start" +%w 2>/dev/null
    fi
}

# 按游戏日切分游玩记录，输出 <序号>\t<秒数>
# 第一行对应最早的边界区间，最后一行对应今天
# 用法: time_record_daily_durations <记录目录> <逗号分隔的边界时间戳>
time_record_daily_durations() {
    local record_dir="$1"
    local bounds="$2"

    awk -v bounds="$bounds" -v OFS=$'\t' '
        BEGIN {
            n = split(bounds, b, ",")
            for (i = 1; i <= n; i++) bs[i] = b[i] + 0
            for (i = 1; i < n; i++) dur[i] = 0
        }
        {
            start = $1 + 0
            end = $2 + 0
            if (end <= start) next
            # 区间在统计范围之前或之后的部分直接丢掉
            if (end <= bs[1]) next
            if (start < bs[1]) start = bs[1]
            if (start >= bs[n]) next
            while (start < end) {
                day = 0
                for (i = 1; i < n; i++) {
                    if (start >= bs[i] && start < bs[i + 1]) {
                        day = i
                        break
                    }
                }
                if (day == 0) break
                seg_end = (day < n) ? bs[day + 1] : end
                if (seg_end > end) seg_end = end
                if (seg_end <= start) break
                dur[day] += seg_end - start
                start = seg_end
            }
        }
        END {
            for (i = 1; i < n; i++) print i, dur[i]
        }
    ' "$record_dir/history" 2>/dev/null
}

# 统计某个时间点之后的启动次数
# 用法: time_record_count_since <记录目录> <起始时间戳>
time_record_count_since() {
    awk -v from="$2" '$1 + 0 >= from { n++ } END { print n + 0 }' \
        "$1/history" 2>/dev/null || echo "0"
}

# 以下 time_record_* 的参数均为某个游戏的记录目录
time_record_last_start() {
    awk 'END {print $1}' "$1/history" 2>/dev/null || echo ""
}

time_record_total_dur() {
    awk '{sum += $2 - $1} END {print sum + 0}' "$1/history" 2>/dev/null || echo "0"
}

time_record_count() {
    [ -f "$1/history" ] || {
        echo "0"
        return 0
    }
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
