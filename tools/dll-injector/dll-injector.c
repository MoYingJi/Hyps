// dll-injector：通用 Windows DLL 注入器
// 以挂起状态启动游戏，把指定 DLL 注入游戏进程，再恢复主线程并等待游戏退出
// 注入方式是文档记载的常规做法：远程线程调用 LoadLibraryW
//
// 构建:
//   x86_64-w64-mingw32-gcc -municode -mwindows -static -O2 -Wall -Wextra -o dll-injector.exe dll-injector.c
//   注入器必须与游戏同位数，注入 32 位游戏时改用 i686-w64-mingw32-gcc 编译
//
// 用法:
//   dll-injector.exe [--no-wait] <DLL>... -- <游戏 exe> [游戏参数...]
//
//   -- 之前是若干要注入的 DLL，按顺序注入；-- 是必填的分隔符，不做猜测
//   -- 之后是游戏 exe，其后的参数原样传给游戏
//   DLL 可以是相对路径，注入前会转成绝对路径
//   游戏在挂起状态下创建，各 DLL 的 DllMain 依次先于游戏自己的初始化执行
//   注入成功后恢复主线程，默认等待游戏退出并把游戏退出码作为本程序退出码
//   --no-wait 时注入并恢复后立即退出，不等待游戏
//
// 退出码: 参数错误返回 2，启动或注入失败返回 1
//         默认等待时返回游戏退出码，--no-wait 成功时返回 0
//
// 为什么默认等游戏退出:
//   wine 和裸 proton 只等它直接启动的那个进程，不等孙进程
//   注入器若先退出，runner 会立即返回，而游戏仍在运行，Hyps 会据此提前收尾
//   umu-run 则跟随整个 prefix/容器的生命周期，注入器提前退出不会让它返回
//   三种 runner 行为不一致，所以默认等待；确实需要不等待时显式加 --no-wait
//   --no-wait 只在 umu-run 一类 runner 下安全
//
// 其它说明:
//   - 注入器、游戏和 DLL 必须同位数，启动前会读 PE 头校验
//   - 远程线程入口按目标进程的模块快照计算，不依赖 kernel32 在两个进程里同址
//   - LoadLibraryW 的返回值只取非零作为成功标志，64 位 HMODULE 无法完整经线程退出码传回
//   - 等待远程 LoadLibraryW 有 30 秒上限，避免 DllMain 卡死时永久挂起
//   - 注入受保护或反作弊进程通常会在 CreateRemoteThread 处失败，需要更高权限
//   - 多个 DLL 按命令行顺序依次注入，DLL 之间的依赖靠顺序保证
//   - DLL 的依赖库仍需自己能找到，放在 DLL 同目录不一定符合 Windows 的搜索规则
//
// 构建与缓存由 lib/utils/toolspec 负责，游戏模块需要时按 toolspec.sh 编译

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>

#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

// 等待远程 LoadLibraryW 返回的上限，避免 DllMain 卡死时永久挂起
#define REMOTE_LOAD_TIMEOUT_MS 30000

typedef enum {
    INJECT_OK = 0,
    INJECT_ERROR,            // 本侧 API 调用失败
    INJECT_REMOTE_FAILED,    // 远程 LoadLibraryW 返回失败
    INJECT_TIMEOUT,          // 远程线程超时
} INJECT_RESULT;

static void show_usage(void);
static int run_game(const WCHAR *const *dll_paths, int dll_count, const WCHAR *exe_path,
                    int game_argc, WCHAR **game_argv, BOOL no_wait);
static INJECT_RESULT inject_dll(HANDLE process, const WCHAR *dll_path, DWORD *last_error);
static BOOL remote_load_library(HANDLE process, LPVOID *address);
static WORD pe_machine_of(const WCHAR *path);
static BOOL machine_is_64bit(WORD machine);
static BOOL machine_matches_self(WORD machine);
static WCHAR *get_full_path(const WCHAR *path);
static WCHAR *append_quoted_arg(WCHAR *dst, const WCHAR *arg);
static WCHAR *build_cmdline(int argc, WCHAR **argv);
static BOOL log_message(const char *level, const WCHAR *message);
static void log_info(const WCHAR *message);
static void show_error(const WCHAR *message);
static void show_errorf(const WCHAR *format, ...);
static void show_win32_error(const WCHAR *what, DWORD code);

