#!/hint/bash

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

feat_time_record_load_config() {
    config_default features.time_record.enabled true >/dev/null
    isy "$(config_get features.time_record.enabled)" || return 0

    config_require_realpath_mkdir features.time_record.dir "$DATA_DIR/time"
    config_default features.time_record.min_sec 60 >/dev/null

    [[ "$(config_get features.time_record.min_sec)" =~ [^0-9] ]] && die 1 time_record "'features.time_record.min_sec' 必须是整数"

    register_hook pre_start feat_time_record_start
    register_hook cleanup feat_time_record_end
}

register_hook load_config feat_time_record_load_config

feat_time_record_start() {
    TIME_RECORD_CURRENT_START_SEC="$(date +%s)"
    log_debug time-record "记录游戏开始时间: $TIME_RECORD_CURRENT_START_SEC"
}

feat_time_record_end() {
    local current_start="$TIME_RECORD_CURRENT_START_SEC"
    local current_end
    local current_dur
    local total_dur

    local min_sec
    local time_record_data_dir

    if [ -z "$current_start" ]; then
        log_info time-record "未记录开始时间，跳过时间记录"
        return 0
    fi

    current_end="$(date +%s)"
    current_dur="$(( current_end - current_start ))"

    log_debug time-record "记录游戏结束时间: $current_end"

    min_sec="$(config_get features.time_record.min_sec)"
    time_record_data_dir="$(config_get features.time_record.dir)/$GAME_NAME"

    if [[ "$current_dur" -lt "$min_sec" ]]; then
        log_info time-record "游戏时间过短 ($((current_dur)) 秒 < $min_sec 秒)，不记录"
        return 0
    fi

    log_info time-record "本次游戏时长 $((current_dur)) 秒"

    mkdir -p "$time_record_data_dir" || die 1 time-record "无法创建时间记录目录: $time_record_data_dir"

    printf "%s\t%s\n" "$current_start" "$current_end" >> "$time_record_data_dir/history"

    total_dur="$(awk '{sum += $2 - $1} END {print sum}' "$time_record_data_dir/history")"
    total_dur="$(( total_dur + current_dur ))"
    echo "$total_dur" > "$time_record_data_dir/total-dur"
    log_info time-record "累计游戏时长 $((total_dur)) 秒"
}
