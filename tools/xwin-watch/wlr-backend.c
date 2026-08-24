#ifdef HAVE_WLR
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>

#include "generated/wlr-foreign-toplevel-management-unstable-v1.h"
#include "wayland.h"

typedef struct wlr_toplevel {
    struct wlr_toplevel *next;
    struct zwlr_foreign_toplevel_handle_v1 *handle;
    char *title;
    bool dead;
} wlr_toplevel_t;

static struct zwlr_foreign_toplevel_manager_v1 *g_wlr_manager = NULL;
static wlr_toplevel_t *g_wlr_toplevels = NULL;

static void wlr_handle_title(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, const char *title) {
    (void)handle;
    auto const node = (wlr_toplevel_t *)data;
    free(node->title);
    node->title = strdup(title);
}

static void wlr_noop(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle) {
    (void)data;
    (void)handle;
}

static void wlr_noop_appid(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, const char *value) {
    (void)data;
    (void)handle;
    (void)value;
}

static void wlr_noop_output(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, struct wl_output *output) {
    (void)data;
    (void)handle;
    (void)output;
}

static void wlr_noop_state(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, struct wl_array *state) {
    (void)data;
    (void)handle;
    (void)state;
}

static void wlr_noop_parent(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle,
                            struct zwlr_foreign_toplevel_handle_v1 *parent) {
    (void)data;
    (void)handle;
    (void)parent;
}

static void wlr_handle_closed(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle) {
    (void)handle;
    auto const node = (wlr_toplevel_t *)data;
    if (node->handle) {
        zwlr_foreign_toplevel_handle_v1_destroy(node->handle);
        node->handle = NULL;
    }
    node->dead = true;
}

static const struct zwlr_foreign_toplevel_handle_v1_listener wlr_handle_listener = {
    .title = wlr_handle_title,
    .app_id = wlr_noop_appid,
    .output_enter = wlr_noop_output,
    .output_leave = wlr_noop_output,
    .state = wlr_noop_state,
    .done = wlr_noop,
    .closed = wlr_handle_closed,
    .parent = wlr_noop_parent,
};

static void wlr_manager_toplevel(void *data, struct zwlr_foreign_toplevel_manager_v1 *manager,
                                 struct zwlr_foreign_toplevel_handle_v1 *toplevel) {
    (void)data;
    (void)manager;
    wlr_toplevel_t *node = calloc(1, sizeof(wlr_toplevel_t));
    node->handle = toplevel;
    node->next = g_wlr_toplevels;
    g_wlr_toplevels = node;
    zwlr_foreign_toplevel_handle_v1_add_listener(toplevel, &wlr_handle_listener, node);
}

static void wlr_manager_finished(void *data, struct zwlr_foreign_toplevel_manager_v1 *manager) {
    (void)data;
    (void)manager;
}

static const struct zwlr_foreign_toplevel_manager_v1_listener wlr_manager_listener = {
    .toplevel = wlr_manager_toplevel,
    .finished = wlr_manager_finished,
};

static void wlr_bind(struct wl_registry *registry, const uint32_t name, const uint32_t version) {
    (void)version;
    g_wlr_manager = (struct zwlr_foreign_toplevel_manager_v1 *)wl_registry_bind(
        registry, name, &zwlr_foreign_toplevel_manager_v1_interface, 1);
    zwlr_foreign_toplevel_manager_v1_add_listener(g_wlr_manager, &wlr_manager_listener, NULL);
}

static bool wlr_check(const char *target_window) {
    bool found = false;
    wlr_toplevel_t *prev = NULL;
    wlr_toplevel_t *node = g_wlr_toplevels;
    while (node) {
        if (node->dead) {
            wlr_toplevel_t *dead = node;
            if (prev) {
                prev->next = node->next;
            } else {
                g_wlr_toplevels = node->next;
            }
            node = node->next;
            free(dead->title);
            free(dead);
            continue;
        }
        if (!found && node->title && strcmp(node->title, target_window) == 0) {
            found = true;
        }
        prev = node;
        node = node->next;
    }
    return found;
}

static void wlr_close(void) {
    if (g_wlr_manager) {
        zwlr_foreign_toplevel_manager_v1_destroy(g_wlr_manager);
        g_wlr_manager = NULL;
    }
    wlr_toplevel_t *node = g_wlr_toplevels;
    while (node) {
        wlr_toplevel_t *next = node->next;
        if (node->handle) {
            zwlr_foreign_toplevel_handle_v1_destroy(node->handle);
        }
        free(node->title);
        free(node);
        node = next;
    }
    g_wlr_toplevels = NULL;
}

static wayland_extension_t g_wlr_extension = {
    .name = "wlr-foreign-toplevel-management",
    .max_version = 1,
    .bind = wlr_bind,
    .check = wlr_check,
    .close = wlr_close,
};

static void wlr_register(void) __attribute__((constructor));
static void wlr_register(void) {
    g_wlr_extension.interface_name = zwlr_foreign_toplevel_manager_v1_interface.name;
    wayland_register_extension(&g_wlr_extension);
}
#endif
