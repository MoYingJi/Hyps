#!/hint/bash

[[ -n "${__UTILS_MISC_SH_LOADED:-}" ]] && return 0
__UTILS_MISC_SH_LOADED=1

#shellcheck source=../core/log.sh
source "$SCRIPT_DIR/core/log.sh"

#shellcheck source=command.sh
source "$SCRIPT_DIR/utils/command.sh"
#shellcheck source=string.sh
source "$SCRIPT_DIR/utils/string.sh"

sudo_request() {
    local why="$1"
    shift

    echo "[Hyps] [sudo 请求] $why"
    echo -n "[Hyps] $ "
    quote_args "$@"
    sudo "$@"
}

run_and_log() {
    local level="$1"
    local module="$2"
    local prompt="$3"
    shift 3

    [ -z "$prompt" ] && prompt="执行命令"
    log "$level" "$module" "$prompt: $(quote_args "$@")"
    "$@"
}

nvidia_version() {
    # if command -v nvidia-smi >/dev/null 2>&1; then
    #     nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null \
    #         | head -n1 | tr -d '[:space:]'
    #     return
    # fi

    if [ -r /sys/module/nvidia/version ]; then
        local version
        IFS= read -r version < /sys/module/nvidia/version || [[ -n "$version" ]] || return 1
        printf '%s\n' "$version"
        return
    fi

    echo "unknown"
}

extract_pkg_version() {
    local pkg_version_file="$1"
    local target_remote_name="$2"

    if [ -z "$pkg_version_file" ] || [ ! -f "$pkg_version_file" ]; then
        die 1 utils "未找到 pkg_version 文件"
    fi

    if [ -z "$target_remote_name" ]; then
        die 1 utils "未指定目标远程文件名"
    fi

    if command_exists jq; then
        jq -r --arg target "$target_remote_name" '
            select(.remoteName == $target) |
            [.md5, (.fileSize | tostring)] | @tsv
        ' "$pkg_version_file"
    else
        grep -F "\"remoteName\": \"$target_remote_name\"" "$pkg_version_file" \
            | sed -E 's/.*"md5": "([^"]+)".*"fileSize": ([0-9]+).*/\1\t\2/'
    fi
}

verify_file_with_pkg_version() {
    local pkg_version_file="$1"
    local target_remote_name="$2"
    local file_to_verify="$3"

    if [ ! -f "$file_to_verify" ]; then
        die 1 utils "文件不存在: $file_to_verify"
    fi

    local expected_md5 expected_size
    IFS=$'\t' read -r expected_md5 expected_size < <(extract_pkg_version "$pkg_version_file" "$target_remote_name")

    local actual_md5 actual_size
    actual_md5=$(md5sum "$file_to_verify" | awk '{print $1}')
    actual_size=$(stat -c%s "$file_to_verify")

    [ "$expected_md5" == "$actual_md5" ] && [ "$expected_size" == "$actual_size" ]
}
