// 修改自 everything411 的 unlocker.c
// https://github.com/everything411/fpsunlock

// We will defy this world with a power from beyond. 
// 从世界之外，我们取得否定世界的力量。

// 此代码非常危险！原理是读写内存！
// 同时也不要在其他地方公开提及！
// 仅在 Linux 上运行！

// unlocker.c - FPS unlocker refactored for native linux.
//
// To compile:
// gcc -o unlocker unlocker.c -Wall -Wextra
//
// To run without sudo (one-time setup):
// 1. Compile the program.
// 2. Grant capability: `sudo setcap cap_sys_ptrace+ep ./unlocker`
// 3. Run as a normal user.
//
// Usage: ./unlocker <PID> <FPS> [INTERVAL_MS] [FIFO_PATH]

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>

#define ANY_ (int16_t)-1

static bool setup_fifo(const char *fifo_path);
static void close_fifo(int fifo_fd, const char* fifo_path);
static bool read_process_memory(pid_t pid, uintptr_t addr, void* buf, size_t size);
static bool write_process_memory(pid_t pid, uintptr_t addr, const void* buf, size_t size);
static void* find_pattern_in_process(pid_t pid, uintptr_t start, size_t len, const int16_t* pattern, size_t plen);
static int verify_process(pid_t pid);
static int ends_with(const char *str, const char *suffix);
static uintptr_t find_fps_var_address(pid_t pid);

int main(const int argc, char **argv) {
    if (argc < 3 || argc > 5) {
        fprintf(stderr, "Usage: %s <PID> <FPS> [INTERVAL_MS] [FIFO_PATH]\n", argv[0]);
        fprintf(stderr, "       If FPS < 1, program enters dry-run mode (read-only).\n");
        fprintf(stderr, "\nNote: Run 'sudo setcap cap_sys_ptrace+ep %s' once to run without sudo.\n", argv[0]);
        return 1;
    }

    int32_t target_fps;
    int64_t interval = 5000;
    const char *fifo_path = nullptr;
    int fifo_fd = -1;
    bool use_fifo = false;

    const pid_t pid = atoi(argv[1]);
    target_fps = atoi(argv[2]);
    const int is_dry_run = target_fps < 1;
    if (argc >= 4) interval = atol(argv[3]);
    if (argc == 5) fifo_path = argv[4];

    if (!verify_process(pid)) {
        fprintf(stderr, "Error: PID %d does not appear to be a Genshin Impact process.\n", pid);
        return 1;
    }

    const uintptr_t fps_addr = find_fps_var_address(pid);
    if (!fps_addr) {
        return 1;
    }

    if (setup_fifo(fifo_path)) {
        fifo_fd = open(fifo_path, O_RDONLY | O_NONBLOCK);
        if (fifo_fd != -1) {
            use_fifo = true;
        }
    }

    if (is_dry_run) {
        int32_t current_fps;
        if (interval > 0) {
            while (read_process_memory(pid, fps_addr, &current_fps, sizeof(current_fps))) {
                printf("\rCurrent FPS limit: %-5d", current_fps);
                fflush(stdout);
                usleep(interval * 1000);
            }
            printf("\n");
        }
    } else {
        if (!write_process_memory(pid, fps_addr, &target_fps, sizeof(target_fps))) {
            close_fifo(fifo_fd, fifo_path);
            return 1;
        }

        if (interval > 0) {
            while (write_process_memory(pid, fps_addr, &target_fps, sizeof(target_fps))) {
                if (use_fifo) {
                    char buffer[32];
                    const ssize_t bytes_read = read(fifo_fd, buffer, sizeof(buffer) - 1);
                    if (bytes_read > 0) {
                        buffer[bytes_read] = '\0';
                        const int new_fps = atoi(buffer);
                        if (new_fps > 0) {
                            target_fps = new_fps;
                            printf("Updated FPS limit to: %d\n", target_fps);
                        }
                    }
                }

                usleep(interval * 1000);
            }
        }
    }

    close_fifo(fifo_fd, fifo_path);
    return 0;
}

