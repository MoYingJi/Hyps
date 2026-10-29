#!/usr/bin/bash

# 生成 compile_commands.json
# 实际运行时不用这个, 仅用于 LSP

HYPS_CC="${HYPS_CC:=gcc}"
HYPS_WIN_CC="${HYPS_WIN_CC:=x86_64-w64-mingw32-gcc}"

# shellcheck disable=SC2034 # 通过 toolspec_resolve 的 nameref 读取
DEFAULT_FLAGS=(-Wall -Wextra)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP="$(mktemp --suffix=.jsonl)"
OUTPUT="${2:-$ROOT/compile_commands.json}"

command -v jq >/dev/null 2>&1 || { echo "jq 未安装" >&2; exit 1; }

true > "$TEMP" || { echo "创建或清空临时文件失败: $TEMP" >&2; exit 1; }

HYPS_CC="$(type -P "$HYPS_CC")" || { echo "无法找到编译器: '$HYPS_CC'" >&2; exit 1; }
HYPS_WIN_CC="$(type -P "$HYPS_WIN_CC")" || { echo "无法找到编译器: '$HYPS_WIN_CC'" >&2; exit 1; }

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
        cc="$HYPS_WIN_CC"
    else
        cc="$HYPS_CC"
    fi

    backends=()
    for backend in "${TOOLSPEC_BACKENDS[@]}"; do
        if toolspec_backend_available "$backend"; then
            backends+=("$backend")
        else
            echo "警告：未检测到 $TOOLSPEC_NAME 的 $backend 后端依赖 (pkg-config 模块 $(toolspec_backend_pkg "$backend"))，将不编译该后端" >&2
        fi
    done

    toolspec_resolve "$cc" DEFAULT_FLAGS "${backends[@]}" || exit 1
    for src in "${TOOLSPEC_RESULT_SOURCES[@]}"; do
        record_compile \
            "$dir" \
            "$src" \
            "$cc" "${TOOLSPEC_RESULT_CFLAGS[@]}" "${TOOLSPEC_RESULT_LIBS[@]}" "$src"
    done
done

# 生成 compile_commands.json 文件

output
