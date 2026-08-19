// 部分代码取自 everything411 的 kill-genshin.c，灵感也来源于此
// https://gist.github.com/everything411/a4ebb2e3479711bd6529e58bff553a34

// 编译: `gcc xwin-watch.c -o xwin-watch -lX11` (仅 X11)
//       `gcc xwin-watch.c -o xwin-watch -lX11 -lwayland-client -I. -DHAVE_WAYLAND` (X11 + Wayland)
//
// 优先通过 Wayland 的 wlr-foreign-toplevel-management 协议检测窗口
// (Wayland 合成器上生效，如 niri / sway / Hyprland)
// 检测不到 Wayland 时回退到 X11 的 _NET_CLIENT_LIST (XWayland / X11 会话)

// 已经堆成石山了，将就用吧

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <getopt.h>
#include <signal.h>
#include <unistd.h>

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>

#ifdef HAVE_WAYLAND
#include <wayland-client.h>
#include "wlr-foreign-toplevel-management-unstable-v1.h"
#endif

typedef struct {
    const char *target_window;
    const char *window_exists_cmd;
    const char *window_closed_cmd;
    const char *window_failed_cmd;
    int check_exists_interval;
    int check_closed_interval;
    int max_attempts;
} app_config_t;

// 函数声明
static bool parse_arguments(int argc, char *argv[]);
static void print_usage(const char *program_name);
static void print_arguments();
static void print_current_time();
static void run_command(const char *command);
static bool check_window_exists(Display *display, const char *target_window);
static bool check_window_exists_x11(Display *display, const char *target_window);
static void close_displays();
static void handle_signal_and_exit(int signum);

// 全局变量
static volatile sig_atomic_t g_signal_received = 0;
static bool g_window_found = false;
static Display *g_display = nullptr;

#ifdef HAVE_WAYLAND
// Wayland 后端 (wlr-foreign-toplevel-management)
typedef struct wl_toplevel {
    struct wl_toplevel *next;
    struct zwlr_foreign_toplevel_handle_v1 *handle;
    char *title;
    bool dead;
} wl_toplevel_t;

static struct wl_display *g_wl_display = nullptr;
static struct zwlr_foreign_toplevel_manager_v1 *g_wl_manager = nullptr;
static wl_toplevel_t *g_wl_toplevels = nullptr;

static void wl_handle_title(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, const char *title) {
    (void)handle;
    wl_toplevel_t *node = (wl_toplevel_t *)data;
    free(node->title);
    node->title = strdup(title);
}

static void wl_noop(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle) {
    (void)data;
    (void)handle;
}

static void wl_noop_appid(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, const char *value) {
    (void)data;
    (void)handle;
    (void)value;
}

static void wl_noop_output(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, struct wl_output *output) {
    (void)data;
    (void)handle;
    (void)output;
}

static void wl_noop_state(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, struct wl_array *state) {
    (void)data;
    (void)handle;
    (void)state;
}

static void wl_noop_parent(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle, struct zwlr_foreign_toplevel_handle_v1 *parent) {
    (void)data;
    (void)handle;
    (void)parent;
}

static void wl_handle_closed(void *data, struct zwlr_foreign_toplevel_handle_v1 *handle) {
    (void)handle;
    wl_toplevel_t *node = (wl_toplevel_t *)data;
    if (node->handle) {
        zwlr_foreign_toplevel_handle_v1_destroy(node->handle);
        node->handle = nullptr;
    }
    node->dead = true;
}

static const struct zwlr_foreign_toplevel_handle_v1_listener wl_handle_listener = {
    .title = wl_handle_title,
    .app_id = wl_noop_appid,
    .output_enter = wl_noop_output,
    .output_leave = wl_noop_output,
    .state = wl_noop_state,
    .done = wl_noop,
    .closed = wl_handle_closed,
    .parent = wl_noop_parent,
};

