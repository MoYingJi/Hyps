#!/usr/bin/bash

# 生成 compile_commands.json
# 实际运行时不用这个, 仅用于 LSP

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

#shellcheck source=../lib/utils/array.sh
source "$ROOT/lib/utils/array.sh"

load_env_args() {
    local output_name="$1" default_value="$2"
    shift 2
    local input_source status=0
    read_env_args "$output_name" input_source "$@" || status=$?
    case "$status" in
        0) ;;
        1) parse_args "$default_value" "$output_name" ;;
        *)
            echo "环境变量 '$input_source' 格式无效，请使用 args 字符串或 Bash 索引数组" >&2
            return 1
            ;;
    esac
}

load_env_args BUILD_CC gcc HYPS_CC CC || exit 1
load_env_args BUILD_CFLAGS '-Wall -Wextra' HYPS_CFLAGS CFLAGS || exit 1
load_env_args BUILD_MINGW_CC x86_64-w64-mingw32-gcc HYPS_MINGW_CC || exit 1
load_env_args BUILD_MINGW_CFLAGS '-Wall -Wextra' HYPS_MINGW_CFLAGS || exit 1

TEMP="$(mktemp --suffix=.jsonl)"
OUTPUT="${2:-$ROOT/compile_commands.json}"

command -v jq >/dev/null 2>&1 || { echo "jq 未安装" >&2; exit 1; }

true > "$TEMP" || { echo "创建或清空临时文件失败: $TEMP" >&2; exit 1; }

cleanup() {
    rm -f "$TEMP"
}

trap cleanup EXIT

resolve_cc() {
    local -n compiler="$1"
    local executable="${compiler[0]:-}"
    compiler[0]="$(type -P -- "$executable")" || {
        echo "无法找到编译器: '$executable'" >&2
        return 1
    }
}

resolve_cc BUILD_CC || exit 1
resolve_cc BUILD_MINGW_CC || exit 1

record_compile() {
    local dir="$1"; shift
    local file="$1"; shift
    jq -n \
        --arg dir "$dir" \
        --arg file "$file" \
        --args \
        '$ARGS.positional as $arguments | {directory: $dir, arguments: $arguments, file: $file}' \
        -- "$@" >> "$TEMP"
}

output() {
    jq -s '.' "$TEMP" > "$OUTPUT"
}

#shellcheck source=../lib/utils/toolspec.sh
source "$ROOT/lib/utils/toolspec.sh"

for spec in "$ROOT"/tools/*/toolspec.sh; do
    dir="$(dirname "$spec")"
    toolspec_load "$dir"

    if [[ "$TOOLSPEC_TOOLCHAIN" == mingw ]]; then
        cc_name=BUILD_MINGW_CC
        flags_name=BUILD_MINGW_CFLAGS
    else
        cc_name=BUILD_CC
        flags_name=BUILD_CFLAGS
    fi

    backends=()
    for backend in "${TOOLSPEC_BACKENDS[@]}"; do
        if toolspec_backend_available "$backend"; then
            backends+=("$backend")
        else
            echo "警告：未检测到 $TOOLSPEC_NAME 的 $backend 后端依赖 (pkg-config 模块 $(toolspec_backend_pkg "$backend"))，将不编译该后端" >&2
        fi
    done

    toolspec_resolve "$cc_name" "$flags_name" "${backends[@]}" || exit 1
    for src in "${TOOLSPEC_RESULT_SOURCES[@]}"; do
        record_compile \
            "$dir" \
            "$src" \
            "${TOOLSPEC_RESULT_CC[@]}" "${TOOLSPEC_RESULT_CFLAGS[@]}" "${TOOLSPEC_RESULT_LIBS[@]}" "$src"
    done
done

# 生成 compile_commands.json 文件

output
