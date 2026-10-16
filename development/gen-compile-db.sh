#!/usr/bin/bash

# 生成 compile_commands.json
# 实际运行时不用这个, 仅用于 LSP

HYPS_CC="${HYPS_CC:=gcc}"
HYPS_WIN_CC="${HYPS_WIN_CC:=x86_64-w64-mingw32-gcc}"

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

# endfield-launcher

ENDFIELD_LAUNCHER_TOOL="$ROOT/tools/endfield-launcher"
ENDFIELD_LAUNCHER_SOURCE="$ENDFIELD_LAUNCHER_TOOL/endfield-launcher.c"
ENDFIELD_LAUNCHER_FLAGS=("${DEFAULT_FLAGS[@]}" -std=gnu23 -municode -mwindows -static)

record_compile \
    "$ENDFIELD_LAUNCHER_TOOL" \
    "$ENDFIELD_LAUNCHER_SOURCE" \
    "$HYPS_WIN_CC" "${ENDFIELD_LAUNCHER_FLAGS[@]}" "$ENDFIELD_LAUNCHER_SOURCE"

# fpsunlock

FPSUNLOCK_TOOL="$ROOT/tools/fpsunlock"
FPSUNLOCK_SOURCE="$FPSUNLOCK_TOOL/unlocker.c"
FPSUNLOCK_FLAGS=("${DEFAULT_FLAGS[@]}" -std=gnu23)

record_compile \
    "$FPSUNLOCK_TOOL" \
    "$FPSUNLOCK_SOURCE" \
    "$HYPS_CC" "${FPSUNLOCK_FLAGS[@]}" "$FPSUNLOCK_SOURCE"

# xwin-watch

XWIN_WATCH_TOOL="$ROOT/tools/xwin-watch"
XWIN_WATCH_SOURCES=("$XWIN_WATCH_TOOL/xwin-watch.c")
XWIN_WATCH_FLAGS=("${DEFAULT_FLAGS[@]}" -std=gnu23)

XWIN_WATCH_FLAGS+=("-I$XWIN_WATCH_TOOL")

if pkg-config --exists x11; then
    XWIN_WATCH_SOURCES+=("$XWIN_WATCH_TOOL/x11-backend.c")
    XWIN_WATCH_FLAGS+=(-DHAVE_X11 -lX11)
else
    echo "警告：未检测到 X11 开发依赖 (pkg-config 模块 x11), xwin-watch 将不编译 X11 后端" >&2
fi

if pkg-config --exists wayland-client; then
    XWIN_WATCH_SOURCES+=("$XWIN_WATCH_TOOL/wayland.c")
    XWIN_WATCH_FLAGS+=(-DHAVE_WAYLAND -lwayland-client)

    XWIN_WATCH_SOURCES+=("$XWIN_WATCH_TOOL/wlr-backend.c" "$XWIN_WATCH_TOOL/generated/wlr-foreign-toplevel-management-unstable-v1.c")
    XWIN_WATCH_FLAGS+=(-DHAVE_WLR)

    XWIN_WATCH_SOURCES+=("$XWIN_WATCH_TOOL/ext-backend.c" "$XWIN_WATCH_TOOL/generated/ext-foreign-toplevel-list-v1.c")
    XWIN_WATCH_FLAGS+=(-DHAVE_EXT)

    XWIN_WATCH_SOURCES+=("$XWIN_WATCH_TOOL/plasma-backend.c" "$XWIN_WATCH_TOOL/generated/plasma-window-management.c")
    XWIN_WATCH_FLAGS+=(-DHAVE_PLASMA)
else
    echo "警告：未检测到 Wayland 开发依赖 (pkg-config 模块 wayland-client), xwin-watch 将不编译 Wayland 后端" >&2
fi

for src in "${XWIN_WATCH_SOURCES[@]}"; do
    record_compile \
        "$XWIN_WATCH_TOOL" \
        "$src" \
        "$HYPS_CC" "${XWIN_WATCH_FLAGS[@]}" "$src"
done

# 生成 compile_commands.json 文件

output
