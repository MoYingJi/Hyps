#ifdef HAVE_X11
#include <string.h>
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>

#include "backends.h"

static Display *g_x11_display = NULL;

static bool x11_backend_init(void) {
    g_x11_display = XOpenDisplay(NULL);
    if (!g_x11_display) {
        return false;
    }
    // 监听根窗口属性变化，_NET_CLIENT_LIST 更新时会收到 PropertyNotify，
    // 从而事件驱动地唤醒 poll，而不是按间隔轮询。
    XSelectInput(g_x11_display, DefaultRootWindow(g_x11_display), PropertyChangeMask);
    return true;
}

static int x11_backend_fd(void) {
    if (!g_x11_display) {
        return -1;
    }
    return ConnectionNumber(g_x11_display);
}

static void x11_backend_dispatch(void) {
    if (!g_x11_display) {
        return;
    }
    // 排空已就绪的 X 事件，让 fd 不再可读，避免 busy loop。
    while (XPending(g_x11_display) > 0) {
        XEvent event;
        XNextEvent(g_x11_display, &event);
    }
}

static bool x11_backend_check(const char *target_window) {
    if (!g_x11_display) {
        return false;
    }
    const Window root = DefaultRootWindow(g_x11_display);
    const Atom net_client_list = XInternAtom(g_x11_display, "_NET_CLIENT_LIST", False);

    Atom type;
    int format;
    unsigned long nitems, bytes_after;
    unsigned char *data = NULL;

    if (XGetWindowProperty(g_x11_display, root, net_client_list, 0, 1024, False, XA_WINDOW,
                           &type, &format, &nitems, &bytes_after, &data) != Success) {
        return false;
    }

    if (!data || nitems == 0) {
        XFree(data);
        return false;
    }

    const Window *windows = (Window *)data;
    bool found = false;

    for (unsigned long i = 0; i < nitems; i++) {
        XTextProperty text_prop;
        if (XGetWMName(g_x11_display, windows[i], &text_prop) && text_prop.value) {
            char **list = NULL;
            int count = 0;
            if (Xutf8TextPropertyToTextList(g_x11_display, &text_prop, &list, &count) == Success) {
                if (count > 0 && list[0] && strcmp(list[0], target_window) == 0) {
                    found = true;
                }
                XFreeStringList(list);
            }
            XFree(text_prop.value);
        }
        if (found) break;
    }

    XFree(data);
    return found;
}

static void x11_backend_close(void) {
    if (g_x11_display) {
        XCloseDisplay(g_x11_display);
        g_x11_display = NULL;
    }
}

static const char *x11_backend_name(void) {
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