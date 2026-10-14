#!/hint/bash

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

TIME_RECORD_TODAY_RESET_DEFAULT="04:00 Asia/Shanghai"

feat_time_record_load_config() {
    config_default features.time_record.enabled true
    config_is_true features.time_record.enabled || return 0

    config_require_realpath_mkdir features.time_record.dir "$DATA_DIR/time"
    config_default features.time_record.min_sec 60

    if ! config_has features.time_record.today.reset; then
        local reset_time
        if [ "$(type -t feat_time_record_today_reset)" = "function" ]; then
            reset_time="$(feat_time_record_today_reset)"
        else
            reset_time="$TIME_RECORD_TODAY_RESET_DEFAULT"
        fi
        [ -z "$reset_time" ] || isn "$reset_time" || time_day_start "$reset_time" >/dev/null || die 1 time-record "无效的重置时间: $reset_time"
        config_set features.time_record.today.reset "$reset_time"
    fi

    local min_sec
    config_read features.time_record.min_sec min_sec
    [[ "$min_sec" =~ [^0-9] ]] && die 1 time-record "'features.time_record.min_sec' 必须是整数"

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