int wmain(const int argc, WCHAR *argv[]) {
    // 选项写在前面，之后是若干 DLL，可用 -- 分隔 DLL 列表和游戏 exe
    int first = 1;
    BOOL no_wait = FALSE;
    while (first < argc) {
        if (wcscmp(argv[first], L"--no-wait") == 0) {
            no_wait = TRUE;
            first++;
        } else if (wcscmp(argv[first], L"--help") == 0 || wcscmp(argv[first], L"-h") == 0) {
            show_usage();
            return 0;
        } else {
            break;
        }
    }

    // -- 必须出现，之前是 DLL 列表，之后是游戏 exe 及其参数
    int delimiter = -1;
    for (int i = first; i < argc; i++) {
        if (wcscmp(argv[i], L"--") == 0) {
            delimiter = i;
            break;
        }
    }
    if (delimiter < 0) {
        show_usage();
        return 2;
    }
    const int dll_count = delimiter - first;
    const int exe_index = delimiter + 1;
    if (dll_count < 1 || exe_index >= argc) {
        show_usage();
        return 2;
    }

    // 每个 DLL 路径转绝对路径，远程加载时不受目标进程工作目录和搜索顺序影响
    WCHAR **dll_paths = malloc((size_t)dll_count * sizeof(*dll_paths));
    if (!dll_paths) {
        show_error(L"内存不足");
        return 1;
    }
    for (int i = 0; i < dll_count; i++) {
        dll_paths[i] = get_full_path(argv[first + i]);
        if (!dll_paths[i]) {
            for (int j = 0; j < i; j++) {
                free(dll_paths[j]);
            }
            free(dll_paths);
            return 1;
        }
    }
    WCHAR *exe_path = get_full_path(argv[exe_index]);
    if (!exe_path) {
        for (int i = 0; i < dll_count; i++) {
            free(dll_paths[i]);
        }
        free(dll_paths);
        return 1;
    }

    // game_argv[0] 是游戏 exe，之后是原样的游戏参数
    const int game_argc = argc - exe_index;
    WCHAR **game_argv = malloc((size_t)game_argc * sizeof(*game_argv));
    if (!game_argv) {
        show_error(L"内存不足");
        for (int i = 0; i < dll_count; i++) {
            free(dll_paths[i]);
        }
        free(dll_paths);
        free(exe_path);
        return 1;
    }
    game_argv[0] = exe_path;
    for (int i = 1; i < game_argc; i++) {
        game_argv[i] = argv[exe_index + i];
    }

    const int rc = run_game((const WCHAR *const *)dll_paths, dll_count, exe_path,
                            game_argc, game_argv, no_wait);

    free(game_argv);
    free(exe_path);
    for (int i = 0; i < dll_count; i++) {
        free(dll_paths[i]);
    }
    free(dll_paths);
    return rc;
}

static void show_usage(void) {
    show_error(L"用法:\n"
               L"  dll-injector.exe [--no-wait] <DLL>... -- <游戏 exe> [游戏参数...]\n"
               L"\n"
               L"-- 之前是若干要注入的 DLL，按顺序注入；-- 必填\n"
               L"-- 之后是游戏 exe，其余参数原样传给游戏\n"
               L"以挂起状态启动游戏并注入 DLL，注入成功后恢复运行，默认等待游戏退出\n"
               L"  --no-wait  注入并恢复后立即退出，不等待游戏\n"
               L"注入器、游戏和 DLL 必须同为 64 位或同为 32 位");
}

