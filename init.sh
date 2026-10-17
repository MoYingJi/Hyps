#!/usr/bin/bash

# Hyps 初始化脚本入口
# 等价于 ./scripts/_Hyps init

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

exec "$PROJECT_ROOT/scripts/_Hyps" init "$@"
