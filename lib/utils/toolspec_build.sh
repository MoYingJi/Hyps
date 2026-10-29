#!/hint/bash

[[ -n "${__UTILS_TOOLSPEC_BUILD_SH_LOADED:-}" ]] && return 0
__UTILS_TOOLSPEC_BUILD_SH_LOADED=1

#shellcheck source=toolspec.sh
source "$SCRIPT_DIR/utils/toolspec.sh"
#shellcheck source=command.sh
source "$SCRIPT_DIR/utils/command.sh"

# 按工具链选择编译器与用户 CFLAGS 后解析 ToolSpec
# toolspec_runtime_resolve <工具目录> [backend...]
toolspec_runtime_resolve() {
    local dir="$1"
    shift
    toolspec_load "$dir" || return 1

    if [[ "$TOOLSPEC_TOOLCHAIN" == mingw ]]; then
        toolspec_resolve "${HYPS_WIN_CC:-x86_64-w64-mingw32-gcc}" HYPS_MINGW_CFLAGS "$@"
    else
        toolspec_resolve "${HYPS_CC:-gcc}" HYPS_CFLAGS "$@"
    fi
}

# toolspec_runtime_fingerprint <工具目录> [backend...]
toolspec_runtime_fingerprint() {
    toolspec_runtime_resolve "$@" && toolspec_fingerprint
}

# toolspec_runtime_build <工具目录> <输出文件> [backend...]
toolspec_runtime_build() {
    local dir="$1" output="$2"
    shift 2
    toolspec_runtime_resolve "$dir" "$@" || return 1

    if ! command_exists "$TOOLSPEC_RESULT_CC"; then
        log_error "$TOOLSPEC_NAME" "未找到编译器 '$TOOLSPEC_RESULT_CC'，请检查 compile 相关配置或安装对应工具链"
        return 1
    fi

    mkdir -p "$(dirname "$output")" || return 1
    run_and_log DEBUG "$TOOLSPEC_NAME" "编译命令" \
        "$TOOLSPEC_RESULT_CC" "${TOOLSPEC_RESULT_CFLAGS[@]}" \
        "${TOOLSPEC_RESULT_SOURCES[@]}" "${TOOLSPEC_RESULT_LIBS[@]}" \
        -o "$output"
}
