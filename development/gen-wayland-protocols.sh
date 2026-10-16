#!/usr/bin/bash

# 生成 Wayland 协议的客户端文件
# 实际运行时不用这个, 这些文件会被提交到 git, 有变动再用

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROTOCOL_DIR="$ROOT/tools/xwin-watch/protocols"
GENERATED_DIR="$ROOT/tools/xwin-watch/generated"

if ! command -v wayland-scanner >/dev/null 2>&1; then
    echo "wayland-scanner 未安装" >&2
    exit 1
fi

shopt -s nullglob
protocols=("$PROTOCOL_DIR"/*.xml)
if (("${#protocols[@]}" == 0)); then
    echo "未找到 Wayland 协议 XML 文件: $PROTOCOL_DIR" >&2
    exit 1
fi

mkdir -p "$GENERATED_DIR"

for protocol in "${protocols[@]}"; do
    name="${protocol##*/}"
    name="${name%.xml}"

    wayland-scanner client-header "$protocol" "$GENERATED_DIR/$name.h"
    wayland-scanner private-code "$protocol" "$GENERATED_DIR/$name.c"
done
