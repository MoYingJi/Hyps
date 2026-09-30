// 部分代码取自 everything411 的 kill-genshin.c，灵感也来源于此
// https://gist.github.com/everything411/a4ebb2e3479711bd6529e58bff553a34

// 编译: 参考项目的 lib/features/xwin_watch.sh
//
// 窗口检测完全事件驱动: 主循环 poll 各后端 (Wayland/X11) 的 fd，
// 窗口出现/关闭事件立即唤醒；poll 仅在出现超时 (-a) 的剩余时间点唤醒以执行超时逻辑。
// Wayland 与 X11 都通过统一的 window_backend_t 接口接入，可同时启用互为兜底。

#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <locale.h>

#include "backends.h"

#define MAX_BACKENDS 2

typedef struct {
    const char *target_window;
    int appear_timeout;
    bool watch_closed; // false 时窗口出现后立即退出，不再等待关闭
} app_config_t;

// 函数声明
static bool parse_arguments(int argc, char *argv[]);
static void print_usage(const char *program_name);
static void print_arguments(void);
static void log_timestamped(const char *fmt, ...);
static void emit_event(const char *event);
static bool check_window_exists(const char *target_window);
static void close_displays(void);
static void handle_signal_and_exit(int signum);

// 全局变量
static volatile sig_atomic_t g_signal_received = 0;
static bool g_window_found = false;
static time_t g_wait_start = 0; // 开始等待窗口出现的时间戳 (秒)

static window_backend_t *g_backends[MAX_BACKENDS];
static int g_backend_count = 0;

// 状态机: 处理一次检查结果，返回 -1 表示继续，>=0 表示退出码
static int handle_state(bool found);

static app_config_t g_config = {
    .target_window = NULL,
    .appear_timeout = 0,
    .watch_closed = false
};

// 窗口出现超时判断: 返回 true 表示已超时
static bool wait_timed_out(void) {
    if (g_config.appear_timeout <= 0 || g_wait_start == 0) {
        return false;
    }
    return (time(NULL) - g_wait_start) >= g_config.appear_timeout;
}

// poll 的超时毫秒数:
// - 已找到窗口: 阻塞等待关闭事件，不设超时
// - 等待窗口出现: 若有出现超时 (-a)，在剩余时间点唤醒以执行超时逻辑
static int wait_poll_timeout_ms(void) {
    if (g_window_found || g_config.appear_timeout <= 0 || g_wait_start == 0) {
        return -1;
    }
    const int remaining = g_config.appear_timeout - (int)(time(NULL) - g_wait_start);
    return remaining <= 0 ? 0 : remaining * 1000;
}

// 尝试初始化一个后端，成功则加入列表；只打印当前实际应用的那个 (第一个成功初始化的后端)
static void add_backend(window_backend_t *backend) {
    if (g_backend_count >= MAX_BACKENDS || !backend->init()) {
        return;
    }
    if (g_backend_count == 0) {
        fprintf(stderr, "窗口检测: %s\n", backend->name());
    }
    g_backends[g_backend_count++] = backend;
}

static void signal_handler(const int signum) {
    g_signal_received = signum;
}

int main(const int argc, char *argv[]) {
    // 必须设置 locale，否则 Xutf8TextPropertyToTextList 无法转换 UTF-8 窗口标题
    setlocale(LC_ALL, "");

    if (!parse_arguments(argc, argv)) {
        return EXIT_FAILURE;
    }

    print_arguments();

    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    // 初始化所有已编译的后端 (Wayland 优先，X11 兜底)
#ifdef HAVE_WAYLAND
    add_backend(&wayland_backend);
#endif
#ifdef HAVE_X11
    add_backend(&x11_backend);
#endif

    if (g_backend_count == 0) {
        fprintf(stderr, "无法打开 X Display 或 Wayland Display\n");
        return EXIT_FAILURE;
    }

    // 进入事件循环前先派发并检查一次，避免已存在的窗口要等事件
    g_wait_start = time(NULL);
    for (int i = 0; i < g_backend_count; i++) {
        g_backends[i]->dispatch();
    }
    {
        const bool found = check_window_exists(g_config.target_window);
        const int rc = handle_state(found);
        if (rc >= 0) {
            return rc;
        }
    }
    if (!g_window_found) {
        log_timestamped("等待窗口出现");
    }

    while (true) {
        handle_signal_and_exit(g_signal_received);

        struct pollfd pfds[MAX_BACKENDS];
        int n = 0;
        for (int i = 0; i < g_backend_count; i++) {
            const int fd = g_backends[i]->fd();
            if (fd >= 0) {
                pfds[n].fd = fd;
                pfds[n].events = POLLIN;
                n++;
            }
        }

        const int rc = poll(pfds, n, wait_poll_timeout_ms());
        if (rc < 0) {
            // poll 被信号中断，回到循环开头处理信号
            continue;
        }

        // 事件唤醒或超时唤醒都先派发事件，保持窗口列表最新
        for (int i = 0; i < g_backend_count; i++) {
            g_backends[i]->dispatch();
        }

        const bool found = check_window_exists(g_config.target_window);
        const int state_rc = handle_state(found);
        if (state_rc >= 0) {
            return state_rc;
        }
    }
}

