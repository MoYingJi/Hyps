// 基于 everything411 的 unlocker.c 修改
// https://github.com/everything411/fpsunlock
// 本修改版尊重并继承原项目许可证，按 MIT 许可，见项目的 licenses/MIT-fpsunlock.txt

// unlocker.c - 为 Linux 原生环境重构的 FPS 解锁工具
//
// 编译命令:
// gcc -o unlocker unlocker.c -std=gnu23 -Wall -Wextra
//
// 无需 sudo 运行（仅需设置一次）:
// 1. 编译程序
// 2. 授予权限: `sudo setcap cap_sys_ptrace+ep ./unlocker`
// 3. 使用普通用户运行
//
// 用法: ./unlocker [--interval MS] [--fifo PATH] [--verbose] <PID> [FPS]

// 为了使用 process_vm_readv / process_vm_writev
// NOLINTBEGIN(bugprone-reserved-identifier)
#define _GNU_SOURCE
// NOLINTEND(bugprone-reserved-identifier)

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <limits.h>
#include <locale.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <time.h>
#include <unistd.h>

// 特征码中的通配字节，匹配任意值
static constexpr int16_t ANY_ = -1;
// 尚未观测到 FPS 时的 last_fps 哨兵值
static constexpr int32_t FPS_UNOBSERVED = INT32_MIN;

typedef struct {
    uintptr_t start;
    uintptr_t end;
    char perms[5];
    const char *path;
} memory_mapping_t;

typedef struct {
    char line[32];
    size_t length;
    bool discarding_line;
} fifo_input_t;

typedef struct {
    pid_t pid;
    int32_t target_fps;
    bool is_dry_run;
    int32_t interval;
    const char *fifo_path;
    bool verbose;
} cli_options_t;

typedef struct {
    pid_t pid;
    uintptr_t fps_addr;
    int32_t target_fps;
    bool is_dry_run;
    int pid_fd;
    int fifo_fd;
    fifo_input_t fifo_input;
    bool verbose;
    int32_t last_fps;
} unlock_ctx_t;

// 函数声明
static bool parse_cli(int argc, char **argv, cli_options_t *opts);
static bool set_option_once(const char **slot, const char *value, const char *name);
static void print_usage(const char *program);
static bool parse_integer(const char *text, long long minimum, long long maximum, bool allow_trailing_whitespace, long long *value);
static void run_poll_loop(unlock_ctx_t *ctx, int32_t interval);
static bool sync_fps(unlock_ctx_t *ctx);
static void print_timestamp();
static bool handle_fifo_updates(int fifo_fd, fifo_input_t *input, int32_t *target_fps, bool *is_dry_run);
static bool setup_fifo(const char *fifo_path);
static void close_fifo(int fifo_fd, const char* fifo_path);
static bool verify_process(pid_t pid);
static uintptr_t find_fps_var_address(pid_t pid);
static bool parse_memory_mapping(char *line, memory_mapping_t *mapping);
static int open_pidfd(pid_t pid);
static bool read_process_memory(pid_t pid, uintptr_t addr, void* buf, size_t size);
static bool write_process_memory(pid_t pid, uintptr_t addr, const void* buf, size_t size);
static void* find_pattern_in_process(pid_t pid, uintptr_t start, size_t len, const int16_t* pattern, size_t plen);
static bool ends_with(const char *str, const char *suffix);
static void signal_handler(int sig);

// 全局变量
static volatile sig_atomic_t received_signal = 0;

int main(const int argc, char **argv) {
    setlocale(LC_CTYPE, "");
    setlocale(LC_MESSAGES, "");

    cli_options_t opts;
    if (!parse_cli(argc, argv, &opts)) return 1;

    struct sigaction sa = { .sa_handler = signal_handler };
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(SIGINT, &sa, nullptr);
    sigaction(SIGTERM, &sa, nullptr);

    if (!verify_process(opts.pid)) {
        fprintf(stderr, "错误: PID %d 对应的进程似乎不是原神进程\n", opts.pid);
        return 1;
    }

    const uintptr_t fps_addr = find_fps_var_address(opts.pid);
    if (!fps_addr) {
        return 1;
    }

    int fifo_fd = -1;
    if (opts.fifo_path != nullptr && setup_fifo(opts.fifo_path)) {
        fifo_fd = open(opts.fifo_path, O_RDWR | O_NONBLOCK);
    }

    unlock_ctx_t ctx = {
        .pid = opts.pid,
        .fps_addr = fps_addr,
        .target_fps = opts.target_fps,
        .is_dry_run = opts.is_dry_run,
        .pid_fd = open_pidfd(opts.pid),
        .fifo_fd = fifo_fd,
        .fifo_input = { .length = 0, .discarding_line = false },
        .verbose = opts.verbose,
        .last_fps = FPS_UNOBSERVED,
    };

    run_poll_loop(&ctx, opts.interval);

    if (ctx.pid_fd != -1) close(ctx.pid_fd);
    close_fifo(fifo_fd, opts.fifo_path);
    return 0;
}

