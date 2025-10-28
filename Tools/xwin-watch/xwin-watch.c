// 部分代码取自 everything411 的 kill-genshin.c，灵感也来源于此
// https://gist.github.com/everything411/a4ebb2e3479711bd6529e58bff553a34

// 编译: `gcc xwin-watch.c -o xwin-watch -lX11`

// 已经堆成石山了，将就用吧

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <unistd.h>
#include <time.h>
#include <string.h>
#include <stdlib.h>
#include <getopt.h>

typedef struct {
    const char *target_window;
    const char *window_exists_cmd;
    const char *window_closed_cmd;
    int check_exists_interval;
    int check_closed_interval;
    int max_attempts;
} app_config_t;

static bool check_window_exists(Display *display, const char *target_window);
static void print_usage(const char *program_name);
static bool parse_arguments(int argc, char *argv[], app_config_t *config);
static void print_current_time();
static void run_command(const char *command);

int main(const int argc, char *argv[]) {
    app_config_t config = { nullptr };
    
    if (!parse_arguments(argc, argv, &config)) {
        exit(EXIT_FAILURE);
    }

    printf(    "窗口名称: %s\n",     config.target_window);         // w
    puts("=== 窗口出现 ===");
    if (config.window_exists_cmd != nullptr) {
        printf("执行命令: %s\n",     config.window_exists_cmd);     // e
    }
    printf(    "检查间隔: %d 秒\n",  config.check_exists_interval); // s
    if (config.max_attempts > 0) {
        printf("最大尝试次数: %d\n", config.max_attempts);          // a
    }
    if (config.window_closed_cmd != nullptr) {
        puts("=== 窗口关闭 ===");
        printf("执行命令: %s\n",     config.window_closed_cmd);     // c
        printf("检查间隔: %d 秒\n",  config.check_closed_interval); // i
    }

    bool window_found = false;
    int attempt_count = 0;
    int sleep_seconds = config.check_exists_interval;

    Display *display = XOpenDisplay(nullptr);
    if (!display) {
        fprintf(stderr, "无法打开 X Display\n");
        exit(EXIT_FAILURE);
    }

    while (1) {
        sleep(sleep_seconds);

        const bool found = check_window_exists(display, config.target_window);
        print_current_time();

        if (window_found) {
            if (found) {
                printf(" 窗口存在 \r");
                fflush(stdout);
            } else {
                printf(" 窗口不存在，监测结束\n");
                // 因为下面判断过了, 进入 window_found 分支的一定要执行 window_closed_cmd
                run_command(config.window_closed_cmd);
                XCloseDisplay(display);
                return 0;
            }
        } else {
            if (found) {
                if (config.window_closed_cmd == nullptr) {
                    printf(" 窗口存在，监测已结束");
                    if (config.max_attempts > 0){
                        printf(" (尝试次数 %d/%d)", attempt_count, config.max_attempts);
                    }
                    puts("");
                    run_command(config.window_exists_cmd);
                    XCloseDisplay(display);
                    return 0;
                }
                printf(" 窗口存在，监测已开始");
                if (config.max_attempts > 0){
                    printf(" (尝试次数 %d/%d)", attempt_count, config.max_attempts);
                }
                puts("");
                run_command(config.window_exists_cmd);
                sleep_seconds = config.check_closed_interval;
                window_found = true;
            } else {
                if (config.max_attempts > 0) {
                    attempt_count++;
                    printf(" 等待窗口出现 (%d/%d) \r", attempt_count, config.max_attempts);
                    fflush(stdout);
                    if (attempt_count >= config.max_attempts) {
                        print_current_time();
                        printf(" 最大尝试次数 (%d) 已用完，退出\n", config.max_attempts);
                        XCloseDisplay(display);
                        exit(EXIT_FAILURE);
                    }
                } else {
                    printf(" 等待窗口出现 \r");
                    fflush(stdout);
                }
            }
        }
    }
}

static bool parse_arguments(int argc, char *argv[], app_config_t *config) {
    bool w_flag = false, s_flag = false;
    bool e_flag = false, c_flag = false;
    bool i_flag = false;
    int opt;
    while ((opt = getopt(argc, argv, "w:a:e:c:s:i:")) != -1) {
        switch (opt) {
            case 'w':
                config -> target_window = optarg;
                w_flag = true; break;
            case 'a':
                config -> max_attempts = atoi(optarg);
                break;
            case 'e':
                config -> window_exists_cmd = optarg;
                e_flag = true; break;
            case 'c':
                config -> window_closed_cmd = optarg;
                c_flag = true; break;
            case 's':
                config -> check_exists_interval = atoi(optarg);
                s_flag = true; break;
            case 'i':
                config -> check_closed_interval = atoi(optarg);
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
        config -> check_closed_interval = config -> check_exists_interval;
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
    puts("    -s <检查窗口出现的间隔>         检查窗口出现的间隔，必填");
    puts("    -i <检查窗口关闭的间隔>         检查窗口关闭的间隔，默认等于检查窗口出现的间隔");
}

static bool check_window_exists(Display *display, const char *target_window) {
    Window root = DefaultRootWindow(display);
    Atom net_client_list = XInternAtom(display, "_NET_CLIENT_LIST", False);

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

    Window *windows = (Window *) data;
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