static void wl_manager_toplevel(void *data, struct zwlr_foreign_toplevel_manager_v1 *manager, struct zwlr_foreign_toplevel_handle_v1 *toplevel) {
    (void)data;
    (void)manager;
    wl_toplevel_t *node = calloc(1, sizeof(wl_toplevel_t));
    node->handle = toplevel;
    node->next = g_wl_toplevels;
    g_wl_toplevels = node;
    zwlr_foreign_toplevel_handle_v1_add_listener(toplevel, &wl_handle_listener, node);
}

static void wl_manager_finished(void *data, struct zwlr_foreign_toplevel_manager_v1 *manager) {
    (void)data;
    (void)manager;
}

static const struct zwlr_foreign_toplevel_manager_v1_listener wl_manager_listener = {
    .toplevel = wl_manager_toplevel,
    .finished = wl_manager_finished,
};

static void wl_registry_global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    (void)data;
    (void)version;
    if (strcmp(interface, zwlr_foreign_toplevel_manager_v1_interface.name) == 0 && !g_wl_manager) {
        g_wl_manager = (struct zwlr_foreign_toplevel_manager_v1 *)wl_registry_bind(
            registry, name, &zwlr_foreign_toplevel_manager_v1_interface, 1);
        zwlr_foreign_toplevel_manager_v1_add_listener(g_wl_manager, &wl_manager_listener, nullptr);
    }
}

static const struct wl_registry_listener wl_registry_listener = {
    .global = wl_registry_global,
    .global_remove = nullptr,
};

// 初始化 Wayland 后端，失败时返回 false (回退 X11)
static bool wl_init() {
    g_wl_display = wl_display_connect(nullptr);
    if (!g_wl_display) {
        return false;
    }

    struct wl_registry *registry = wl_display_get_registry(g_wl_display);
    wl_registry_add_listener(registry, &wl_registry_listener, nullptr);
    wl_display_roundtrip(g_wl_display);
    wl_registry_destroy(registry);

    if (!g_wl_manager) {
        wl_display_disconnect(g_wl_display);
        g_wl_display = nullptr;
        return false;
    }

    // 接收已存在的 toplevel 及其标题
    wl_display_roundtrip(g_wl_display);
    return true;
}

// 遍历 Wayland toplevel 列表，标题包含目标字符串即认为窗口存在
static bool check_wl_windows(const char *target_window) {
    // dispatch_pending 只派发已读入队列的事件，不会读 socket；
    // roundtrip 会读取并处理 socket 中的事件 (合成器应答 sync 为毫秒级)
    if (wl_display_roundtrip(g_wl_display) == -1) {
        return false;
    }

    bool found = false;
    wl_toplevel_t *prev = nullptr;
    wl_toplevel_t *node = g_wl_toplevels;
    while (node) {
        if (node->dead) {
            wl_toplevel_t *dead = node;
            if (prev) {
                prev->next = node->next;
            } else {
                g_wl_toplevels = node->next;
            }
            node = node->next;
            free(dead->title);
            free(dead);
            continue;
        }
        if (!found && node->title && strstr(node->title, target_window)) {
            found = true;
        }
        prev = node;
        node = node->next;
    }
    return found;
}
#endif

static app_config_t g_config = {
    .target_window = nullptr,
    .window_exists_cmd = nullptr,
    .window_closed_cmd = nullptr,
    .window_failed_cmd = nullptr,
    .check_exists_interval = 0,
    .check_closed_interval = 0,
    .max_attempts = 0
};

static void signal_handler(const int signum) {
    g_signal_received = signum;
}