static bool parse_cli(const int argc, char **argv, cli_options_t *opts) {
    const char *interval_text = nullptr;
    opts->fifo_path = nullptr;
    static const struct option long_options[] = {
        { .name = "interval", .has_arg = required_argument, .flag = nullptr, .val = 'i' },
        { .name = "fifo", .has_arg = required_argument, .flag = nullptr, .val = 'f' },
        { .name = "verbose", .has_arg = no_argument, .flag = nullptr, .val = 'v' },
        { .name = nullptr, .has_arg = 0, .flag = nullptr, .val = 0 },
    };

    opts->verbose = false;
    int opt;
    while ((opt = getopt_long(argc, argv, "+i:f:v", long_options, nullptr)) != -1) {
        switch (opt) {
            case 'i':
                if (!set_option_once(&interval_text, optarg, "interval")) return false;
                break;
            case 'f':
                if (!set_option_once(&opts->fifo_path, optarg, "fifo")) return false;
                break;
            case 'v':
                opts->verbose = true;
                break;
            default:
                print_usage(argv[0]);
                return false;
        }
    }

    const int positional_count = argc - optind;
    if (positional_count < 1 || positional_count > 2) {
        print_usage(argv[0]);
        return false;
    }
    char **positional = argv + optind;

    long long parsed_value;
    if (!parse_integer(positional[0], INT_MIN, INT_MAX, false, &parsed_value)) {
        fprintf(stderr, "错误: PID 无效: %s\n", positional[0]);
        return false;
    }
    opts->pid = (pid_t)parsed_value;

    opts->target_fps = 0;
    opts->is_dry_run = true;
    if (positional_count == 2) {
        if (!parse_integer(positional[1], INT32_MIN, INT32_MAX, false, &parsed_value)) {
            fprintf(stderr, "错误: FPS 数值无效: %s\n", positional[1]);
            return false;
        }
        opts->target_fps = (int32_t)parsed_value;
        opts->is_dry_run = opts->target_fps < 1;
    }

    opts->interval = 5000;
    if (interval_text != nullptr) {
        if (!parse_integer(interval_text, INT32_MIN, INT32_MAX, false, &parsed_value)) {
            fprintf(stderr, "错误: 轮询间隔无效: %s\n", interval_text);
            return false;
        }
        opts->interval = (int32_t)parsed_value;
    }
    return true;
}

static bool set_option_once(const char **slot, const char *value, const char *name) {
    if (*slot != nullptr) {
        fprintf(stderr, "错误: 选项 --%s 只能指定一次\n", name);
        return false;
    }
    *slot = value;
    return true;
}

static void print_usage(const char *program) {
    fprintf(stderr, "用法: %s [--interval MS] [--fifo PATH] [--verbose] <PID> [FPS]\n", program);
    fprintf(stderr, "      --interval  轮询间隔（0 表示只执行一次，默认 5000）\n");
    fprintf(stderr, "      --verbose   打印 FPS 的首次观测、外部变化与本程序写入，时间戳为 CLOCK_MONOTONIC\n");
    fprintf(stderr, "      FPS 省略或小于 1 时进入试运行模式（只读）\n");
    fprintf(stderr, "      FIFO 中每条 FPS 更新以换行结束\n");
    fprintf(stderr, "\n提示: 运行一次 'sudo setcap cap_sys_ptrace+ep %s' 后即可无需 sudo 运行\n", program);
}

static bool parse_integer(const char *text, const long long minimum, const long long maximum,
                          const bool allow_trailing_whitespace, long long *value) {
    char *endptr;
    errno = 0;
    const long long parsed = strtoll(text, &endptr, 10);
    if (endptr == text || errno == ERANGE || parsed < minimum || parsed > maximum) {
        return false;
    }
    if (allow_trailing_whitespace) {
        while (isspace((unsigned char)*endptr)) {
            ++endptr;
        }
    }
    if (*endptr != '\0') {
        return false;
    }
    *value = parsed;
    return true;
}

