#!/hint/bash

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

#shellcheck source=xwin_watch.sh
source "${SCRIPT_DIR:-.}/features/xwin_watch.sh"

feat_hosts_disconnect_load_config() {
    isy "$(config_get features.hosts_disconnect.enabled)" || return 0

    config_has features.hosts_disconnect.content || die 1 hosts-disconnect "请在配置文件中设置 features.hosts_disconnect.content"
    config_require_realpath_file features.hosts_disconnect.file "/etc/hosts"
    config_default features.hosts_disconnect.duration "-" >/dev/null

    local duration
    duration="$(config_get features.hosts_disconnect.duration)"
    if [[ "$duration" != "-" ]]; then
        if ! [[ "$duration" =~ ^[0-9]+$ ]]; then
            die 1 hosts-disconnect "features.hosts_disconnect.duration 必须是整数或 '-'"
        fi
    else
        config_set features.xwin_watch.enabled true
    fi
}

register_hook load_config feat_hosts_disconnect_load_config 50 before:feat_xwin_watch_load_config

feat_hosts_disconnect_prepare() {
    local flag="Hyps Gaming Network Hosts"
    local flagStart="# $flag $GAME_NAME Start"
    local flagEnd="# $flag $GAME_NAME End"

    local content
    local hosts_file

    content="$(config_get features.hosts_disconnect.content)"
    hosts_file="$(config_get features.hosts_disconnect.file)"

    if [ ! -w "$hosts_file" ]; then
        HOSTS_ORI_PERM="$(stat -c "%a" "$hosts_file")"
        sudo_request "使 hosts 文件可写" chmod +w "$hosts_file"
    fi

    content="$(cat << EOF
$flagStart
$content
$flagEnd
EOF
    )"

    HOSTS_DISCONNECT_BACKUP="$(mktemp "$TEMP_DIR/hosts.XXXXXXX.bak")"
    cat "$hosts_file" > "$HOSTS_DISCONNECT_BACKUP"
    echo -n "$content" >> "$hosts_file"

    if [[ "$duration" != "-" ]]; then
        register_hook pre_start feat_hosts_disconnect_pre_start
        register_hook cleanup feat_hosts_disconnect_cleanup
    else
        xwin_watch_on closed feat_hosts_disconnect_restore
        xwin_watch_on failed feat_hosts_disconnect_restore
    fi
}

feat_hosts_disconnect_pre_start() {
    local duration
    duration="$(config_get features.hosts_disconnect.duration)"
    (
        trap feat_hosts_disconnect_restore EXIT
        sleep "$duration"
    ) &
    HOSTS_DISCONNECT_SLEEP_PID="$!"
}

feat_hosts_disconnect_cleanup() {
    kill "$HOSTS_DISCONNECT_SLEEP_PID" 2>/dev/null
}

feat_hosts_disconnect_restore() {
    local hosts_file
    local flag="Hyps Gaming Network Hosts"
    local flagStart="# $flag $GAME_NAME Start"
    local flagEnd="# $flag $GAME_NAME End"

    hosts_file="$(config_get features.hosts_disconnect.file)"

    if [ ! -w "$hosts_file" ]; then
        sudo_request "使 hosts 文件可写" chmod +w "$hosts_file"
    fi

    sed -i "/$flagStart/,/$flagEnd/d" "$hosts_file"

    if [ -n "$HOSTS_ORI_PERM" ]; then
        sudo_request "恢复 hosts 文件权限" chmod "$HOSTS_ORI_PERM" "$hosts_file"
    fi
}
