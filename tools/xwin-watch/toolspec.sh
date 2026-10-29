#!/hint/bash
# shellcheck disable=SC2034 # 由 lib/utils/toolspec.sh 读取

# xwin-watch: 窗口监控工具 (见 lib/shared/xwin_watch.sh)
# 后端由运行时配置或 pkg-config 决定; 这里只描述每个后端的输入

TOOLSPEC_SOURCES=(xwin-watch.c)
TOOLSPEC_INCLUDES=(.)
TOOLSPEC_DEPS=(
    backends.h
    wayland.h
    generated/wlr-foreign-toplevel-management-unstable-v1.h
    generated/ext-foreign-toplevel-list-v1.h
    generated/plasma-window-management.h
)
TOOLSPEC_BACKENDS=(x11 wayland)

TOOLSPEC_BACKEND_x11_PKG=x11
TOOLSPEC_BACKEND_x11_SOURCES=(x11-backend.c)
TOOLSPEC_BACKEND_x11_DEFINES=(HAVE_X11)
TOOLSPEC_BACKEND_x11_LIBS=(-lX11)

TOOLSPEC_BACKEND_wayland_PKG=wayland-client
TOOLSPEC_BACKEND_wayland_SOURCES=(
    wayland.c
    wlr-backend.c
    generated/wlr-foreign-toplevel-management-unstable-v1.c
    ext-backend.c
    generated/ext-foreign-toplevel-list-v1.c
    plasma-backend.c
    generated/plasma-window-management.c
)
TOOLSPEC_BACKEND_wayland_DEFINES=(HAVE_WAYLAND HAVE_WLR HAVE_EXT HAVE_PLASMA)
TOOLSPEC_BACKEND_wayland_LIBS=(-lwayland-client)