static void run_poll_loop(unlock_ctx_t *ctx, const int32_t interval) {
    const int32_t timeout_ms = interval > 0 ? interval : 0;
    do {
        if (!sync_fps(ctx)) break;

        // poll 会忽略负数 fd，因此 pid_fd 或 fifo_fd 为 -1 时对应项不起作用
        struct pollfd pfds[] = {
            { .fd = ctx->pid_fd, .events = POLLIN },
            { .fd = ctx->fifo_fd, .events = POLLIN },
        };
        poll(pfds, 2, timeout_ms);

        if (pfds[0].revents & POLLIN) {
            printf("目标进程已退出\n");
            break;
        }
        if ((pfds[1].revents & POLLIN) &&
            !handle_fifo_updates(ctx->fifo_fd, &ctx->fifo_input, &ctx->target_fps, &ctx->is_dry_run)) {
            break;
        }

        if (received_signal != 0) {
            printf("收到信号 %d，正在正常退出\n", received_signal);
            break;
        }
    } while (interval > 0);
}

static bool sync_fps(unlock_ctx_t *ctx) {
    int32_t current_fps;
    if (!read_process_memory(ctx->pid, ctx->fps_addr, &current_fps, sizeof(current_fps))) return false;

    if (ctx->is_dry_run) {
        printf("当前 FPS 限制：%-5d\r", current_fps);
        fflush(stdout);
        return true;
    }

    if (ctx->verbose) {
        if (ctx->last_fps == FPS_UNOBSERVED) {
            print_timestamp();
            printf("首次观测 FPS: %d\n", current_fps);
            fflush(stdout);
        } else if (current_fps != ctx->last_fps) {
            print_timestamp();
            printf("FPS 变化: %d -> %d\n", ctx->last_fps, current_fps);
            fflush(stdout);
        }
    }

    if (current_fps != ctx->target_fps) {
        if (!write_process_memory(ctx->pid, ctx->fps_addr, &ctx->target_fps, sizeof(ctx->target_fps))) return false;
        if (ctx->verbose) {
            print_timestamp();
            printf("FPS 写入: %d -> %d\n", current_fps, ctx->target_fps);
            fflush(stdout);
        }
        current_fps = ctx->target_fps;
    }

    ctx->last_fps = current_fps;
    return true;
}

static void print_timestamp() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    printf("[%lld.%09ld] ", (long long)ts.tv_sec, ts.tv_nsec);
}

static bool handle_fifo_updates(const int fifo_fd, fifo_input_t *input, int32_t *target_fps,
                               bool *is_dry_run) {
    char chunk[128];
    while (true) {
        const ssize_t bytes_read = read(fifo_fd, chunk, sizeof(chunk));
        if (bytes_read == -1) {
            if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) {
                return true;
            }
            perror("读取 FIFO 失败");
            return false;
        }
        if (bytes_read == 0) {
            return true;
        }

        for (ssize_t i = 0; i < bytes_read; ++i) {
            const char ch = chunk[i];
            if (input->discarding_line) {
                if (ch == '\n') {
                    input->discarding_line = false;
                }
                continue;
            }
            if (ch == '\0') {
                fprintf(stderr, "错误: 忽略从 FIFO 收到的无效 FPS 数值\n");
                input->length = 0;
                input->discarding_line = true;
                continue;
            }
            if (ch != '\n') {
                if (input->length == sizeof(input->line) - 1) {
                    fprintf(stderr, "错误: 忽略从 FIFO 收到的超长 FPS 数值\n");
                    input->length = 0;
                    input->discarding_line = true;
                } else {
                    input->line[input->length++] = ch;
                }
                continue;
            }

            input->line[input->length] = '\0';
            long long parsed_value;
            if (parse_integer(input->line, 0, INT32_MAX, true, &parsed_value)) {
                *target_fps = (int32_t)parsed_value;
                *is_dry_run = *target_fps < 1;
                printf("FPS 限制已更新为：%d%s\n", *target_fps, *is_dry_run ? " (dry-run)" : "");
            } else {
                fprintf(stderr, "错误: 忽略从 FIFO 收到的无效 FPS 数值: %s\n", input->line);
            }
            input->length = 0;
        }
    }
}

static bool setup_fifo(const char* fifo_path) {
    if (mkfifo(fifo_path, 0666) == -1) {
        if (errno != EEXIST) {
            perror("创建 FIFO 失败");
            return false;
        }
    }
    return true;
}

