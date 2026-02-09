// 部分代码取自 everything411 的 kill-genshin.c，灵感也来源于此
// https://gist.github.com/everything411/a4ebb2e3479711bd6529e58bff553a34

// 编译: `gcc xwin-watch.c -o xwin-watch -lX11`

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
static void handle_signal_and_exit(int signum);

// 全局变量
static volatile sig_atomic_t g_signal_received = 0;
static bool g_window_found = false;
static Display *g_display = nullptr;

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

    g_display = XOpenDisplay(nullptr);
    if (!g_display) {
        fprintf(stderr, "无法打开 X Display\n");
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
                XCloseDisplay(g_display);
                g_display = nullptr; // 防止信号处理器再次关闭
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
                    XCloseDisplay(g_display);
                    g_display = nullptr;
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
                        XCloseDisplay(g_display);
                        g_display = nullptr;
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
        if (signum) {
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

        if (g_display) {
            XCloseDisplay(g_display);
        }

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

static bool check_window_exists(Display *display, const char *target_window) {
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
