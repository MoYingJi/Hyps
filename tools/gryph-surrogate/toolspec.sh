#!/hint/bash
# shellcheck disable=SC2034 # 由 lib/utils/toolspec.sh 读取

# gryph-surrogate: Windows 替身父进程 (见 lib/games/endfield.sh), 使用 mingw 交叉编译

TOOLSPEC_TOOLCHAIN=mingw
TOOLSPEC_SOURCES=(gryph-surrogate.c)
TOOLSPEC_CFLAGS=(-municode -mwindows -static)