static void close_fifo(const int fifo_fd, const char* fifo_path) {
    if (fifo_fd != -1) {
        close(fifo_fd);
        unlink(fifo_path);
    }
}

static bool verify_process(const pid_t pid) {
    char path[64];
    char cmdline[1024] = {};

    if (pid < 1) return false;
    snprintf(path, sizeof(path), "/proc/%d/cmdline", pid);
    FILE* fp = fopen(path, "r");
    if (!fp) return false;

    fread(cmdline, 1, sizeof(cmdline) - 1, fp);
    fclose(fp);

    return ends_with(cmdline, "GenshinImpact.exe") || ends_with(cmdline, "YuanShen.exe");
}

static uintptr_t find_fps_var_address(const pid_t pid) {
    char maps_path[64];
    FILE *fp = nullptr;
    char *line = nullptr;
    size_t len = 0;
    uint8_t *setter_call = nullptr;
    uintptr_t fps_var_addr = 0;     // 默认返回 0 表示失败

    static constexpr int16_t pattern[] = { 0xB9, 0x3C, 0x00, 0x00, 0x00, 0xE8, ANY_, ANY_, ANY_, ANY_, 0x80 };
    static constexpr size_t pattern_len = sizeof(pattern)/sizeof(pattern[0]);

    snprintf(maps_path, sizeof(maps_path), "/proc/%d/maps", pid);
    fp = fopen(maps_path, "r");
    if (!fp) {
        perror("错误: 无法打开进程映射文件");
        goto out;
    }

    int game_module_found = 0;
    uintptr_t last_end = 0;
    while (getline(&line, &len, fp) != -1) {
        memory_mapping_t mapping;
        if (!parse_memory_mapping(line, &mapping)) {
            continue;
        }

        if (!game_module_found) {
            if (ends_with(mapping.path, "GenshinImpact.exe") || ends_with(mapping.path, "YuanShen.exe")) {
                game_module_found = 1;
            } else {
                continue;
            }
        }

        // 地址不连续表示模块的内存段已结束
        if (last_end != 0 && mapping.start != last_end) {
            break;
        }

        if (strchr(mapping.perms, 'x')) { // 检查该内存段是否可执行
            setter_call = find_pattern_in_process(pid, mapping.start, mapping.end - mapping.start, pattern, pattern_len);
            if (setter_call) {
                break; // 找到特征码后无需继续扫描
            }
        }
        last_end = mapping.end;
    }

    if (!setter_call) {
        fprintf(stderr, "错误: 未找到 FPS 设置函数的特征码\n");
        goto out_cleanup;
    }

    uint8_t instr_bytes[7];
    uint8_t *current_addr = setter_call + 5;
    for (int i = 0; i < 5; ++i) { // 限制追踪深度，避免无限循环
        if (!read_process_memory(pid, (uintptr_t)current_addr, instr_bytes, sizeof(instr_bytes))) {
            goto out_cleanup;
        }
        if (instr_bytes[0] == 0xE8 || instr_bytes[0] == 0xE9) { // JMP 或 CALL 指令
            int32_t offset;
            memcpy(&offset, &instr_bytes[1], 4);
            current_addr += offset + 5;
        } else {
            break; // 遇到非 JMP/CALL 指令，假定已到达目标位置
        }
    }

    if (instr_bytes[0] != 0x89 || instr_bytes[1] != 0x0D) {
        fprintf(stderr, "错误: 未找到最终的 'mov [rip+offset], ecx' 指令\n");
        goto out_cleanup;
    }

    int32_t rip_offset;
    memcpy(&rip_offset, &instr_bytes[2], 4);

    fps_var_addr = (uintptr_t)(current_addr + 6 + rip_offset);

out_cleanup:
    fclose(fp);
    free(line);
out:
    return fps_var_addr;
}

