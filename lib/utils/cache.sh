#!/hint/bash

[[ -n "${__UTILS_CACHE_SH_LOADED:-}" ]] && return 0
__UTILS_CACHE_SH_LOADED=1

#shellcheck source=string.sh
source "${SCRIPT_DIR:-.}/utils/string.sh"

check_cache_and_compile() {
    local name="$1"
    local output_file="$2"
    local all_source_fn="$3" # 会拿函数输出来计算校验和
    local verify_output_fn="$4"
    local compile_fn="$5"
    local log_level="${6:-INFO}"

    local sha256sum_dir="$CACHE_DIR/checksums"
    mkdir -p "$sha256sum_dir"
    local sha256sum_file="$sha256sum_dir/${name}.sha256sum"
    local current_sha256

    if isy "$HYPS_FORCE_RECOMPILE"; then
        log "$log_level" utils "[$name] 强制重新编译 (HYPS_FORCE_RECOMPILE=1)"
    elif [ ! -e "$output_file" ]; then
        log_debug utils "[$name] 输出文件不存在"
    elif ! "$verify_output_fn" "$output_file"; then
        log_debug utils "[$name] 输出文件验证失败"
    elif [ ! -f "$sha256sum_file" ]; then
        log_debug utils "[$name] 校验和文件不存在"
    else
        local cached_sha256
        current_sha256="$("$all_source_fn" "$output_file" | sha256sum | awk '{print $1}')"
        cached_sha256="$(cat "$sha256sum_file")"

        if [ "$current_sha256" != "$cached_sha256" ]; then
            log_debug utils "[$name] 校验和不一致"
        else
            log_debug utils "[$name] 校验和一致"
            return 0
        fi
    fi

    log "$log_level" utils "[$name] 重新编译"
    "$compile_fn" "$output_file" || die 1 utils "[$name] 编译失败"
    "$verify_output_fn" "$output_file" || die 1 utils "[$name] 编译后验证失败"

    [ -z "$current_sha256" ] && current_sha256="$("$all_source_fn" "$output_file" | sha256sum | awk '{print $1}')"
    echo "$current_sha256" > "$sha256sum_file"
}
