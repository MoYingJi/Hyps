#ifdef HAVE_X11
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <string.h>

#include "backends.h"

static Display *g_x11_display = nullptr;

static bool x11_backend_init() {
    g_x11_display = XOpenDisplay(nullptr);
    if (!g_x11_display) {
        return false;
    }
    // 监听根窗口属性变化，_NET_CLIENT_LIST 更新时会收到 PropertyNotify，
    // 从而事件驱动地唤醒 poll，而不是按间隔轮询。
    XSelectInput(g_x11_display, DefaultRootWindow(g_x11_display), PropertyChangeMask);
    return true;
}

static int x11_backend_fd() {
    if (!g_x11_display) {
        return -1;
    }
    return ConnectionNumber(g_x11_display);
}

static void x11_backend_dispatch() {
    if (!g_x11_display) {
        return;
    }
    // 排空已就绪的 X 事件，让 fd 不再可读，避免 busy loop。
    while (XPending(g_x11_display) > 0) {
        XEvent event;
        XNextEvent(g_x11_display, &event);
    }
}

// 窗口在列表读取后可能已被销毁，此时的 X 错误应视为读取失败并跳过，而不是让 Xlib 默认处理函数终止进程
static volatile bool g_x11_request_failed = false;

static int x11_error_handler(Display *display, XErrorEvent *event) {
    (void)display;
    (void)event;
    g_x11_request_failed = true;
    return 0;
}

// 读取窗口的 WM_NAME，按 UTF-8 转换后取第一项与目标做逐字节比较
static bool window_title_equals(Display *display, Window window, const char *target_window) {
    XTextProperty prop = {};
    char **list = nullptr;
    int count = 0;
    bool equal = false;

    g_x11_request_failed = false;
    const bool got_prop = XGetTextProperty(display, window, &prop, XA_WM_NAME);
    if (!g_x11_request_failed && got_prop && prop.value && prop.nitems > 0) {
        if (Xutf8TextPropertyToTextList(display, &prop, &list, &count) == Success && list && count > 0) {
            equal = strcmp(list[0], target_window) == 0;
        }
    }

    if (list) {
        XFreeStringList(list);
    }
    if (prop.value) {
        XFree(prop.value);
    }
    return equal;
}

static bool x11_backend_check(const char *target_window) {
    if (!g_x11_display) {
        return false;
    }

    // only_if_exists 为 True: 属性名不存在时返回 None，不会在 X 服务器上新建 atom
    const Atom client_list = XInternAtom(g_x11_display, "_NET_CLIENT_LIST", True);
    if (client_list == None) {
        return false;
    }

    g_x11_request_failed = false;
    Atom actual_type = None;
    int actual_format = 0;
    unsigned long count = 0;
    unsigned long bytes_after = 0;
    unsigned char *data = nullptr;
    const XErrorHandler previous_handler = XSetErrorHandler(x11_error_handler);
    const int status = XGetWindowProperty(g_x11_display, DefaultRootWindow(g_x11_display),
                                          client_list, 0, 1024, False, XA_WINDOW,
                                          &actual_type, &actual_format,
                                          &count, &bytes_after, &data);

    bool found = false;
    if (status == Success && !g_x11_request_failed && data && count > 0 && actual_format == 32) {
        auto const windows = (const Window *)data;
        for (unsigned long i = 0; i < count && !found; i++) {
            found = window_title_equals(g_x11_display, windows[i], target_window);
        }
    }
    XSetErrorHandler(previous_handler);

    if (data) {
        XFree(data);
    }
    return found;
}

static void x11_backend_close() {
    if (g_x11_display) {
        XCloseDisplay(g_x11_display);
        g_x11_display = nullptr;
    }
}

static const char *x11_backend_name() {
    return "X11 (_NET_CLIENT_LIST)";
}

window_backend_t x11_backend = {
    .name = x11_backend_name,
    .init = x11_backend_init,
    .fd = x11_backend_fd,
    .dispatch = x11_backend_dispatch,
    .check = x11_backend_check,
    .close = x11_backend_close,
};
#endif
