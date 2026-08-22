#ifdef HAVE_EXT
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>

#include "generated/ext-foreign-toplevel-list-v1.h"
#include "wayland.h"

typedef struct ext_toplevel {
    struct ext_toplevel *next;
    struct ext_foreign_toplevel_handle_v1 *handle;
    char *title;
    bool dead;
} ext_toplevel_t;

static struct ext_foreign_toplevel_list_v1 *g_ext_list = NULL;
static ext_toplevel_t *g_ext_toplevels = NULL;

static void ext_handle_title(void *data, struct ext_foreign_toplevel_handle_v1 *handle, const char *title) {
    (void)handle;
    const auto node = (ext_toplevel_t *)data;
    free(node->title);
    node->title = strdup(title);
}

static void ext_handle_done(void *data, struct ext_foreign_toplevel_handle_v1 *handle) {
    (void)data;
    (void)handle;
}

static void ext_handle_closed(void *data, struct ext_foreign_toplevel_handle_v1 *handle) {
    (void)handle;
    const auto node = (ext_toplevel_t *)data;
    if (node->handle) {
        ext_foreign_toplevel_handle_v1_destroy(node->handle);
        node->handle = NULL;
    }
    node->dead = true;
}

static void ext_handle_appid(void *data, struct ext_foreign_toplevel_handle_v1 *handle, const char *value) {
    (void)data;
    (void)handle;
    (void)value;
}

static const struct ext_foreign_toplevel_handle_v1_listener ext_handle_listener = {
    .closed = ext_handle_closed,
    .done = ext_handle_done,
    .title = ext_handle_title,
    .app_id = ext_handle_appid,
    .identifier = ext_handle_appid,
};

static void ext_list_toplevel(void *data, struct ext_foreign_toplevel_list_v1 *list,
                              struct ext_foreign_toplevel_handle_v1 *toplevel) {
    (void)data;
    (void)list;
    ext_toplevel_t *node = calloc(1, sizeof(ext_toplevel_t));
    node->handle = toplevel;
    node->next = g_ext_toplevels;
    g_ext_toplevels = node;
    ext_foreign_toplevel_handle_v1_add_listener(toplevel, &ext_handle_listener, node);
}

static void ext_list_finished(void *data, struct ext_foreign_toplevel_list_v1 *list) {
    (void)data;
    (void)list;
}

static const struct ext_foreign_toplevel_list_v1_listener ext_list_listener = {
    .toplevel = ext_list_toplevel,
    .finished = ext_list_finished,
};

static void ext_bind(struct wl_registry *registry, const uint32_t name, const uint32_t version) {
    (void)version;
    g_ext_list = (struct ext_foreign_toplevel_list_v1 *)wl_registry_bind(
        registry, name, &ext_foreign_toplevel_list_v1_interface, 1);
    ext_foreign_toplevel_list_v1_add_listener(g_ext_list, &ext_list_listener, NULL);
}

static bool ext_check(const char *target_window) {
    bool found = false;
    ext_toplevel_t *prev = NULL;
    ext_toplevel_t *node = g_ext_toplevels;
    while (node) {
        if (node->dead) {
            ext_toplevel_t *dead = node;
            if (prev) {
                prev->next = node->next;
            } else {
                g_ext_toplevels = node->next;
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

static void ext_close(void) {
    if (g_ext_list) {
        ext_foreign_toplevel_list_v1_destroy(g_ext_list);
        g_ext_list = NULL;
    }
    ext_toplevel_t *node = g_ext_toplevels;
    while (node) {
        ext_toplevel_t *next = node->next;
        if (node->handle) {
            ext_foreign_toplevel_handle_v1_destroy(node->handle);
        }
        free(node->title);
        free(node);
        node = next;
    }
    g_ext_toplevels = NULL;
}

static wayland_extension_t g_ext_extension = {
    .name = "ext-foreign-toplevel-list",
    .max_version = 1,
    .bind = ext_bind,
    .check = ext_check,
    .close = ext_close,
};

static void ext_register(void) __attribute__((constructor));
static void ext_register(void) {
    g_ext_extension.interface_name = ext_foreign_toplevel_list_v1_interface.name;
    wayland_register_extension(&g_ext_extension);
}
#endif
