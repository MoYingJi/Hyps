// 以启动器作为父进程拉起游戏，用于满足“必须通过启动器启动”的检查。
//
// 构建 (由 lib/games/endfield.sh 按需调用，需要 mingw-w64):
//   x86_64-w64-mingw32-gcc -municode -static -O2 -Wall -Wextra -o endfield-launcher.exe endfield-launcher.c
//
// 用法: endfield-launcher.exe <launcher.exe> <game.exe> [game args...]

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

// 按 MSVCRT/CommandLineToArgvW 的规则拼接一个参数，结果需要 3 * len + 3 个字符
static WCHAR *append_quoted_arg(WCHAR *dst, const WCHAR *arg)
{
    size_t i;
    size_t backslashes;

    *dst++ = L'"';
    for (;; arg++) {
        backslashes = 0;
        while (*arg == L'\\') {
            arg++;
            backslashes++;
        }

        if (*arg == L'\0') {
            for (i = 0; i < backslashes * 2; i++)
                *dst++ = L'\\';
            break;
        } else if (*arg == L'"') {
            for (i = 0; i < backslashes * 2 + 1; i++)
                *dst++ = L'\\';
            *dst++ = L'"';
        } else {
            for (i = 0; i < backslashes; i++)
                *dst++ = L'\\';
            *dst++ = *arg;
        }
    }
    *dst++ = L'"';
    return dst;
}

static WCHAR *build_cmdline(int argc, WCHAR **argv)
{
    size_t total = 1;
    int i;
    for (i = 0; i < argc; i++)
        total += wcslen(argv[i]) * 3 + 4;

    WCHAR *cmd = malloc(total * sizeof(WCHAR));
    if (!cmd)
        return NULL;

    WCHAR *p = cmd;
    for (i = 0; i < argc; i++) {
        if (i > 0)
            *p++ = L' ';
        p = append_quoted_arg(p, argv[i]);
    }
    *p = L'\0';
    return cmd;
}

static void print_error(const WCHAR *what)
{
    fwprintf(stderr, L"%ls 失败，错误码: %lu\n", what, GetLastError());
}

int wmain(int argc, WCHAR **argv)
{
    if (argc < 3) {
        fwprintf(stderr, L"用法: %ls <launcher.exe> <game.exe> [args...]\n", argv[0]);
        return 2;
    }

    int exit_code = 1;
    WCHAR *lcmd = NULL;
    WCHAR *gcmd = NULL;
    LPPROC_THREAD_ATTRIBUTE_LIST attrs = NULL;
    PROCESS_INFORMATION lpi = { 0 };
    PROCESS_INFORMATION pi = { 0 };

    lcmd = build_cmdline(1, &argv[1]);
    gcmd = build_cmdline(argc - 2, &argv[2]);
    if (!lcmd || !gcmd) {
        fwprintf(stderr, L"内存不足\n");
        goto cleanup;
    }

    // 启动器以挂起状态创建且永不恢复，仅作为父进程句柄使用
    STARTUPINFOW lsi;
    ZeroMemory(&lsi, sizeof(lsi));
    lsi.cb = sizeof(lsi);
    if (!CreateProcessW(NULL, lcmd, NULL, NULL, FALSE, CREATE_SUSPENDED, NULL, NULL, &lsi, &lpi)) {
        print_error(L"以挂起状态启动启动器");
        goto cleanup;
    }
    CloseHandle(lpi.hThread);

    SIZE_T size = 0;
    InitializeProcThreadAttributeList(NULL, 1, 0, &size);
    attrs = HeapAlloc(GetProcessHeap(), 0, size);
    if (!attrs || !InitializeProcThreadAttributeList(attrs, 1, 0, &size)) {
        print_error(L"初始化进程属性列表");
        goto cleanup;
    }

    HANDLE parent = lpi.hProcess;
    if (!UpdateProcThreadAttribute(attrs, 0, PROC_THREAD_ATTRIBUTE_PARENT_PROCESS,
                                   &parent, sizeof(parent), NULL, NULL)) {
        print_error(L"设置父进程属性");
        goto cleanup;
    }

    STARTUPINFOEXW si;
    ZeroMemory(&si, sizeof(si));
    si.StartupInfo.cb = sizeof(si);
    si.lpAttributeList = attrs;
    if (!CreateProcessW(NULL, gcmd, NULL, NULL, FALSE, EXTENDED_STARTUPINFO_PRESENT,
                        NULL, NULL, &si.StartupInfo, &pi)) {
        print_error(L"启动游戏");
        goto cleanup;
    }
    CloseHandle(pi.hThread);

    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD game_code = 0;
    if (GetExitCodeProcess(pi.hProcess, &game_code))
        exit_code = (int)game_code;
    CloseHandle(pi.hProcess);

cleanup:
    if (lpi.hProcess) {
        TerminateProcess(lpi.hProcess, 0);
        CloseHandle(lpi.hProcess);
    }
    if (attrs) {
        DeleteProcThreadAttributeList(attrs);
        HeapFree(GetProcessHeap(), 0, attrs);
    }
    free(lcmd);
    free(gcmd);
    return exit_code;
}