int main(const int argc, char *argv[]) {
    if (!parse_arguments(argc, argv)) {
        return EXIT_FAILURE;
    }

    print_arguments();

    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    int attempt_count = 0;
    int sleep_seconds = g_config.check_exists_interval;

    bool any_display = false;

    g_display = XOpenDisplay(nullptr);
    if (g_display) {
        any_display = true;
    }

#ifdef HAVE_WAYLAND
    if (wl_init()) {
        any_display = true;
        printf("窗口检测: Wayland (wlr-foreign-toplevel-management)\n");
        if (!g_display) {
            printf("窗口检测: X11 不可用，仅使用 Wayland\n");
        }
    }
#endif

    if (!any_display) {
        fprintf(stderr, "无法打开 X Display 或 Wayland Display\n");
        return EXIT_FAILURE;
    }

    while (true) {
        sleep(sleep_seconds);
        handle_signal_and_exit(g_signal_received);

        const bool found = check_window_exists(g_display, g_config.target_window);
        print_current_time();

        if (g_window_found) {
            if (found) {
                printf(" 窗口存在 \r");
                fflush(stdout);
            } else {
                printf(" 窗口不存在，监测结束\n");
                run_command(g_config.window_closed_cmd);
                close_displays(); // 防止信号处理器再次关闭
                return EXIT_SUCCESS;
            }
        } else {
            if (found) {
                if (g_config.window_closed_cmd == nullptr) {
                    printf(" 窗口存在，监测已结束");
                    if (g_config.max_attempts > 0){
                        printf(" (尝试次数 %d/%d)", attempt_count, g_config.max_attempts);
                    }
                    puts("");
                    run_command(g_config.window_exists_cmd);
                    close_displays();
                    return EXIT_SUCCESS;
                }
                printf(" 窗口存在，监测已开始");
                if (g_config.max_attempts > 0){
                    printf(" (尝试次数 %d/%d)", attempt_count, g_config.max_attempts);
                }
                puts("");
                run_command(g_config.window_exists_cmd);
                sleep_seconds = g_config.check_closed_interval;
                g_window_found = true;
            } else {
                if (g_config.max_attempts > 0) {
                    attempt_count++;
                    printf(" 等待窗口出现 (%d/%d) \r", attempt_count, g_config.max_attempts);
                    fflush(stdout);
                    if (attempt_count >= g_config.max_attempts) {
                        print_current_time();
                        printf(" 最大尝试次数 (%d) 已用完，退出\n", g_config.max_attempts);
                        if (g_config.window_failed_cmd != nullptr) {
                            run_command(g_config.window_failed_cmd);
                        }
                        close_displays();
                        return EXIT_FAILURE;
                    }
                } else {
                    printf(" 等待窗口出现 \r");
                    fflush(stdout);
                }
            }
        }
    }
}

static bool parse_arguments(const int argc, char *argv[]) {
    bool w_flag = false, s_flag = false;
    bool e_flag = false, c_flag = false;
    bool i_flag = false;
    int opt;
    while ((opt = getopt(argc, argv, "w:a:e:c:f:s:i:")) != -1) {
        switch (opt) {
            case 'w':
                g_config.target_window = optarg;
                w_flag = true; break;
            case 'a':
                g_config.max_attempts = atoi(optarg);
                break;
            case 'e':
                g_config.window_exists_cmd = optarg;
                e_flag = true; break;
            case 'c':
                g_config.window_closed_cmd = optarg;
                c_flag = true; break;
            case 'f':
                g_config.window_failed_cmd = optarg;
                break;
            case 's':
                g_config.check_exists_interval = atoi(optarg);
                s_flag = true; break;
            case 'i':
                g_config.check_closed_interval = atoi(optarg);
                i_flag = true; break;

            default:
                print_usage(argv[0]);
                return false;
        }
    }

    // 检查参数是否完整
    if (!w_flag || !s_flag) {
        fprintf(stderr, "错误: 缺少必要参数\n");
        print_usage(argv[0]);
        return false;
    }
    if (!e_flag && !c_flag) {
        fprintf(stderr, "错误: 你想让我执行啥？让我猜吗喵？\n");
        print_usage(argv[0]);
        return false;
    }

    // 默认监测关闭间隔等于监测打开间隔
    if (!i_flag) {
        g_config.check_closed_interval = g_config.check_exists_interval;
    }

    return true;
}