// 对应原 sscanf("%lx-%lx %4s %*x %*s %*d %1023[^\n]%*c") 的字段解析:
// 读取地址范围和权限，跳过偏移量、设备号和 inode，剩余内容作为可选路径
static bool parse_memory_mapping(char *line, memory_mapping_t *mapping) {
    const char *cursor = line;
    char *endptr;

    if (!isxdigit((unsigned char)*cursor)) {
        return false;
    }
    errno = 0;
    const unsigned long long start = strtoull(cursor, &endptr, 16);
    if (endptr == cursor || errno == ERANGE || start > UINTPTR_MAX || *endptr != '-') {
        return false;
    }

    cursor = endptr + 1;
    if (!isxdigit((unsigned char)*cursor)) {
        return false;
    }
    errno = 0;
    const unsigned long long end = strtoull(cursor, &endptr, 16);
    if (endptr == cursor || errno == ERANGE || end > UINTPTR_MAX || end < start ||
        !isspace((unsigned char)*endptr)) {
        return false;
    }
    mapping->start = (uintptr_t)start;
    mapping->end = (uintptr_t)end;

    cursor = endptr;
    while (isspace((unsigned char)*cursor)) {
        ++cursor;
    }
    const size_t perms_len = strcspn(cursor, " \t\r\n");
    if (perms_len != 4 || !isspace((unsigned char)cursor[perms_len])) {
        return false;
    }
    memcpy(mapping->perms, cursor, perms_len);
    mapping->perms[perms_len] = '\0';
    cursor += perms_len;

    // 跳过偏移量、设备号和 inode 字段
    for (int i = 0; i < 3; ++i) {
        while (isspace((unsigned char)*cursor)) {
            ++cursor;
        }
        const size_t field_len = strcspn(cursor, " \t\r\n");
        if (field_len == 0) {
            return false;
        }
        cursor += field_len;
    }

    while (isspace((unsigned char)*cursor)) {
        ++cursor;
    }
    line[strcspn(line, "\n")] = '\0';
    mapping->path = cursor;
    return true;
}

// pidfd 在进程退出时变为可读，用于让轮询立即唤醒；内核不支持时返回 -1，退回定时轮询
static int open_pidfd(const pid_t pid) {
    const long fd = syscall(SYS_pidfd_open, pid, 0);
    return fd == -1 ? -1 : (int)fd;
}

static bool read_process_memory(const pid_t pid, const uintptr_t addr, void* buf, const size_t size) {
    const struct iovec local = { .iov_base = buf, .iov_len = size };
    const struct iovec remote = { .iov_base = (void*)addr, .iov_len = size };
    const ssize_t bytes_read = process_vm_readv(pid, &local, 1, &remote, 1, 0);
    if (bytes_read == -1) {
        if (errno == ESRCH) {
            printf("目标进程已退出\n");
            return false;
        }
        fprintf(stderr, "错误: 读取地址 %p 处的 %zu 字节失败: %s\n", (void*)addr, size, strerror(errno));
        return false;
    }
    return bytes_read == (ssize_t)size;
}

static bool write_process_memory(const pid_t pid, const uintptr_t addr, const void* buf, const size_t size) {
    const struct iovec local = { .iov_base = (void*)buf, .iov_len = size };
    const struct iovec remote = { .iov_base = (void*)addr, .iov_len = size };
    const ssize_t bytes_written = process_vm_writev(pid, &local, 1, &remote, 1, 0);
    if (bytes_written == -1) {
        if (errno == ESRCH) {
            printf("目标进程已退出\n");
            return false;
        }
        fprintf(stderr, "错误: 向地址 %p 写入 %zu 字节失败: %s\n", (void*)addr, size, strerror(errno));
        return false;
    }
    return bytes_written == (ssize_t)size;
}

static void* find_pattern_in_process(const pid_t pid, const uintptr_t start, const size_t len, const int16_t* pattern, const size_t plen) {
    auto const remote = (uint8_t*)start;
    uint8_t buf[4096];
    if (plen == 0 || plen > sizeof(buf) || len < plen) return nullptr;

    const size_t step = sizeof(buf) - plen + 1;
    const size_t last_start = len - plen;
    for (size_t offset = 0; offset <= last_start;) {
        const size_t bytes_to_read = len - offset < sizeof(buf) ? len - offset : sizeof(buf);
        if (!read_process_memory(pid, (uintptr_t)(remote + offset), buf, bytes_to_read)) break;
        for (size_t j = 0; j + plen <= bytes_to_read; ++j) {
            int found = 1;
            for (size_t k = 0; k < plen; ++k) {
                if (pattern[k] != ANY_ && pattern[k] != buf[j + k]) { found = 0; break; }
            }
            if (found) return remote + offset + j;
        }
        if (last_start - offset < step) break;
        offset += step;
    }
    return nullptr;
}

static bool ends_with(const char *str, const char *suffix) {
    if (!str || !suffix) return false;
    const size_t len_str = strlen(str);
    const size_t len_suffix = strlen(suffix);
    if (len_suffix > len_str) return false;
    return !strncmp(str + len_str - len_suffix, suffix, len_suffix);
}

static void signal_handler(const int sig) {
    received_signal = sig;
}