static bool setup_fifo(const char* fifo_path) {
    // 创建命名管道
    if (mkfifo(fifo_path, 0666) == -1) {
        if (errno != EEXIST) {
            perror("mkfifo");
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

static bool read_process_memory(const pid_t pid, const uintptr_t addr, void* buf, const size_t size) {
    struct iovec local = { .iov_base = buf, .iov_len = size };
    struct iovec remote = { .iov_base = (void*)addr, .iov_len = size };
    ssize_t bytes_read = process_vm_readv(pid, &local, 1, &remote, 1, 0);
    if (bytes_read == -1) {
        fprintf(stderr, "Error: Read %zu bytes at %p failed: %s\n", size, (void*)addr, strerror(errno));
        return false;
    }
    return bytes_read == (ssize_t)size;
}

static bool write_process_memory(const pid_t pid, const uintptr_t addr, const void* buf, const size_t size) {
    const struct iovec local = { .iov_base = (void*)buf, .iov_len = size };
    const struct iovec remote = { .iov_base = (void*)addr, .iov_len = size };
    const ssize_t bytes_written = process_vm_writev(pid, &local, 1, &remote, 1, 0);
    if (bytes_written == -1) {
        fprintf(stderr, "Error: Write %zu bytes at %p failed: %s\n", size, (void*)addr, strerror(errno));
        return false;
    }
    return bytes_written == (ssize_t)size;
}

static void* find_pattern_in_process(const pid_t pid, const uintptr_t start, const size_t len, const int16_t* pattern, const size_t plen) {
    auto const remote = (uint8_t*)start;
    uint8_t buf[4096];
    for (size_t i = 0; i < len; i += sizeof(buf) - plen) {
        if (!read_process_memory(pid, (uintptr_t)(remote + i), buf, sizeof(buf))) break;
        for (size_t j = 0; j < sizeof(buf) - plen; ++j) {
            int found = 1;
            for (size_t k = 0; k < plen; ++k) {
                if (pattern[k] != ANY_ && pattern[k] != buf[j + k]) { found = 0; break; }
            }
            if (found) return remote + i + j;
        }
    }
    return NULL;
}

static int ends_with(const char *str, const char *suffix) {
    if (!str || !suffix) return 0;
    const size_t len_str = strlen(str);
    const size_t len_suffix = strlen(suffix);
    if (len_suffix > len_str) return 0;
    return !strncmp(str + len_str - len_suffix, suffix, len_suffix);
}

static int verify_process(const pid_t pid) {
    char path[64];
    char cmdline[1024] = {0};

    if (pid < 1) return 0;
    snprintf(path, sizeof(path), "/proc/%d/cmdline", pid);
    FILE* fp = fopen(path, "r");
    if (!fp) return 0;

    fread(cmdline, 1, sizeof(cmdline) - 1, fp);
    fclose(fp);

    return ends_with(cmdline, "GenshinImpact.exe") || ends_with(cmdline, "YuanShen.exe");
}

static uintptr_t find_fps_var_address(const pid_t pid) {
    char maps_path[64];
    FILE *fp = NULL;
    char *line = NULL;
    size_t len = 0;
    uint8_t *setter_call = NULL;
    uintptr_t fps_var_addr = 0; // Default return value is 0 (failure)

    constexpr int16_t pattern[] = { 0xB9, 0x3C, 0x00, 0x00, 0x00, 0xE8, ANY_, ANY_, ANY_, ANY_, 0x80 };
    constexpr size_t pattern_len = sizeof(pattern)/sizeof(pattern[0]);

    snprintf(maps_path, sizeof(maps_path), "/proc/%d/maps", pid);
    fp = fopen(maps_path, "r");
    if (!fp) {
        perror("Error: Failed to open process maps file");
        goto out;
    }

    int game_module_found = 0;
    uintptr_t last_end = 0;
    while (getline(&line, &len, fp) != -1) {
        uintptr_t start, end;
        char perms[5], path[1024] = {0};
        
        if (sscanf(line, "%lx-%lx %4s %*x %*s %*d %1023[^\n]%*c", &start, &end, perms, path) < 3) {
            continue;
        }

        if (!game_module_found) {
            if (ends_with(path, "GenshinImpact.exe") || ends_with(path, "YuanShen.exe")) {
                game_module_found = 1;
            } else {
                continue;
            }
        }

        // A gap in memory addresses signifies the end of the module's segments.
        if (last_end != 0 && start != last_end) {
            break;
        }
            
        if (strchr(perms, 'x')) { // Is the section executable?
            setter_call = find_pattern_in_process(pid, start, end - start, pattern, pattern_len);
            if (setter_call) {
                break; // Pattern found, no need to scan further.
            }
        }
        last_end = end;
    }

    if (!setter_call) {
        fprintf(stderr, "Error: Could not find the FPS setter pattern.\n");
        goto out_cleanup;
    }

    uint8_t instr_bytes[7];
    uint8_t *current_addr = setter_call + 5;
    for (int i = 0; i < 5; ++i) { // Limit trace depth to prevent infinite loops
        if (!read_process_memory(pid, (uintptr_t)current_addr, instr_bytes, sizeof(instr_bytes))) {
            goto out_cleanup;
        }
        if (instr_bytes[0] == 0xE8 || instr_bytes[0] == 0xE9) { // JMP or CALL
            int32_t offset;
            memcpy(&offset, &instr_bytes[1], 4);
            current_addr += offset + 5;
        } else {
            break; // Found an instruction that is not a JMP/CALL, assume it's the target.
        }
    }

    if (instr_bytes[0] != 0x89 || instr_bytes[1] != 0x0D) {
        fprintf(stderr, "Error: Could not find the final 'mov [rip+offset], ecx' instruction.\n");
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
