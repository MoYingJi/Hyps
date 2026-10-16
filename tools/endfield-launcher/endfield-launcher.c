// 以启动器作为父进程拉起游戏，用于满足“必须通过启动器启动”的检查。
//
// 构建 (由 lib/games/endfield.sh 按需调用，需要 mingw-w64):
//   x86_64-w64-mingw32-gcc -municode -static -O2 -Wall -Wextra -o endfield-launcher.exe endfield-launcher.c
//
// 用法: endfield-launcher.exe <启动器目录或exe文件> <游戏程序路径或目录> [游戏参数...]

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

static WCHAR *append_quoted_arg(WCHAR *dst, const WCHAR *arg);
static WCHAR *build_cmdline(int argc, WCHAR **argv);
static WCHAR *resolve_launcher_path(const WCHAR *path);
static WCHAR *resolve_game_path(const WCHAR *path);
static void show_error(const WCHAR *message);
static void show_win32_error(const WCHAR *what, DWORD code);

int wmain(const int argc, WCHAR *argv[]) {
    PROCESS_INFORMATION launcher;
    PROCESS_INFORMATION game;
    STARTUPINFOW si;
    STARTUPINFOEXW siex;
    LPPROC_THREAD_ATTRIBUTE_LIST attrs = nullptr;
    BOOL attrs_ready = FALSE;
    SIZE_T attrs_size = 0;
    WCHAR *resolved_launcher = nullptr;
    WCHAR *resolved_game = nullptr;
    WCHAR **game_argv = nullptr;
    WCHAR *lcmd = nullptr;
    WCHAR *gcmd = nullptr;
    DWORD code = 0;
    int rc = 1;

    ZeroMemory(&launcher, sizeof(launcher));
    ZeroMemory(&game, sizeof(game));

    if (argc < 3) {
        show_error(L"用法: endfield-launcher.exe <启动器目录或exe文件> <游戏程序路径或目录> [游戏参数...]");
        return 2;
    }

    resolved_launcher = resolve_launcher_path(argv[1]);
    if (!resolved_launcher) {
        goto cleanup;
    }

    resolved_game = resolve_game_path(argv[2]);
    if (!resolved_game) {
        goto cleanup;
    }

    WCHAR *launcher_argv[] = {resolved_launcher};
    lcmd = build_cmdline(1, launcher_argv);
    game_argv = malloc((size_t)(argc - 2) * sizeof(*game_argv));
    if (!game_argv) {
        show_error(L"内存不足");
        goto cleanup;
    }
    game_argv[0] = resolved_game;
    for (int i = 3; i < argc; i++) {
        game_argv[i - 2] = argv[i];
    }
    gcmd = build_cmdline(argc - 2, game_argv);
    if (!lcmd || !gcmd) {
        show_error(L"内存不足");
        goto cleanup;
    }

    // 挂起的启动器只用于提供父进程句柄，主线程不恢复运行
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    if (!CreateProcessW(nullptr, lcmd, nullptr, nullptr, FALSE, CREATE_SUSPENDED,
                        NULL, nullptr, &si, &launcher)) {
        show_win32_error(L"无法启动官方启动器", GetLastError());
        goto cleanup;
    }
    CloseHandle(launcher.hThread);
    launcher.hThread = NULL;

    InitializeProcThreadAttributeList(nullptr, 1, 0, &attrs_size);
    attrs = HeapAlloc(GetProcessHeap(), 0, attrs_size);
    if (!attrs) {
        show_error(L"内存不足");
        goto cleanup;
    }
    if (!InitializeProcThreadAttributeList(attrs, 1, 0, &attrs_size)) {
        show_win32_error(L"无法初始化进程属性", GetLastError());
        goto cleanup;
    }
    attrs_ready = TRUE;

    if (!UpdateProcThreadAttribute(attrs, 0, PROC_THREAD_ATTRIBUTE_PARENT_PROCESS,
                                   &launcher.hProcess, sizeof(launcher.hProcess),
                                   NULL, nullptr)) {
        show_win32_error(L"无法设置游戏父进程", GetLastError());
        goto cleanup;
    }

    ZeroMemory(&siex, sizeof(siex));
    siex.StartupInfo.cb = sizeof(siex);
    siex.lpAttributeList = attrs;
    if (!CreateProcessW(nullptr, gcmd, nullptr, nullptr, FALSE, EXTENDED_STARTUPINFO_PRESENT,
                        NULL, nullptr, &siex.StartupInfo, &game)) {
        show_win32_error(L"无法启动游戏", GetLastError());
        goto cleanup;
    }
    CloseHandle(game.hThread);
    game.hThread = NULL;

    if (WaitForSingleObject(game.hProcess, INFINITE) != WAIT_OBJECT_0) {
        show_win32_error(L"等待游戏进程失败", GetLastError());
        goto cleanup;
    }
    if (!GetExitCodeProcess(game.hProcess, &code)) {
        show_win32_error(L"无法读取游戏退出码", GetLastError());
        goto cleanup;
    }
    rc = (int)code;

cleanup:
    if (launcher.hProcess) {
        TerminateProcess(launcher.hProcess, 0);
        CloseHandle(launcher.hProcess);
    }
    if (game.hProcess) {
        CloseHandle(game.hProcess);
    }
    if (attrs) {
        if (attrs_ready) {
            DeleteProcThreadAttributeList(attrs);
        }
        HeapFree(GetProcessHeap(), 0, attrs);
    }
    free(resolved_launcher);
    free(resolved_game);
    free(game_argv);
    free(lcmd);
    free(gcmd);
    return rc;
}