static void print_usage(const char *program_name) {
    puts("\n用法: ");
    printf("    %s [选项]\n", program_name);
    puts("\n选项: ");
    puts("    -w <窗口名称>                   监控的窗口名称，必填");
    puts("    -a <检查窗口出现最大尝试次数>   检查窗口出现的最大尝试次数，默认为 0，表示无限制");
    puts("    -e <窗口出现命令>               窗口出现时执行的命令，不填写代表不执行");
    puts("    -c <窗口关闭命令>               窗口关闭时执行的命令，不填写代表不检测窗口关闭");
    puts("    -f <检查窗口失败命令>           检查窗口失败时执行的命令，例如最大尝试次数用完");
    puts("    -s <检查窗口出现的间隔>         检查窗口出现的间隔，必填");
    puts("    -i <检查窗口关闭的间隔>         检查窗口关闭的间隔，默认等于检查窗口出现的间隔");
}

static void print_arguments() {
    printf("窗口名称: %s\n", g_config.target_window);
    puts("=== 窗口出现 ===");
    if (g_config.window_exists_cmd != nullptr) {
        printf("执行命令: %s\n", g_config.window_exists_cmd);
    }
    printf("检查间隔: %d 秒\n", g_config.check_exists_interval);
    if (g_config.max_attempts > 0) {
        printf("最大尝试次数: %d\n", g_config.max_attempts);
        if (g_config.window_failed_cmd != nullptr) {
            puts("=== 检查失败 ===");
            printf("执行命令: %s\n", g_config.window_failed_cmd);
        }
    }
    if (g_config.window_closed_cmd != nullptr) {
        puts("=== 窗口关闭 ===");
        printf("执行命令: %s\n", g_config.window_closed_cmd);
        printf("检查间隔: %d 秒\n", g_config.check_closed_interval);
    }
}

static void handle_signal_and_exit(const int signum) {
    if (signum) {
        printf("\n收到信号 %d，开始清理...\n", signum);

        // 保证脚本执行逻辑完整
        if (g_window_found) {
            if (g_config.window_closed_cmd != nullptr) {
                printf("执行窗口关闭命令...\n");
                run_command(g_config.window_closed_cmd);
            }
        } else {
            if (g_config.window_failed_cmd != nullptr) {
                printf("执行检查失败命令...\n");
                run_command(g_config.window_failed_cmd);
            }
        }

        close_displays();

        exit(signum);
    }
}

static void print_current_time() {
    const time_t now = time(nullptr);
    const struct tm *tm_info = localtime(&now);
    char time_str[64];
    strftime(time_str, sizeof(time_str), "%H:%M:%S", tm_info);
    printf("[%s]", time_str);
}

static void run_command(const char *command) {
    if (command != nullptr) {
        print_current_time();
        printf(" 运行命令: %s\n", command);
        system(command);
    }
}

static void close_displays() {
    if (g_display) {
        XCloseDisplay(g_display);
        g_display = nullptr;
    }
#ifdef HAVE_WAYLAND
    if (g_wl_display) {
        wl_display_disconnect(g_wl_display);
        g_wl_display = nullptr;
    }
#endif
}

static bool check_window_exists(Display *display, const char *target_window) {
#ifdef HAVE_WAYLAND
    if (g_wl_display && check_wl_windows(target_window)) {
        return true;
    }
#endif
    if (!display) {
        return false;
    }
    return check_window_exists_x11(display, target_window);
}

static bool check_window_exists_x11(Display *display, const char *target_window) {
    const Window root = DefaultRootWindow(display);
    const Atom net_client_list = XInternAtom(display, "_NET_CLIENT_LIST", False);

    Atom type;
    int format;
    unsigned long nitems, bytes_after;
    unsigned char *data = nullptr;

    if (XGetWindowProperty(display, root, net_client_list, 0, 1024, False, XA_WINDOW,
                           &type, &format, &nitems, &bytes_after, &data) != Success) {
        return false;
    }

    if (!data || nitems == 0) {
        XFree(data);
        return false;
    }

    const Window *windows = (Window *) data;
    bool found = false;

    for (unsigned long i = 0; i < nitems; i++) {
        XTextProperty text_prop;
        if (XGetWMName(display, windows[i], &text_prop) && text_prop.value) {
            char **list = nullptr;
            int count = 0;
            if (Xutf8TextPropertyToTextList(display, &text_prop, &list, &count) == Success) {
                if (count > 0 && list[0] && strstr(list[0], target_window)) {
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