static int run_game(const WCHAR *const *dll_paths, const int dll_count, const WCHAR *exe_path,
                    const int game_argc, WCHAR **game_argv, const BOOL no_wait) {
    // 启动前先确认位数一致，避免白白启动一次游戏后又因远程线程跑不起来被杀掉
    const WORD exe_machine = pe_machine_of(exe_path);
    if (exe_machine == IMAGE_FILE_MACHINE_UNKNOWN) {
        show_errorf(L"无法识别游戏可执行文件的格式:\n%ls", exe_path);
        return 1;
    }
    if (!machine_matches_self(exe_machine)) {
        show_errorf(L"游戏与注入器的位数不一致，无法注入:\n%ls", exe_path);
        return 1;
    }
    // 启动前校验每个 DLL，避免启动后才发现注定失败的注入
    for (int i = 0; i < dll_count; i++) {
        const WORD dll_machine = pe_machine_of(dll_paths[i]);
        if (dll_machine == IMAGE_FILE_MACHINE_UNKNOWN) {
            show_errorf(L"无法识别 DLL 的文件格式:\n%ls", dll_paths[i]);
            return 1;
        }
        if (!machine_matches_self(dll_machine)) {
            show_errorf(L"DLL 与注入器的位数不一致，无法注入:\n%ls", dll_paths[i]);
            return 1;
        }
    }

    WCHAR *cmdline = build_cmdline(game_argc, game_argv);
    if (!cmdline) {
        show_error(L"内存不足");
        return 1;
    }

    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    ZeroMemory(&pi, sizeof(pi));
    si.cb = sizeof(si);

    int rc = 1;
    if (!CreateProcessW(exe_path, cmdline, nullptr, nullptr, FALSE, CREATE_SUSPENDED,
                        nullptr, nullptr, &si, &pi)) {
        show_win32_error(L"无法启动游戏进程", GetLastError());
        goto cleanup;
    }

    // 按顺序逐个注入，任意一个失败都终止整个进程
    for (int i = 0; i < dll_count; i++) {
        DWORD last_error = 0;
        const INJECT_RESULT result = inject_dll(pi.hProcess, dll_paths[i], &last_error);
        if (result == INJECT_OK) {
            continue;
        }
        if (result == INJECT_TIMEOUT) {
            show_errorf(L"等待 DLL 加载超时 (PID %lu)，已终止游戏进程:\n%ls",
                        (unsigned long)pi.dwProcessId, dll_paths[i]);
        } else if (result == INJECT_REMOTE_FAILED) {
            show_errorf(L"目标进程内的 LoadLibraryW 返回失败 (PID %lu)，已终止游戏进程:\n%ls\n"
                        L"常见原因: 依赖库缺失、位数不符、DllMain 返回 FALSE",
                        (unsigned long)pi.dwProcessId, dll_paths[i]);
        } else {
            show_win32_error(L"注入失败，已终止游戏进程", last_error);
        }
        TerminateProcess(pi.hProcess, 1);
        WaitForSingleObject(pi.hProcess, 5000);
        goto cleanup;
    }

    WCHAR message[512];
    _snwprintf(message, ARRAYSIZE(message), L"注入成功 %d 个 DLL，PID %lu",
               dll_count, (unsigned long)pi.dwProcessId);
    message[ARRAYSIZE(message) - 1] = L'\0';
    log_info(message);

    if (ResumeThread(pi.hThread) == (DWORD)-1) {
        show_win32_error(L"无法恢复游戏主线程", GetLastError());
        TerminateProcess(pi.hProcess, 1);
        WaitForSingleObject(pi.hProcess, 5000);
        goto cleanup;
    }

    if (no_wait) {
        rc = 0;
        goto cleanup;
    }

    if (WaitForSingleObject(pi.hProcess, INFINITE) != WAIT_OBJECT_0) {
        show_win32_error(L"等待游戏进程失败", GetLastError());
        goto cleanup;
    }
    DWORD exit_code = 0;
    if (!GetExitCodeProcess(pi.hProcess, &exit_code)) {
        show_win32_error(L"无法读取游戏退出码", GetLastError());
        goto cleanup;
    }
    rc = (int)exit_code;

cleanup:
    if (pi.hProcess) {
        CloseHandle(pi.hProcess);
    }
    if (pi.hThread) {
        CloseHandle(pi.hThread);
    }
    free(cmdline);
    return rc;
}

// 在目标进程里执行 LoadLibraryW，失败时通过 last_error 带回本侧错误码
static INJECT_RESULT inject_dll(const HANDLE process, const WCHAR *dll_path, DWORD *last_error) {
    *last_error = ERROR_SUCCESS;

    const SIZE_T size = (wcslen(dll_path) + 1) * sizeof(WCHAR);
    LPVOID remote_mem = VirtualAllocEx(process, nullptr, size, MEM_COMMIT | MEM_RESERVE,
                                       PAGE_READWRITE);
    if (!remote_mem) {
        *last_error = GetLastError();
        return INJECT_ERROR;
    }

    SIZE_T written = 0;
    if (!WriteProcessMemory(process, remote_mem, dll_path, size, &written) || written != size) {
        *last_error = GetLastError();
        VirtualFreeEx(process, remote_mem, 0, MEM_RELEASE);
        return INJECT_ERROR;
    }

    LPVOID load_library = nullptr;
    if (!remote_load_library(process, &load_library)) {
        *last_error = GetLastError();
        VirtualFreeEx(process, remote_mem, 0, MEM_RELEASE);
        return INJECT_ERROR;
    }

    const HANDLE thread = CreateRemoteThread(process, nullptr, 0,
                                             (LPTHREAD_START_ROUTINE)load_library,
                                             remote_mem, 0, nullptr);
    if (!thread) {
        *last_error = GetLastError();
        VirtualFreeEx(process, remote_mem, 0, MEM_RELEASE);
        return INJECT_ERROR;
    }

    INJECT_RESULT result = INJECT_ERROR;
    const DWORD wait = WaitForSingleObject(thread, REMOTE_LOAD_TIMEOUT_MS);
    if (wait == WAIT_TIMEOUT) {
        // 远程线程可能还在引用路径内存，此时不能释放，交给进程退出回收
        CloseHandle(thread);
        return INJECT_TIMEOUT;
    }
    if (wait != WAIT_OBJECT_0) {
        *last_error = GetLastError();
        CloseHandle(thread);
        return INJECT_ERROR;
    }

    DWORD module = 0;
    if (!GetExitCodeThread(thread, &module)) {
        *last_error = GetLastError();
    } else if (module == 0) {
        // LoadLibraryW 失败时返回 NULL
        result = INJECT_REMOTE_FAILED;
    } else {
        result = INJECT_OK;
    }

    CloseHandle(thread);
    VirtualFreeEx(process, remote_mem, 0, MEM_RELEASE);
    return result;
}

