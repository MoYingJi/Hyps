#!/hint/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

time_record_default_dir() {
    local -n result="$1"
    result="$DATA_DIR/time"
}

# 未声明日常刷新时间时留空，表示不显示日常，可由 features.time_record.today.reset 覆盖
#shellcheck disable=SC2034
time_record_default_reset() {
    local -n result="$1"
    result="${GAME_DAILY_RESET-}"
}

time_record_validate_reset() {
    [[ -z "$1" ]] || isn "$1" || time_day_start "$1" >/dev/null
}

config_declare features.time_record.enabled bool --default true --description "记录游玩时间"
config_declare features.time_record.dir path --in global --default-fn time_record_default_dir --description "游玩记录目录"
config_declare features.time_record.min_sec uint --default 60 --when features.time_record.enabled \
    --description "单次游玩记录的最短秒数"
config_declare features.time_record.today.reset string --in game-instance --default-fn time_record_default_reset \
    --validate time_record_validate_reset --description "日常刷新时间，空值或假值表示不参与"

feat_time_record_load_config() {
    config_is_true features.time_record.enabled || return 0
    config_validate features.time_record

    register_hook pre_start feat_time_record_start
    register_hook cleanup feat_time_record_end
}

register_hook load_config feat_time_record_load_config

feat_time_record_start() {
    if isy "$SKIP_TIME_RECORD"; then
        log_info time-record "因环境变量 SKIP_TIME_RECORD 设置，跳过时间记录"
        return 0
    fi
    printf -v TIME_RECORD_CURRENT_START_SEC '%(%s)T' -1
    log_debug time-record "记录游戏开始时间: $TIME_RECORD_CURRENT_START_SEC"
}

feat_time_record_end() {
    local current_start="$TIME_RECORD_CURRENT_START_SEC"
    local current_end
    local current_dur
    local total_dur

    local min_sec
    local time_record_dir
    local time_record_data_dir

    if [ -z "$current_start" ]; then
        log_info time-record "未记录开始时间，跳过时间记录"
        return 0
    fi

    printf -v current_end '%(%s)T' -1
    current_dur="$(( current_end - current_start ))"

    log_debug time-record "记录游戏结束时间: $current_end"

    config_read features.time_record.min_sec min_sec
    config_read features.time_record.dir time_record_dir
    time_record_data_dir="$time_record_dir/$GAME_NAME"

    if [[ "$current_dur" -lt "$min_sec" ]]; then
        log_info time-record "游戏时间过短 ($((current_dur)) 秒 < $min_sec 秒)，不记录"
        return 0
    fi

    log_info time-record "本次游戏时长 $((current_dur)) 秒"

    mkdir -p "$time_record_data_dir" || die 1 time-record "无法创建时间记录目录: $time_record_data_dir"

    printf "%s\t%s\n" "$current_start" "$current_end" >> "$time_record_data_dir/history"

    total_dur="$(time_record_total_dur "$time_record_data_dir")"
    total_dur="$(( total_dur + current_dur ))"

    log_info time-record "累计游戏时长 $((total_dur)) 秒"

    # echo "$total_dur" > "$time_record_data_dir/total-dur"
    # 删除旧文件，total-dur 文件已弃用
    rm -f "$time_record_data_dir/total-dur" 2>/dev/null
}
