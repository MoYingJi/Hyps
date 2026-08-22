#ifndef BACKENDS_H
#define BACKENDS_H

// 统一后端抽象: X11 与 Wayland 都实现同一接口，主程序通过它事件驱动地监听窗口变化。
typedef struct window_backend {
    const char *(*name)(void);                 // 检测方式显示名，如 "X11 (_NET_CLIENT_LIST)"
    bool (*init)(void);                        // 初始化，返回是否可用
    int (*fd)(void);                           // 供 poll 监听的 fd，-1 表示无
    void (*dispatch)(void);                    // 处理已就绪的事件，保持内部状态最新
    bool (*check)(const char *target_window);  // 检查目标窗口是否存在
    void (*close)(void);                       // 释放资源
} window_backend_t;

#ifdef HAVE_X11
extern window_backend_t x11_backend;
#endif

#ifdef HAVE_WAYLAND
extern window_backend_t wayland_backend;
#endif

#endif
