#!/hint/bash

# shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

feat_fs_detect_get_blkfs() {
    local path="$1"
    [ -n "$path" ] || return 1
    while [ ! -e "$path" ] && [ "$path" != "/" ]; do
        path_dirname path path
    done

    local source_dev
    source_dev="$(findmnt -no SOURCE -T "$path")" || return 1
    [ -n "$source_dev" ] || return 1
    source_dev="${source_dev%%\[*}"   # /dev/sda1[/@] -> /dev/sda1
    source_dev="${source_dev%%,*}"    # /dev/sda1,/dev/sdb1 -> /dev/sda1

    lsblk -no FSTYPE "$source_dev" 2>/dev/null
}

feat_fs_detect_warn_game_in() {
    local fs="$1"
    local fs_config="$2"

    config_is_true features.fs_detect.game_in_"$fs_config" true || return 0

    log_warn fs-detect "游戏正运行在 $fs 上！这可能会导致游戏文件损坏或双系统时出现 Bug"
    log_warn fs-detect "推荐使用 Overlay，并将游戏本体所在的 $fs 保持只读"
    log_warn fs-detect "要抑制这条警告，使用 'features.fs_detect.game_in_$fs_config = false'"
}

feat_fs_detect_error_prefix_in() {
    local fs="$1"
    local fs_config="$2"

    config_is_true features.fs_detect.prefix_in_"$fs_config" true || return 0

    log_error fs-detect "Wine Prefix 在 $fs 上！这很可能导致兼容层无法正常工作！"
    log_error fs-detect "推荐将其设置到其他文件系统上 (如 ext4 / btrfs)"
    log_error fs-detect "要忽视这条错误强行运行，使用 'features.fs_detect.prefix_in_$fs_config = false'"

    die 1
}

feat_fs_detect_pre_start() {
    config_is_true features.fs_detect.enabled true || return 0 # 总开关

    local game_exe game_blkfs
    config_read game.exe game_exe
    game_blkfs="$(feat_fs_detect_get_blkfs "$game_exe")" \
        || log_debug "无法获取游戏本体所在的文件系统: '$game_exe'"

    case "$game_blkfs" in
        ntfs)  feat_fs_detect_warn_game_in "NTFS"         "ntfs"  ;;
        exfat) feat_fs_detect_warn_game_in "exFAT"        "exfat" ;;
        vfat)  feat_fs_detect_warn_game_in "FAT 文件系统" "vfat"  ;;
    esac

    local prefix_dir prefix_blkfs
    config_read game.prefix prefix_dir
    prefix_blkfs="$(feat_fs_detect_get_blkfs "$prefix_dir")" \
        || log_debug "无法获取 Wine Prefix 所在的文件系统: '$prefix_dir'"

    case "$prefix_blkfs" in
        ntfs)  feat_fs_detect_error_prefix_in "NTFS"         "ntfs"  ;;
        exfat) feat_fs_detect_error_prefix_in "exFAT"        "exfat" ;;
        vfat)  feat_fs_detect_error_prefix_in "FAT 文件系统" "vfat"  ;;
    esac

    return 0
}

register_hook pre_start feat_fs_detect_pre_start