static BOOL is_digit(const WCHAR value) {
    return value >= L'0' && value <= L'9';
}

static BOOL is_numeric_version(const WCHAR *version) {
    BOOL need_digit = TRUE;

    for (; *version; version++) {
        if (is_digit(*version)) {
            need_digit = FALSE;
        } else if (*version == L'.' && !need_digit) {
            need_digit = TRUE;
        } else {
            return FALSE;
        }
    }
    return !need_digit;
}

static int compare_version_component(const WCHAR *left, size_t left_length,
                                     const WCHAR *right, size_t right_length) {
    while (left_length > 0 && *left == L'0') {
        left++;
        left_length--;
    }
    while (right_length > 0 && *right == L'0') {
        right++;
        right_length--;
    }

    if (left_length != right_length) {
        return left_length < right_length ? -1 : 1;
    }
    const int result = wmemcmp(left, right, left_length);
    return (result > 0) - (result < 0);
}

static int compare_versions(const WCHAR *left, const WCHAR *right) {
    while (*left || *right) {
        const WCHAR *left_end = left;
        const WCHAR *right_end = right;
        while (is_digit(*left_end)) {
            left_end++;
        }
        while (is_digit(*right_end)) {
            right_end++;
        }

        const int component = compare_version_component(
            left, (size_t)(left_end - left), right, (size_t)(right_end - right));
        if (component != 0) {
            return component;
        }

        left = *left_end == L'.' ? left_end + 1 : left_end;
        right = *right_end == L'.' ? right_end + 1 : right_end;
    }
    return 0;
}

static WCHAR *get_full_path(const WCHAR *path) {
    const DWORD size = GetFullPathNameW(path, 0, nullptr, nullptr);
    if (size == 0) {
        show_win32_error(L"无法解析启动器路径", GetLastError());
        return nullptr;
    }

    WCHAR *full_path = malloc((size_t)size * sizeof(WCHAR));
    if (!full_path) {
        show_error(L"内存不足");
        return nullptr;
    }

    const DWORD written = GetFullPathNameW(path, size, full_path, nullptr);
    if (written == 0 || written >= size) {
        const DWORD code = GetLastError();
        free(full_path);
        show_win32_error(L"无法解析启动器路径", code);
        return nullptr;
    }
    return full_path;
}

