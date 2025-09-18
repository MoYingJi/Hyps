// 修改自 everything411 的 kill-genshin.c
// https://gist.github.com/everything411/a4ebb2e3479711bd6529e58bff553a34

// 编译: `gcc kill-target.c -o kill-target -lX11`

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <unistd.h>
#include <time.h>
#include <string.h>
#include <stdlib.h>
#include <getopt.h>

int main(int argc, char *argv[]) {
    const char *target_window = NULL;
    const char *process_name = NULL;
    int sleep_seconds = 0;
    int w_flag = 0, p_flag = 0, s_flag = 0;

    // 解析命令行参数
    int opt;
    while ((opt = getopt(argc, argv, "w:p:s:")) != -1) {
        switch (opt) {
            case 'w':
                target_window = optarg;
                w_flag = 1;
                break;
            case 'p':
                process_name = optarg;
                p_flag = 1;
                break;
            case 's':
                sleep_seconds = atoi(optarg);
                s_flag = 1;
                break;
            default:
                fprintf(stderr, "Usage: %s [-w window_name] [-p process_name] [-s sleep_seconds]\n", argv[0]);
                exit(EXIT_FAILURE);
        }
    }

    // 检查参数是否完整
    if (!w_flag || !p_flag || !s_flag) {
        fprintf(stderr, "错误: 缺少必要参数\n");
        fprintf(stderr, "Usage: %s [-w window_name] [-p process_name] [-s sleep_seconds]\n", argv[0]);
        exit(EXIT_FAILURE);
    }

    printf("窗口名称: %s\n", target_window);
    printf("进程名称: %s\n", process_name);
    printf("检查间隔: %d 秒\n", sleep_seconds);

    int founded = 0;

    Display *display = XOpenDisplay(NULL);
    if (!display) {
        fprintf(stderr, "无法打开 X Display\n");
        exit(EXIT_FAILURE);
    }

    while (1) {
        sleep(sleep_seconds);

        // 检查窗口
        int found = 0;

        if (display) {
            Window root = DefaultRootWindow(display);
            Atom net_client_list = XInternAtom(display, "_NET_CLIENT_LIST", False);

            Atom type;
            int format;
            unsigned long nitems, bytes_after;
            unsigned char *data = NULL;

            if (XGetWindowProperty(display, root, net_client_list, 0, 1024, False, XA_WINDOW,
                                  &type, &format, &nitems, &bytes_after, &data) == Success) {

                if (data && nitems > 0) {
                    Window *windows = (Window *)data;
                    
                    for (unsigned long i = 0; i < nitems; i++) {
                        XTextProperty text_prop;
                        if (XGetWMName(display, windows[i], &text_prop)) {
                            if (text_prop.value) {
                                char **list = NULL;
                                int count = 0;
                                if (Xutf8TextPropertyToTextList(display, &text_prop, &list, &count) == Success) {
                                    if (count > 0 && list[0] && strstr(list[0], target_window)) {
                                        found = 1;
                                    }
                                    XFreeStringList(list);
                                }
                            }
                            XFree(text_prop.value);
                        }
                        if (found) break;
                    }
                }
                XFree(data);
            }
        }

        // 输出状态并处理
        time_t now = time(NULL);
        struct tm *tm_info = localtime(&now);
        char time_str[64];
        strftime(time_str, sizeof(time_str), "%H:%M:%S", tm_info);

        if (founded) {
            if (found) {
                printf("[%s] 窗口存在\n", time_str);
            } else {
                printf("[%s] 窗口不存在，执行 killall\n", time_str);
                char command[256];
                snprintf(command, sizeof(command), "killall %s", process_name);
                system(command);
                XCloseDisplay(display);
                return 0;
            }
        } else {
            if (found) {
                printf("[%s] 窗口存在，监测已开始\n", time_str);
                founded = 1;
            } else {
                printf("[%s] 窗口不存在，等待窗口出现\n", time_str);
            }
        }
    }

    XCloseDisplay(display);
    return 0;
}
