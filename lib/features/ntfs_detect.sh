#!/hint/bash

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

feat_ntfs_detect_pre_start() {
    isy "$(config_get features.ntfs_detect.enabled true)" || return 0

    local game_exe fs
    game_exe="$(config_get game.exe)"
    fs="$(stat -f -c %T "$game_exe")"

    if [ "$fs" = "ntfs" ] || [ "$fs" = "ntfs3" ]; then
        log_warn ntfs-detect "游戏正运行在 NTFS 上！这可能会导致游戏文件损坏或双系统时出现 Bug"
        log_warn ntfs-detect "推荐使用 Overlay 并保持 NTFS 中的游戏本体只读"
        log_warn ntfs-detect "要抑制这条警告，使用 'features.ntfs_detect.enabled = false'"
    fi
}

register_hook pre_start feat_ntfs_detect_pre_start
