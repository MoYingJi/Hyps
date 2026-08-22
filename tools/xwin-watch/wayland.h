#ifndef WAYLAND_H
#define WAYLAND_H

#include <stdint.h>

struct wl_registry;

typedef struct wayland_extension {
    const char *name;
    const char *interface_name;
    uint32_t max_version;
    void (*bind)(struct wl_registry *registry, uint32_t name, uint32_t version);
    bool (*check)(const char *target_window);
    void (*close)(void);
} wayland_extension_t;

void wayland_register_extension(wayland_extension_t *ext);

#endif
