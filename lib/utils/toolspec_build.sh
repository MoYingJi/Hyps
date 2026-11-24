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

    local cc_name=BUILD_CC flags_name=BUILD_CFLAGS
    local -a default_cc=(gcc)
    if [[ "$TOOLSPEC_TOOLCHAIN" == mingw ]]; then
        cc_name=BUILD_MINGW_CC
        flags_name=BUILD_MINGW_CFLAGS
        # shellcheck disable=SC2034 # 通过 toolspec_resolve 的 nameref 读取
        default_cc=(x86_64-w64-mingw32-gcc)
    fi
    [[ -v "$cc_name" || "${!cc_name@a}" == *a* ]] || cc_name=default_cc
    toolspec_resolve "$cc_name" "$flags_name" "$@"
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

    if [[ -z "${TOOLSPEC_RESULT_CC[0]:-}" ]] || ! command_exists "${TOOLSPEC_RESULT_CC[0]}"; then
        log_error "$TOOLSPEC_NAME" "未找到编译器 '${TOOLSPEC_RESULT_CC[0]:-}'，请检查 compile 相关配置或安装对应工具链"
        return 1
    fi

    mkdir -p "$(dirname "$output")" || return 1
    run_and_log DEBUG "$TOOLSPEC_NAME" "编译命令" \
        "${TOOLSPEC_RESULT_CC[@]}" "${TOOLSPEC_RESULT_CFLAGS[@]}" \
        "${TOOLSPEC_RESULT_SOURCES[@]}" "${TOOLSPEC_RESULT_LIBS[@]}" \
        -o "$output"
}
