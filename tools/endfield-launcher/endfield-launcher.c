// 以启动器作为父进程拉起游戏，用于满足“必须通过启动器启动”的检查。
//
// 构建 (由 lib/games/endfield.sh 按需调用，需要 mingw-w64):
//   x86_64-w64-mingw32-gcc -municode -static -O2 -Wall -Wextra -o endfield-launcher.exe endfield-launcher.c
//
// 用法: endfield-launcher.exe <launcher.exe> <game.exe> [game args...]

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <wchar.h>

static WCHAR *append_quoted_arg(WCHAR *dst, const WCHAR *arg);
static WCHAR *build_cmdline(int argc, WCHAR **argv);
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
    WCHAR *lcmd = nullptr;
    WCHAR *gcmd = nullptr;
    DWORD code = 0;
    int rc = 1;

    ZeroMemory(&launcher, sizeof(launcher));
    ZeroMemory(&game, sizeof(game));

    if (argc < 3) {
        show_error(L"用法: endfield-launcher.exe <launcher.exe> <game.exe> [args...]");
        return 2;
    }

    lcmd = build_cmdline(1, &argv[1]);
    gcmd = build_cmdline(argc - 2, &argv[2]);
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
    free(lcmd);
    free(gcmd);
    return rc;
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
