#ifdef HAVE_WAYLAND
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <wayland-client.h>

#include "backends.h"
#include "wayland.h"

#define WAYLAND_MAX_EXTENSIONS 8

static struct wl_display *g_display = NULL;
static struct wl_registry *g_registry = NULL;

static wayland_extension_t *g_extensions[WAYLAND_MAX_EXTENSIONS];
static bool g_bound[WAYLAND_MAX_EXTENSIONS];
static int g_extension_count = 0;

static char g_protocol_name[128] = "unknown";

void wayland_register_extension(wayland_extension_t *ext) {
    if (g_extension_count >= WAYLAND_MAX_EXTENSIONS) {
        return;
    }
    g_extensions[g_extension_count] = ext;
    g_bound[g_extension_count] = false;
    g_extension_count++;
}

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
                            const char *interface, uint32_t version) {
    (void)data;
    for (int i = 0; i < g_extension_count; i++) {
        if (g_bound[i]) {
            continue;
        }
        if (strcmp(interface, g_extensions[i]->interface_name) == 0) {
            g_extensions[i]->bind(registry, name, version);
            g_bound[i] = true;
            snprintf(g_protocol_name, sizeof(g_protocol_name), "%s", g_extensions[i]->name);
        }
    }
}

static void registry_global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

static void wayland_close(void);

static bool wayland_init(void) {
    g_display = wl_display_connect(NULL);
    if (!g_display) {
        return false;
    }

    g_registry = wl_display_get_registry(g_display);
    wl_registry_add_listener(g_registry, &registry_listener, NULL);
    wl_display_roundtrip(g_display);

    bool any = false;
    for (int i = 0; i < g_extension_count; i++) {
        if (g_bound[i]) {
            any = true;
            break;
        }
    }
    if (!any) {
        wayland_close();
        return false;
    }

    // 接收已存在的 toplevel 及其标题 (get_window_by_uuid 的响应)
    wl_display_roundtrip(g_display);
    wl_display_roundtrip(g_display);
    return true;
}

static int wayland_fd(void) {
    if (!g_display) {
        return -1;
    }
    return wl_display_get_fd(g_display);
}

static void wayland_dispatch(void) {
    if (!g_display) {
        return;
    }
    // 派发已读入队列的事件 (如 window_with_uuid 触发的 get_window_by_uuid 请求)，
    // 再 roundtrip 等待 KWin 响应这些请求 (窗口标题等) 并派发。
    // roundtrip 会 flush + 读取 socket，合成器应答为毫秒级，不会长时间阻塞。
    wl_display_dispatch_pending(g_display);
    wl_display_roundtrip(g_display);
}

static bool wayland_check(const char *target_window) {
    for (int i = 0; i < g_extension_count; i++) {
        if (g_bound[i] && g_extensions[i]->check && g_extensions[i]->check(target_window)) {
            return true;
        }
    }
    return false;
}

static void wayland_close(void) {
    for (int i = 0; i < g_extension_count; i++) {
        if (g_bound[i] && g_extensions[i]->close) {
            g_extensions[i]->close();
        }
        g_bound[i] = false;
    }
    if (g_registry) {
        wl_registry_destroy(g_registry);
        g_registry = NULL;
    }
    if (g_display) {
        wl_display_disconnect(g_display);
        g_display = NULL;
    }
}

static const char *wayland_backend_name(void) {
    static char name[160];
    snprintf(name, sizeof(name), "Wayland (%s)", g_protocol_name);
    return name;
}

window_backend_t wayland_backend = {
    .name = wayland_backend_name,
    .init = wayland_init,
    .fd = wayland_fd,
    .dispatch = wayland_dispatch,
    .check = wayland_check,
    .close = wayland_close,
};
#endif