static WCHAR *join_path(const WCHAR *directory, const WCHAR *name) {
    const size_t directory_length = wcslen(directory);
    const size_t name_length = wcslen(name);
    const BOOL has_separator = directory_length > 0
        && (directory[directory_length - 1] == L'\\' || directory[directory_length - 1] == L'/');
    WCHAR *path = malloc((directory_length + name_length + (has_separator ? 1 : 2)) * sizeof(WCHAR));
    if (!path) {
        show_error(L"内存不足");
        return nullptr;
    }

    memcpy(path, directory, directory_length * sizeof(WCHAR));
    size_t offset = directory_length;
    if (!has_separator) {
        path[offset++] = L'\\';
    }
    memcpy(path + offset, name, (name_length + 1) * sizeof(WCHAR));
    return path;
}

static WCHAR *resolve_launcher_path(const WCHAR *path) {
    WCHAR *full_path = get_full_path(path);
    if (!full_path) {
        return nullptr;
    }

    const DWORD attributes = GetFileAttributesW(full_path);
    if (attributes == INVALID_FILE_ATTRIBUTES) {
        const DWORD code = GetLastError();
        free(full_path);
        show_win32_error(L"启动器路径不存在", code);
        return nullptr;
    }

    WCHAR *launcher_root = nullptr;
    if (attributes & FILE_ATTRIBUTE_DIRECTORY) {
        launcher_root = full_path;
    } else {
        const WCHAR *filename = wcsrchr(full_path, L'\\');
        const WCHAR *forward_separator = wcsrchr(full_path, L'/');
        if (!filename || (forward_separator && forward_separator > filename)) {
            filename = forward_separator;
        }
        filename = filename ? filename + 1 : full_path;
        const WCHAR *extension = wcsrchr(filename, L'.');
        if (!extension || _wcsicmp(extension, L".exe") != 0) {
            free(full_path);
            show_error(L"启动器文件参数必须是 .exe 文件；只有指定目录时才会自动查找 Games.exe");
            return nullptr;
        }
        return full_path;
    }

    WCHAR *games_path = join_path(launcher_root, L"Games.exe");
    if (!games_path) {
        free(launcher_root);
        return nullptr;
    }
    DWORD games_attributes = GetFileAttributesW(games_path);
    if (games_attributes != INVALID_FILE_ATTRIBUTES && !(games_attributes & FILE_ATTRIBUTE_DIRECTORY)) {
        free(launcher_root);
        return games_path;
    }
    free(games_path);

    WCHAR *search_pattern = join_path(launcher_root, L"*");
    if (!search_pattern) {
        free(launcher_root);
        return nullptr;
    }

    WIN32_FIND_DATAW entry;
    HANDLE search = FindFirstFileW(search_pattern, &entry);
    free(search_pattern);
    if (search == INVALID_HANDLE_VALUE) {
        const DWORD code = GetLastError();
        free(launcher_root);
        show_win32_error(L"无法查找启动器版本目录", code);
        return nullptr;
    }

    WCHAR *best_games_path = nullptr;
    WCHAR *best_version = nullptr;
    BOOL allocation_failed = FALSE;
    DWORD search_error = ERROR_SUCCESS;
    for (;;) {
        if ((entry.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
            && is_numeric_version(entry.cFileName)) {
            WCHAR *version_directory = join_path(launcher_root, entry.cFileName);
            if (!version_directory) {
                allocation_failed = TRUE;
                break;
            }
            games_path = join_path(version_directory, L"Games.exe");
            free(version_directory);
            if (!games_path) {
                allocation_failed = TRUE;
                break;
            }

            games_attributes = GetFileAttributesW(games_path);
            if (games_attributes != INVALID_FILE_ATTRIBUTES
                && !(games_attributes & FILE_ATTRIBUTE_DIRECTORY)
                && (!best_version || compare_versions(entry.cFileName, best_version) > 0)) {
                WCHAR *version_copy = _wcsdup(entry.cFileName);
                if (!version_copy) {
                    free(games_path);
                    show_error(L"内存不足");
                    allocation_failed = TRUE;
                    break;
                }
                free(best_games_path);
                free(best_version);
                best_games_path = games_path;
                best_version = version_copy;
            } else {
                free(games_path);
            }
        }

        if (!FindNextFileW(search, &entry)) {
            search_error = GetLastError();
            break;
        }
    }

    FindClose(search);
    free(launcher_root);
    free(best_version);

    if (allocation_failed) {
        free(best_games_path);
        return nullptr;
    }
    if (search_error != ERROR_NO_MORE_FILES) {
        free(best_games_path);
        show_win32_error(L"读取启动器版本目录失败", search_error);
        return nullptr;
    }
    if (!best_games_path) {
        show_error(L"启动器目录中未找到数字版本目录下的 Games.exe");
        return nullptr;
    }
    return best_games_path;
}

static WCHAR *resolve_game_path(const WCHAR *path) {
    const DWORD attributes = GetFileAttributesW(path);
    if (attributes == INVALID_FILE_ATTRIBUTES) {
        show_win32_error(L"游戏路径不存在", GetLastError());
        return nullptr;
    }

    if (!(attributes & FILE_ATTRIBUTE_DIRECTORY)) {
        const WCHAR *filename = wcsrchr(path, L'\\');
        const WCHAR *forward_separator = wcsrchr(path, L'/');
        if (!filename || (forward_separator && forward_separator > filename)) {
            filename = forward_separator;
        }
        filename = filename ? filename + 1 : path;
        const WCHAR *extension = wcsrchr(filename, L'.');
        if (!extension || _wcsicmp(extension, L".exe") != 0) {
            show_error(L"游戏文件参数必须是 .exe 文件；只有指定目录时才会自动查找游戏程序");
            return nullptr;
        }

        WCHAR *game_path = get_full_path(path);
        if (!game_path) {
            return nullptr;
        }
        return game_path;
    }

    WCHAR *directory = get_full_path(path);
    if (!directory) {
        return nullptr;
    }

    static const WCHAR *const game_names[] = {
        L"Endfield.exe",
        L"Arknights.exe", // 当前版本还没有，但留作备用
    };
    for (size_t i = 0; i < ARRAYSIZE(game_names); i++) {
        WCHAR *game_path = join_path(directory, game_names[i]);
        if (!game_path) {
            free(directory);
            return nullptr;
        }
        const DWORD game_attributes = GetFileAttributesW(game_path);
        if (game_attributes != INVALID_FILE_ATTRIBUTES
            && !(game_attributes & FILE_ATTRIBUTE_DIRECTORY)) {
            free(directory);
            return game_path;
        }
        free(game_path);
    }

    free(directory);
    show_error(L"游戏目录中未找到 Endfield.exe 或 Arknights.exe");
    return nullptr;
}

// 按 MSVCRT/CommandLineToArgvW 的规则拼接一个参数，结果需要 3 * len + 3 个字符
static WCHAR *append_quoted_arg(WCHAR *dst, const WCHAR *arg) {
    size_t i;

    *dst++ = L'"';
    for (;; arg++) {
        size_t backslashes = 0;
        while (*arg == L'\\') {
            arg++;
            backslashes++;
        }

        if (*arg == L'\0') {
            for (i = 0; i < backslashes * 2; i++) {
                *dst++ = L'\\';
            }
            break;
        }
        if (*arg == L'"') {
            for (i = 0; i < backslashes * 2 + 1; i++) {
                *dst++ = L'\\';
            }
            *dst++ = L'"';
        } else {
            for (i = 0; i < backslashes; i++) {
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
    int i;

    for (i = 0; i < argc; i++) {
        total += wcslen(argv[i]) * 3 + 4;
    }

    WCHAR *cmd = malloc(total * sizeof(WCHAR));
    if (!cmd) {
        return nullptr;
    }

    WCHAR *p = cmd;
    for (i = 0; i < argc; i++) {
        if (i > 0) {
            *p++ = L' ';
        }
        p = append_quoted_arg(p, argv[i]);
    }
    *p = L'\0';
    return cmd;
}

static void show_error(const WCHAR *message) {
    MessageBoxW(nullptr, message, L"Endfield Launcher", MB_OK | MB_ICONERROR);
}

static void show_win32_error(const WCHAR *what, const DWORD code) {
    WCHAR buf[256];
    _snwprintf(buf, ARRAYSIZE(buf), L"%ls\n错误码: %lu", what, code);
    buf[ARRAYSIZE(buf) - 1] = L'\0';
    show_error(buf);
}
