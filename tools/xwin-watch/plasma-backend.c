#ifdef HAVE_PLASMA
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>

#include "generated/plasma-window-management.h"
#include "wayland.h"

#define PLASMA_MAX_VERSION 18

typedef struct plasma_toplevel {
    struct plasma_toplevel *next;
    struct org_kde_plasma_window *handle;
    char *title;
    bool dead;
} plasma_toplevel_t;

static struct org_kde_plasma_window_management *g_plasma_wm = NULL;
static plasma_toplevel_t *g_plasma_toplevels = NULL;

static void plasma_handle_title(void *data, struct org_kde_plasma_window *window, const char *title) {
    (void)window;
    plasma_toplevel_t *node = (plasma_toplevel_t *)data;
    free(node->title);
    node->title = strdup(title);
}

static void plasma_handle_unmapped(void *data, struct org_kde_plasma_window *window) {
    (void)window;
    plasma_toplevel_t *node = (plasma_toplevel_t *)data;
    if (node->handle) {
        org_kde_plasma_window_destroy(node->handle);
        node->handle = NULL;
    }
    node->dead = true;
}

static void plasma_noop(void *data, struct org_kde_plasma_window *window) {
    (void)data;
    (void)window;
}

static void plasma_noop_str(void *data, struct org_kde_plasma_window *window, const char *value) {
    (void)data;
    (void)window;
    (void)value;
}

static void plasma_noop_state(void *data, struct org_kde_plasma_window *window, uint32_t flags) {
    (void)data;
    (void)window;
    (void)flags;
}

static void plasma_noop_vdesk(void *data, struct org_kde_plasma_window *window, int32_t number) {
    (void)data;
    (void)window;
    (void)number;
}

static void plasma_noop_geometry(void *data, struct org_kde_plasma_window *window, int32_t x, int32_t y,
                                uint32_t width, uint32_t height) {
    (void)data;
    (void)window;
    (void)x;
    (void)y;
    (void)width;
    (void)height;
}

static void plasma_noop_parent(void *data, struct org_kde_plasma_window *window, struct org_kde_plasma_window *parent) {
    (void)data;
    (void)window;
    (void)parent;
}

static void plasma_noop_menu(void *data, struct org_kde_plasma_window *window, const char *service_name,
                             const char *object_path) {
    (void)data;
    (void)window;
    (void)service_name;
    (void)object_path;
}

static const struct org_kde_plasma_window_listener plasma_window_listener = {
    .title_changed = plasma_handle_title,
    .app_id_changed = plasma_noop_str,
    .state_changed = plasma_noop_state,
    .virtual_desktop_changed = plasma_noop_vdesk,
    .themed_icon_name_changed = plasma_noop_str,
    .unmapped = plasma_handle_unmapped,
    .initial_state = plasma_noop,
    .parent_window = plasma_noop_parent,
    .geometry = plasma_noop_geometry,
    .icon_changed = plasma_noop,
    .pid_changed = plasma_noop_state,
    .virtual_desktop_entered = plasma_noop_str,
    .virtual_desktop_left = plasma_noop_str,
    .application_menu = plasma_noop_menu,
    .activity_entered = plasma_noop_str,
    .activity_left = plasma_noop_str,
    .resource_name_changed = plasma_noop_str,
    .client_geometry = plasma_noop_geometry,
};

static void plasma_add_window(struct org_kde_plasma_window *window) {
    plasma_toplevel_t *node = calloc(1, sizeof(plasma_toplevel_t));
    node->handle = window;
    node->next = g_plasma_toplevels;
    g_plasma_toplevels = node;
    org_kde_plasma_window_add_listener(window, &plasma_window_listener, node);
}

static void plasma_wm_window(void *data, struct org_kde_plasma_window_management *wm, uint32_t id) {
    (void)data;
    plasma_add_window(org_kde_plasma_window_management_get_window(wm, id));
}

static void plasma_wm_window_with_uuid(void *data, struct org_kde_plasma_window_management *wm, uint32_t id,
                                       const char *uuid) {
    (void)data;
    (void)id;
    plasma_add_window(org_kde_plasma_window_management_get_window_by_uuid(wm, uuid));
}

static void plasma_wm_noop(void *data, struct org_kde_plasma_window_management *wm) {
    (void)data;
    (void)wm;
}

static void plasma_wm_noop_state(void *data, struct org_kde_plasma_window_management *wm, uint32_t state) {
    (void)data;
    (void)wm;
    (void)state;
}

static void plasma_wm_noop_order(void *data, struct org_kde_plasma_window_management *wm, struct wl_array *ids) {
    (void)data;
    (void)wm;
    (void)ids;
}

static void plasma_wm_noop_order_str(void *data, struct org_kde_plasma_window_management *wm, const char *uuids) {
    (void)data;
    (void)wm;
    (void)uuids;
}

static const struct org_kde_plasma_window_management_listener plasma_wm_listener = {
    .show_desktop_changed = plasma_wm_noop_state,
    .window = plasma_wm_window,
    .stacking_order_changed = plasma_wm_noop_order,
    .stacking_order_uuid_changed = plasma_wm_noop_order_str,
    .window_with_uuid = plasma_wm_window_with_uuid,
    .stacking_order_changed_2 = plasma_wm_noop,
};

static void plasma_bind(struct wl_registry *registry, uint32_t name, uint32_t version) {
    uint32_t bind_version = version < PLASMA_MAX_VERSION ? version : PLASMA_MAX_VERSION;
    g_plasma_wm = (struct org_kde_plasma_window_management *)wl_registry_bind(
        registry, name, &org_kde_plasma_window_management_interface, bind_version);
    org_kde_plasma_window_management_add_listener(g_plasma_wm, &plasma_wm_listener, NULL);
}

static bool plasma_check(const char *target_window) {
    bool found = false;
    plasma_toplevel_t *prev = NULL;
    plasma_toplevel_t *node = g_plasma_toplevels;
    while (node) {
        if (node->dead) {
            plasma_toplevel_t *dead = node;
            if (prev) {
                prev->next = node->next;
            } else {
                g_plasma_toplevels = node->next;
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

static void plasma_close(void) {
    if (g_plasma_wm) {
        org_kde_plasma_window_management_destroy(g_plasma_wm);
        g_plasma_wm = NULL;
    }
    plasma_toplevel_t *node = g_plasma_toplevels;
    while (node) {
        plasma_toplevel_t *next = node->next;
        if (node->handle) {
            org_kde_plasma_window_destroy(node->handle);
        }
        free(node->title);
        free(node);
        node = next;
    }
    g_plasma_toplevels = NULL;
}

static wayland_extension_t g_plasma_extension = {
    .name = "org_kde_plasma_window_management",
    .max_version = PLASMA_MAX_VERSION,
    .bind = plasma_bind,
    .check = plasma_check,
    .close = plasma_close,
};

static void plasma_register(void) __attribute__((constructor));
static void plasma_register(void) {
    g_plasma_extension.interface_name = org_kde_plasma_window_management_interface.name;
    wayland_register_extension(&g_plasma_extension);
}
#endif