// 求 LoadLibraryW 在目标进程中的地址
// 先在本进程取它相对 kernel32 基址的偏移，再用目标进程的模块快照找到 kernel32 基址
// 这样不依赖 kernel32 在两个进程里同址，不同 Wine 版本也成立
static BOOL remote_load_library(const HANDLE process, LPVOID *address) {
    const HMODULE local_kernel32 = GetModuleHandleW(L"kernel32.dll");
    if (!local_kernel32) {
        return FALSE;
    }
    const FARPROC local_proc = GetProcAddress(local_kernel32, "LoadLibraryW");
    if (!local_proc) {
        return FALSE;
    }
    const ULONG_PTR offset = (ULONG_PTR)local_proc - (ULONG_PTR)local_kernel32;

    const HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32,
                                                     GetProcessId(process));
    if (snapshot != INVALID_HANDLE_VALUE) {
        MODULEENTRY32W entry;
        entry.dwSize = sizeof(entry);
        if (Module32FirstW(snapshot, &entry)) {
            do {
                if (_wcsicmp(entry.szModule, L"kernel32.dll") == 0) {
                    *address = (LPVOID)((ULONG_PTR)entry.modBaseAddr + offset);
                    CloseHandle(snapshot);
                    return TRUE;
                }
            } while (Module32NextW(snapshot, &entry));
        }
        CloseHandle(snapshot);
    }

    // 快照不可用时退回本进程的地址，同位数的内核 DLL 通常位于相同地址
    *address = (LPVOID)local_proc;
    return TRUE;
}

// 读取 PE 文件的 Machine 字段，失败返回 IMAGE_FILE_MACHINE_UNKNOWN
static WORD pe_machine_of(const WCHAR *path) {
    const HANDLE file = CreateFileW(path, GENERIC_READ,
                                    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                    nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        return IMAGE_FILE_MACHINE_UNKNOWN;
    }

    WORD machine = IMAGE_FILE_MACHINE_UNKNOWN;
    IMAGE_DOS_HEADER dos;
    DWORD read = 0;
    if (ReadFile(file, &dos, sizeof(dos), &read, nullptr) && read == sizeof(dos)
        && dos.e_magic == IMAGE_DOS_SIGNATURE && dos.e_lfanew > 0) {
        LARGE_INTEGER offset;
        offset.QuadPart = dos.e_lfanew;
        if (SetFilePointerEx(file, offset, nullptr, FILE_BEGIN)) {
            DWORD signature = 0;
            IMAGE_FILE_HEADER header;
            if (ReadFile(file, &signature, sizeof(signature), &read, nullptr)
                && read == sizeof(signature) && signature == IMAGE_NT_SIGNATURE
                && ReadFile(file, &header, sizeof(header), &read, nullptr)
                && read == sizeof(header)) {
                machine = header.Machine;
            }
        }
    }
    CloseHandle(file);
    return machine;
}

static BOOL machine_is_64bit(const WORD machine) {
    return machine == IMAGE_FILE_MACHINE_AMD64
           || machine == IMAGE_FILE_MACHINE_ARM64
           || machine == IMAGE_FILE_MACHINE_IA64;
}

// 判断某个 PE 的位数是否与本注入器一致
static BOOL machine_matches_self(const WORD machine) {
#ifdef _WIN64
    return machine_is_64bit(machine);
#else
    // 32 位注入器只接受非 64 位的 PE，调用方已经排除了无法识别的文件
    return !machine_is_64bit(machine);
#endif
}

