#!/hint/bash
# shellcheck disable=SC2034 # 由 lib/utils/toolspec.sh 读取

# dll-injector: 通用 Windows DLL 注入器，用 mingw 交叉编译
# 注入器位数必须与被注入进程一致，默认编译 64 位，注入 32 位游戏需改用 i686-w64-mingw32-gcc

TOOLSPEC_TOOLCHAIN=mingw
TOOLSPEC_SOURCES=(dll-injector.c)
TOOLSPEC_CFLAGS=(-municode -mwindows -static)