// 状态机: 处理一次检查结果，返回 -1 表示继续，>=0 表示退出码
// 事件通过 stdout 逐行输出 (exists/closed/failed)，由调用方 (bash) 读取并分发回调
static int handle_state(const bool found) {
    if (g_window_found) {
        if (!found) {
            log_timestamped("窗口消失，监测结束");
            emit_event("closed");
            close_displays(); // 防止信号处理器再次关闭
            return EXIT_SUCCESS;
        }
    } else {
        if (found) {
            if (g_config.appear_timeout > 0) {
                log_timestamped("窗口出现，监测已开始 (等待 %ld 秒)", (long)(time(NULL) - g_wait_start));
            } else {
                log_timestamped("窗口出现，监测已开始");
            }
            emit_event("exists");
            if (!g_config.watch_closed) {
                close_displays();
                return EXIT_SUCCESS;
            }
            g_window_found = true;
        } else {
            // 窗口未出现: 若已超时则输出失败事件并退出，否则继续等待事件
            if (wait_timed_out()) {
                log_timestamped("窗口出现超时 (%d 秒) 已到，退出", g_config.appear_timeout);
                emit_event("failed");
                close_displays();
                return EXIT_FAILURE;
            }
        }
    }
    return -1;
}

static bool parse_arguments(const int argc, char *argv[]) {
    bool w_flag = false;
    int opt;
    while ((opt = getopt(argc, argv, "w:a:c")) != -1) {
        switch (opt) {
            case 'w':
                g_config.target_window = optarg;
                w_flag = true; break;
            case 'a':
                g_config.appear_timeout = atoi(optarg);
                break;
            case 'c':
                g_config.watch_closed = true;
                break;

            default:
                print_usage(argv[0]);
                return false;
        }
    }

    // 检查参数是否完整
    if (!w_flag) {
        fprintf(stderr, "错误: 缺少必要参数\n");
        print_usage(argv[0]);
        return false;
    }

    return true;
}

static void print_usage(const char *program_name) {
    fprintf(stderr, "\n用法: \n");
    fprintf(stderr, "    %s [选项]\n", program_name);
    fprintf(stderr, "\n选项: \n");
    fprintf(stderr, "    -w <窗口名称>       监控的窗口名称，必填\n");
    fprintf(stderr, "    -a <窗口出现超时>   窗口出现的超时时间（秒），超时后输出 failed 事件并退出，默认为 0，表示无限制\n");
    fprintf(stderr, "    -c                  窗口出现后继续监控，窗口关闭时输出 closed 事件；不指定则窗口出现后立即退出\n");
    fprintf(stderr, "\n事件通过 stdout 逐行输出: exists / closed / failed，其余日志输出到 stderr\n");
}

static void print_arguments(void) {
    fprintf(stderr, "窗口名称: %s\n", g_config.target_window);
    if (g_config.appear_timeout > 0) {
        fprintf(stderr, "窗口出现超时: %d 秒\n", g_config.appear_timeout);
    }
}

static void handle_signal_and_exit(const int signum) {
    if (signum) {
        log_timestamped("收到信号 %d，开始清理...", signum);

        // 保证消费者能收到对应事件
        if (!g_window_found) {
            emit_event("failed");
        } else if (g_config.watch_closed) {
            emit_event("closed");
        }

        close_displays();

        exit(signum);
    }
}

// 输出带时间戳的日志到 stderr，不干扰 stdout 上的事件流
static void log_timestamped(const char *fmt, ...) {
    const time_t now = time(NULL);
    const struct tm *tm_info = localtime(&now);
    char time_str[64];
    strftime(time_str, sizeof(time_str), "%H:%M:%S", tm_info);
    fprintf(stderr, "[%s] ", time_str);

    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);
    fputc('\n', stderr);
}

// 向 stdout 输出一行事件 (exists/closed/failed)，供调用方读取分发
static void emit_event(const char *event) {
    printf("%s\n", event);
    fflush(stdout);
}

static void close_displays(void) {
    for (int i = 0; i < g_backend_count; i++) {
        g_backends[i]->close();
    }
    g_backend_count = 0;
}

static bool check_window_exists(const char *target_window) {
    for (int i = 0; i < g_backend_count; i++) {
        if (g_backends[i]->check(target_window)) {
            return true;
        }
    }
    return false;
}