// 转成绝对路径，不要求文件存在
static WCHAR *get_full_path(const WCHAR *path) {
    const DWORD size = GetFullPathNameW(path, 0, nullptr, nullptr);
    if (size == 0) {
        show_win32_error(L"无法解析路径", GetLastError());
        return nullptr;
    }
    WCHAR *full = malloc((size_t)size * sizeof(WCHAR));
    if (!full) {
        show_error(L"内存不足");
        return nullptr;
    }
    const DWORD written = GetFullPathNameW(path, size, full, nullptr);
    if (written == 0 || written >= size) {
        const DWORD code = GetLastError();
        free(full);
        show_win32_error(L"无法解析路径", code);
        return nullptr;
    }
    return full;
}

// 按 MSVCRT 和 CommandLineToArgvW 的规则给参数加上引号并转义，最多需要 3 * len + 3 个字符
static WCHAR *append_quoted_arg(WCHAR *dst, const WCHAR *arg) {
    *dst++ = L'"';
    for (;; arg++) {
        size_t backslashes = 0;
        while (*arg == L'\\') {
            arg++;
            backslashes++;
        }

        if (*arg == L'\0') {
            for (size_t i = 0; i < backslashes * 2; i++) {
                *dst++ = L'\\';
            }
            break;
        }
        if (*arg == L'"') {
            for (size_t i = 0; i < backslashes * 2 + 1; i++) {
                *dst++ = L'\\';
            }
            *dst++ = L'"';
        } else {
            for (size_t i = 0; i < backslashes; i++) {
                *dst++ = L'\\';
            }
            *dst++ = *arg;
        }
    }
    *dst++ = L'"';
    return dst;
}

static WCHAR *build_cmdline(const int argc, WCHAR **argv) {
    size_t total = 1;
    for (int i = 0; i < argc; i++) {
        total += wcslen(argv[i]) * 3 + 4;
    }

    WCHAR *cmd = malloc(total * sizeof(WCHAR));
    if (!cmd) {
        return nullptr;
    }

    WCHAR *p = cmd;
    for (int i = 0; i < argc; i++) {
        if (i > 0) {
            *p++ = L' ';
        }
        p = append_quoted_arg(p, argv[i]);
    }
    *p = L'\0';
    return cmd;
}

static HANDLE get_stderr_handle(void) {
    static HANDLE stderr_handle;
    static BOOL checked;
    if (!checked) {
        stderr_handle = GetStdHandle(STD_ERROR_HANDLE);
        if (stderr_handle == INVALID_HANDLE_VALUE) {
            stderr_handle = nullptr;
        }
        checked = TRUE;
    }
    return stderr_handle;
}

static BOOL log_message(const char *level, const WCHAR *message) {
    const HANDLE handle = get_stderr_handle();
    if (!handle) {
        return FALSE;
    }

    char output[4096];
    const size_t level_length = strlen(level);
    if (level_length + 1 >= sizeof(output)) {
        return FALSE;
    }
    memcpy(output, level, level_length);
    const int message_length = WideCharToMultiByte(
        CP_UTF8, WC_ERR_INVALID_CHARS, message, -1,
        output + level_length,
        (int)(sizeof(output) - level_length - 1), nullptr, nullptr);
    if (message_length <= 0) {
        return FALSE;
    }

    output[level_length + (size_t)message_length - 1] = '\r';
    output[level_length + (size_t)message_length] = '\n';
    const SIZE_T output_length = level_length + (size_t)message_length + 1;

    for (SIZE_T offset = 0; offset < output_length;) {
        const SIZE_T remaining = output_length - offset;
        const DWORD chunk = remaining > MAXDWORD ? MAXDWORD : (DWORD)remaining;
        DWORD written = 0;
        if (!WriteFile(handle, output + offset, chunk, &written, nullptr) || written == 0) {
            return FALSE;
        }
        offset += written;
    }
    return TRUE;
}

static void log_info(const WCHAR *message) {
    log_message("[INFO] ", message);
}

static void show_error(const WCHAR *message) {
    // stderr 可用时只写日志，否则 (例如从桌面直接启动) 弹信息框
    if (!log_message("[ERROR] ", message)) {
        MessageBoxW(nullptr, message, L"Hyps dll-injector", MB_OK | MB_ICONERROR);
    }
}

static void show_errorf(const WCHAR *format, ...) {
    WCHAR buffer[2048];
    va_list args;
    va_start(args, format);
    _vsnwprintf(buffer, ARRAYSIZE(buffer), format, args);
    va_end(args);
    buffer[ARRAYSIZE(buffer) - 1] = L'\0';
    show_error(buffer);
}

static void show_win32_error(const WCHAR *what, const DWORD code) {
    show_errorf(L"%ls\n错误码: %lu", what, (unsigned long)code);
}
