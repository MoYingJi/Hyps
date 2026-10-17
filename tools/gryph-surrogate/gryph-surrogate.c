// gryph-surrogate：鹰角 (Hypergryph / Gryphline) 游戏通用的父进程替身工具
// 终末地要求游戏必须由官方启动器拉起，会检查三项内容
// 直接父进程的文件名、父进程磁盘文件的 Authenticode 签名是否可信，以及签名证书的指纹
// 本工具会先准备一个替身文件，再将它挂起，让它充当游戏的父进程
// 目前仅终末地有此需求，但理论支持所有检测逻辑相同的游戏
//
// 构建:
//   x86_64-w64-mingw32-gcc -municode -static -O2 -Wall -Wextra -o gryph-surrogate.exe gryph-surrogate.c
//
// 用法: 选项写在前面 遇到的第一个非选项参数是游戏路径 之后的参数都会原样传给游戏
//
//   gryph-surrogate.exe <启动器目录|exe> <游戏路径> [游戏参数...]
//     旧写法，不写 --mode 时即为 launcher 模式，第一个位置参数是启动器
//     启动器可以是目录，此时会选用版本号最大的数字目录中的 Games.exe，也可以直接指定 exe 文件
//
//   gryph-surrogate.exe --launcher <启动器目录|exe> <游戏路径> [游戏参数...]
//     效果与旧写法相同，使用 --launcher 后，位置参数里不再包含启动器
//
//   gryph-surrogate.exe --mode launcher --launcher <启动器> <游戏路径> [游戏参数...]
//     显式指定 launcher 模式，此时必须用 --launcher 给出启动器
//
//   gryph-surrogate.exe --mode hardlink|copy|hardlink-or-copy
//         [--launcher <源文件>] [--target <目标文件>] [--keep-surrogate]
//         <游戏路径> [游戏参数...]
//     替身模式: 把源文件做成目标文件（硬链接或复制），再将目标文件挂起，作为游戏的父进程
//     - 不写 --launcher 时，源文件就是游戏 exe 本身
//       这样做可行，是因为游戏目录里的几个 PE 与官方启动器的 Games.exe 使用同一张 HG 代码签名证书
//     - 不写 --target 时，目标默认放在 <游戏目录>\..\gryph-surrogate\Games.exe
//       该位置和游戏目录在同一个盘上，硬链接更容易成功，而且不会往游戏目录里写文件
//     - 目标已存在时，会先校验再决定是否复用
//       hardlink 检查两者是否为同一份物理文件
//       copy 检查大小和修改时间是否一致
//       hardlink-or-copy 满足其中任一条件即可复用
//       校验不通过或文件不存在时，会重新生成
//     - hardlink 失败时直接报错，不回退
//       hardlink-or-copy 会先尝试硬链接，失败（例如跨盘）后改用复制
//     - 目标文件名不做限制，游戏侧会检查文件名，改用其他名字的话...用户这么做一定有道理
//     - 游戏退出后默认删除替身文件，再逐层删除本次运行新建的空目录
//       遇到非空目录会停止，运行前已存在的目录不会删除
//     - 加上 --keep-surrogate 时保留替身文件和目录，该选项在 launcher 模式下不可用
//
// 注意：上面三项校验读取的是父进程映像路径指向的磁盘文件本身
// 普通程序改名为 Games.exe 无法通过信任和指纹检查，替身必须来自真正签名的文件
// 游戏版本更新后签名证书可能会更换，到时重新检查游戏目录里 PE 文件的签名证书即可

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

typedef enum {
    MODE_LAUNCHER = 0,       // 挂起官方启动器作为父进程
    MODE_HARDLINK,           // 硬链接替身，失败不回退
    MODE_COPY,               // 复制替身
    MODE_HARDLINK_OR_COPY,   // 先试硬链接，失败时改用复制
} LAUNCH_MODE;

// 解析后的命令行参数
typedef struct {
    LAUNCH_MODE mode;
    const WCHAR *launcher;  // launcher 模式下是启动器路径，替身模式下是替身源文件，为 NULL 时使用游戏 exe 本身
    const WCHAR *target;    // 替身目标文件，为 NULL 时使用默认位置
    BOOL keep_surrogate;    // 替身模式下是否保留替身文件和目录，默认删除
    int game_index;         // 游戏路径在 argv 中的下标
    int game_args_index;    // 第一个游戏参数的下标，即 game_index + 1
} OPTIONS;

static LAUNCH_MODE parse_mode(const WCHAR *value);
static void show_usage();
static int parse_command_line(int argc, WCHAR *argv[], OPTIONS *opts);
static WCHAR *surrogate_default_target(const WCHAR *game_exe);
static WCHAR *surrogate_prepare(const OPTIONS *opts, const WCHAR *game_exe, WCHAR **created_root);
static int launch_game_chain(WCHAR *surrogate_path, int game_argc, WCHAR **game_argv);
static BOOL open_file_info(const WCHAR *path, HANDLE *handle, BY_HANDLE_FILE_INFORMATION *info);
static BOOL is_same_file(const WCHAR *left, const WCHAR *right);
static BOOL copy_matches_source(const WCHAR *source, const WCHAR *link);
static BOOL delete_if_exists(const WCHAR *path);
static void remove_created_directories(const WCHAR *file_path, const WCHAR *created_root);
static void remove_surrogate(const WCHAR *path, const WCHAR *created_root);
static BOOL ensure_parent_directory(const WCHAR *target, WCHAR **created_root);
static WCHAR *surrogate_make_link(const WCHAR *source, LAUNCH_MODE mode, const WCHAR *target,
                                  WCHAR **created_root);
static BOOL is_digit(WCHAR value);
static BOOL is_numeric_version(const WCHAR *version);
static int compare_version_component(const WCHAR *left, size_t left_length,
                                     const WCHAR *right, size_t right_length);
static int compare_versions(const WCHAR *left, const WCHAR *right);
static WCHAR *get_full_path(const WCHAR *path);
static WCHAR *join_path(const WCHAR *directory, const WCHAR *name);
static WCHAR *resolve_launcher_path(const WCHAR *path);
static WCHAR *resolve_game_path(const WCHAR *path);
static WCHAR *append_quoted_arg(WCHAR *dst, const WCHAR *arg);
static WCHAR *build_cmdline(int argc, WCHAR **argv);
static void show_error(const WCHAR *message);
static void show_win32_error(const WCHAR *what, DWORD code);

int wmain(const int argc, WCHAR *argv[]) {
    OPTIONS opts;
    const int parse_rc = parse_command_line(argc, argv, &opts);
    if (parse_rc != 0) {
        return parse_rc;
    }

    WCHAR *resolved_game = resolve_game_path(argv[opts.game_index]);
    if (!resolved_game) {
        return 1;
    }

    // game_argv[0] 是解析后的游戏绝对路径，后面依次是原始的游戏参数
    const int game_argc = argc - opts.game_args_index + 1;
    WCHAR **game_argv = malloc((size_t)game_argc * sizeof(*game_argv));
    if (!game_argv) {
        show_error(L"内存不足");
        free(resolved_game);
        return 1;
    }
    game_argv[0] = resolved_game;
    for (int k = 1; k < game_argc; k++) {
        game_argv[k] = argv[opts.game_args_index + k - 1];
    }

    // 要挂起的父进程 exe
    // launcher 模式下是启动器，传入目录时会从中查找 Games.exe
    // 替身模式下是刚准备好的替身文件，created_root 是本次新建的最上层目录，退出后用于逐层删除
    WCHAR *created_root = nullptr;
    WCHAR *surrogate_path = opts.mode == MODE_LAUNCHER
        ? resolve_launcher_path(opts.launcher)
        : surrogate_prepare(&opts, resolved_game, &created_root);
    if (!surrogate_path) {
        free(game_argv);
        free(resolved_game);
        return 1;
    }

    const int rc = launch_game_chain(surrogate_path, game_argc, game_argv);

    if (opts.mode != MODE_LAUNCHER && !opts.keep_surrogate) {
        remove_surrogate(surrogate_path, created_root);
    }
    free(created_root);
    free(surrogate_path);
    free(game_argv);
    free(resolved_game);
    return rc;
}

static LAUNCH_MODE parse_mode(const WCHAR *value) {
    if (!value || !*value) {
        return (LAUNCH_MODE)-1;
    }
    if (_wcsicmp(value, L"launcher") == 0) {
        return MODE_LAUNCHER;
    }
    if (_wcsicmp(value, L"hardlink") == 0) {
        return MODE_HARDLINK;
    }
    if (_wcsicmp(value, L"copy") == 0) {
        return MODE_COPY;
    }
    if (_wcsicmp(value, L"hardlink-or-copy") == 0) {
        return MODE_HARDLINK_OR_COPY;
    }
    return (LAUNCH_MODE)-1;
}

static void show_usage() {
    show_error(L"用法:\n"
        L"gryph-surrogate.exe <启动器目录|exe> <游戏路径> [游戏参数...]\n"
        L"gryph-surrogate.exe --launcher <启动器|exe> <游戏路径> [游戏参数...]\n"
        L"gryph-surrogate.exe --mode launcher --launcher <启动器|exe> <游戏路径> [游戏参数...]\n"
        L"gryph-surrogate.exe --mode hardlink|copy|hardlink-or-copy"
        L" [--launcher <源文件>] [--target <目标文件>] [--keep-surrogate]"
        L" <游戏路径> [游戏参数...]");
}

// 解析命令行，成功返回 0，失败返回一个正数作为退出码，错误信息已经显示过了
static int parse_command_line(const int argc, WCHAR *argv[], OPTIONS *opts) {
    LAUNCH_MODE mode = MODE_LAUNCHER;   // 没写 --mode 时默认为 launcher
    int has_mode = FALSE;
    int has_launcher = FALSE;
    const WCHAR *launcher_value = nullptr;
    const WCHAR *target_value = nullptr;
    int keep_surrogate = FALSE;

    // 选项写在前面，遇到第一个非选项参数就当作游戏路径，之后的全部都是游戏参数
    // 没写 --mode 时，有 --launcher 就用 launcher 模式，没有的话按旧写法处理，第一个位置参数是启动器
    int pos_start = -1;
    int i = 1;
    while (i < argc && pos_start < 0) {
        if (wcscmp(argv[i], L"--mode") == 0) {
            if (has_mode || i + 1 >= argc) {
                show_usage();
                return 2;
            }
            const LAUNCH_MODE parsed = parse_mode(argv[i + 1]);
            if (parsed == (LAUNCH_MODE)-1) {
                show_error(L"--mode 只接受 launcher / hardlink / copy / hardlink-or-copy");
                return 2;
            }
            mode = parsed;
            has_mode = TRUE;
            i += 2;
        } else if (wcscmp(argv[i], L"--launcher") == 0) {
            if (i + 1 >= argc) {
                show_usage();
                return 2;
            }
            launcher_value = argv[i + 1];
            has_launcher = TRUE;
            i += 2;
        } else if (wcscmp(argv[i], L"--target") == 0) {
            if (i + 1 >= argc) {
                show_usage();
                return 2;
            }
            target_value = argv[i + 1];
            i += 2;
        } else if (wcscmp(argv[i], L"--keep-surrogate") == 0) {
            keep_surrogate = TRUE;
            i++;
        } else {
            pos_start = i;
        }
    }

    if (pos_start < 0) {
        show_usage();
        return 2;
    }

    if (!has_mode && has_launcher) {
        mode = MODE_LAUNCHER;
    }

    ZeroMemory(opts, sizeof(*opts));
    opts->mode = mode;
    opts->target = target_value;
    opts->keep_surrogate = keep_surrogate;

    if (mode == MODE_LAUNCHER) {
        if (target_value) {
            // launcher 模式不会创建链接，所以不能用 --target
            show_error(L"--target 仅在替身模式（hardlink / copy / hardlink-or-copy）下可用");
            return 2;
        }
        if (keep_surrogate) {
            show_error(L"--keep-surrogate 仅在替身模式（hardlink / copy / hardlink-or-copy）下可用");
            return 2;
        }
        if (has_mode && !has_launcher) {
            // 显式 launcher 模式必须用 --launcher 指定启动器
            show_error(L"--mode launcher 需要显式 --launcher <启动器|exe>；"
                       L"兼容写法（位置参数给启动器）请同时省略 --mode");
            return 2;
        }
        if (has_launcher) {
            // 显式指定 launcher 时，位置参数从游戏路径开始
            opts->launcher = launcher_value;
        } else {
            // 旧写法: 位置参数依次是启动器、游戏路径，之后是游戏参数
            if (argc - pos_start < 2) {
                show_usage();
                return 2;
            }
            opts->launcher = argv[pos_start];
            pos_start++;
        }
        opts->game_index = pos_start;
    } else {
        opts->launcher = launcher_value;
        opts->game_index = pos_start;
    }
    opts->game_args_index = opts->game_index + 1;
    return 0;
}

// 推导默认替身目标 <游戏目录>\..\gryph-surrogate\Games.exe
// 该位置和游戏目录在同一个盘上，硬链接更容易成功，也不会往游戏目录里写文件
static WCHAR *surrogate_default_target(const WCHAR *game_exe) {
    const WCHAR *sep0 = wcsrchr(game_exe, L'\\');
    const WCHAR *sep1 = wcsrchr(game_exe, L'/');
    const WCHAR *last_sep = sep0 > sep1 ? sep0 : sep1;
    if (!last_sep || last_sep == game_exe) {
        show_error(L"无法推导默认替身目标（游戏路径缺少上级目录），请用 --target 显式指定");
        return nullptr;
    }

    // 同样的方法，再从游戏目录路径里找出它的上一级分隔符
    const WCHAR *dsep0 = nullptr;
    const WCHAR *dsep1 = nullptr;
    for (const WCHAR *p = game_exe; p < last_sep; p++) {
        if (*p == L'\\') {
            dsep0 = p;
        } else if (*p == L'/') {
            dsep1 = p;
        }
    }
    const WCHAR *game_dir_last_sep = dsep0 > dsep1 ? dsep0 : dsep1;
    if (!game_dir_last_sep) {
        show_error(L"无法推导默认替身目标（游戏目录缺少上级目录），请用 --target 显式指定");
        return nullptr;
    }

    const size_t parent_len = (size_t)(game_dir_last_sep - game_exe);
    WCHAR *parent = malloc((parent_len + 1) * sizeof(WCHAR));
    if (!parent) {
        show_error(L"内存不足");
        return nullptr;
    }
    wmemcpy(parent, game_exe, parent_len);
    parent[parent_len] = L'\0';

    WCHAR *base = join_path(parent, L"gryph-surrogate");
    free(parent);
    if (!base) {
        show_error(L"内存不足");
        return nullptr;
    }
    WCHAR *target = join_path(base, L"Games.exe");
    free(base);
    if (!target) {
        show_error(L"内存不足");
        return nullptr;
    }
    return target;
}

// 确定替身模式的源和目标，准备替身文件
// 成功时返回替身的可执行路径，由调用方负责释放
// 本次新建的最上层目录会写入 created_root，失败时这些空目录会被删掉
static WCHAR *surrogate_prepare(const OPTIONS *opts, const WCHAR *game_exe, WCHAR **created_root) {
    // 替身源默认是游戏 exe 本身
    // 指定了 --launcher 时，它必须是文件，不能是目录
    const WCHAR *source = opts->launcher ? opts->launcher : game_exe;
    if (opts->launcher) {
        const DWORD source_attributes = GetFileAttributesW(opts->launcher);
        if (source_attributes == INVALID_FILE_ATTRIBUTES) {
            show_win32_error(L"替身源文件不存在", GetLastError());
            return nullptr;
        }
        if (source_attributes & FILE_ATTRIBUTE_DIRECTORY) {
            show_error(L"替身模式下 --launcher 必须指向源文件本身，目录只支持 launcher 模式");
            return nullptr;
        }
    }

    WCHAR *target;
    if (opts->target) {
        target = _wcsdup(opts->target);
        if (!target) {
            show_error(L"内存不足");
            return nullptr;
        }
    } else {
        target = surrogate_default_target(game_exe);
        if (!target) {
            return nullptr;
        }
    }

    WCHAR *surrogate = surrogate_make_link(source, opts->mode, target, created_root);
    if (!surrogate && *created_root) {
        remove_created_directories(target, *created_root);
        free(*created_root);
        *created_root = nullptr;
    }
    free(target);
    return surrogate;
}

// 以挂起的 surrogate_path 作为父进程启动游戏 game_argv
// 游戏退出后，原样返回它的退出码
// 失败返回 1，成功返回游戏退出码
static int launch_game_chain(WCHAR *surrogate_path, const int game_argc, WCHAR **game_argv) {
    PROCESS_INFORMATION launcher;
    PROCESS_INFORMATION game;
    STARTUPINFOW si;
    STARTUPINFOEXW siex;
    LPPROC_THREAD_ATTRIBUTE_LIST attrs = nullptr;
    BOOL attrs_ready = FALSE;
    SIZE_T attrs_size = 0;
    WCHAR *lcmd_argv[] = {surrogate_path};
    WCHAR *lcmd = build_cmdline(1, lcmd_argv);
    WCHAR *gcmd = build_cmdline(game_argc, game_argv);
    DWORD code = 0;
    int rc = 1;

    ZeroMemory(&launcher, sizeof(launcher));
    ZeroMemory(&game, sizeof(game));
    if (!lcmd || !gcmd) {
        show_error(L"内存不足");
        goto cleanup;
    }

    // 挂起的父进程只用来提供父进程句柄，它的主线程不会被恢复运行
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    if (!CreateProcessW(nullptr, lcmd, nullptr, nullptr, FALSE, CREATE_SUSPENDED,
                        NULL, nullptr, &si, &launcher)) {
        show_win32_error(L"无法创建挂起的父进程", GetLastError());
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
        // 等父进程真正退出后，替身文件才不再被占用，之后才能删除
        WaitForSingleObject(launcher.hProcess, 5000);
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


// ── 父进程替身 ──────────────────────────────────────────────

static BOOL open_file_info(const WCHAR *path, HANDLE *handle, BY_HANDLE_FILE_INFORMATION *info) {
    *handle = CreateFileW(path, 0,
                          FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                          nullptr, OPEN_EXISTING, 0, nullptr);
    if (*handle == INVALID_HANDLE_VALUE) {
        return FALSE;
    }
    if (!GetFileInformationByHandle(*handle, info)) {
        CloseHandle(*handle);
        return FALSE;
    }
    return TRUE;
}

static BOOL is_same_file(const WCHAR *left, const WCHAR *right) {
    HANDLE hl = INVALID_HANDLE_VALUE;
    HANDLE hr = INVALID_HANDLE_VALUE;
    BY_HANDLE_FILE_INFORMATION il;
    BY_HANDLE_FILE_INFORMATION ir;
    if (!open_file_info(left, &hl, &il) || !open_file_info(right, &hr, &ir)) {
        if (hl != INVALID_HANDLE_VALUE) {
            CloseHandle(hl);
        }
        if (hr != INVALID_HANDLE_VALUE) {
            CloseHandle(hr);
        }
        return FALSE;
    }
    CloseHandle(hl);
    CloseHandle(hr);
    // 卷序列号和文件索引都相同，说明两个路径指向同一份磁盘数据（硬链接），可以直接复用
    return il.dwVolumeSerialNumber == ir.dwVolumeSerialNumber
        && il.nFileIndexHigh == ir.nFileIndexHigh
        && il.nFileIndexLow == ir.nFileIndexLow;
}

// 判断已有的复制品是否与源文件一致，即大小和最后修改时间都相同
static BOOL copy_matches_source(const WCHAR *source, const WCHAR *link) {
    WIN32_FILE_ATTRIBUTE_DATA sf;
    WIN32_FILE_ATTRIBUTE_DATA lf;
    if (!GetFileAttributesExW(source, GetFileExInfoStandard, &sf)
        || !GetFileAttributesExW(link, GetFileExInfoStandard, &lf)) {
        return FALSE;
    }
    return sf.dwFileAttributes == lf.dwFileAttributes
        && sf.nFileSizeHigh == lf.nFileSizeHigh
        && sf.nFileSizeLow == lf.nFileSizeLow
        && CompareFileTime(&sf.ftLastWriteTime, &lf.ftLastWriteTime) == 0;
}

static BOOL delete_if_exists(const WCHAR *path) {
    if (!DeleteFileW(path)) {
        const DWORD error = GetLastError();
        if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND) {
            return TRUE;
        }
        show_win32_error(L"无法清理旧替身文件", error);
        return FALSE;
    }
    return TRUE;
}

// 从 file_path 所在目录开始，逐层向上删除空目录，直到 created_root 为止
// 遇到非空目录会停止，created_root 之上的目录不会被删除
static void remove_created_directories(const WCHAR *file_path, const WCHAR *created_root) {
    WCHAR *dir = _wcsdup(file_path);
    if (!dir) {
        return;
    }
    const size_t root_len = wcslen(created_root);
    size_t len = wcslen(dir);
    while (true) {
        // 去掉最后一级（文件名或目录名）及其前面的分隔符
        while (len > 0 && dir[len - 1] != L'\\' && dir[len - 1] != L'/') {
            len--;
        }
        while (len > 0 && (dir[len - 1] == L'\\' || dir[len - 1] == L'/')) {
            len--;
        }
        if (len == 0 || len < root_len) {
            break;
        }
        dir[len] = L'\0';
        if (!RemoveDirectoryW(dir) || len == root_len) {
            break;
        }
    }
    free(dir);
}

// 游戏退出后删除替身文件，再删除本次运行新建的空目录
static void remove_surrogate(const WCHAR *path, const WCHAR *created_root) {
    if (!DeleteFileW(path)) {
        const DWORD error = GetLastError();
        if (error != ERROR_FILE_NOT_FOUND && error != ERROR_PATH_NOT_FOUND) {
            show_win32_error(L"无法删除替身文件", error);
            return;
        }
    }
    if (created_root) {
        remove_created_directories(path, created_root);
    }
}

// 逐级创建目标路径的父目录，已存在的盘符根和末尾分隔符会跳过
// 最上层的新建目录会写入 created_root，已经记录过则不再覆盖
static BOOL ensure_parent_directory(const WCHAR *target, WCHAR **created_root) {
    // 取出目标文件名之前的部分，然后逐级创建
    size_t last_len = wcslen(target);
    while (last_len > 0 && target[last_len - 1] != L'\\' && target[last_len - 1] != L'/') {
        last_len--;
    }
    if (last_len == 0) {
        return TRUE; // 目标没有目录部分，位于当前目录下，无需创建
    }

    WCHAR *dir = malloc((last_len + 1) * sizeof(WCHAR));
    if (!dir) {
        show_error(L"内存不足");
        return FALSE;
    }
    wmemcpy(dir, target, last_len);
    dir[last_len] = L'\0';
    // 去掉末尾的分隔符
    while (last_len > 0 && (dir[last_len - 1] == L'\\' || dir[last_len - 1] == L'/')) {
        dir[--last_len] = L'\0';
    }
    if (last_len == 0) {
        free(dir);
        return TRUE; // 目标全是分隔符，即盘符根目录，无需创建
    }

    for (size_t pos = 0; pos < last_len; pos++) {
        if (!(dir[pos] == L'\\' || dir[pos] == L'/') && pos != last_len - 1) {
            continue;
        }
        const size_t component_end = dir[pos] == L'\\' || dir[pos] == L'/' ? pos : last_len;
        const WCHAR saved = dir[component_end];
        dir[component_end] = L'\0';
        if (component_end == 0 || (component_end == 2 && dir[1] == L':')) {
            // 空前缀（UNC 路径开头的分隔符）或盘符（如 Z:），跳过
            dir[component_end] = saved;
            continue;
        }
        if (!CreateDirectoryW(dir, nullptr)) {
            const DWORD error = GetLastError();
            if (error != ERROR_ALREADY_EXISTS) {
                show_win32_error(L"无法创建替身目录", error);
                free(dir);
                return FALSE;
            }
        } else if (!*created_root) {
            *created_root = _wcsdup(dir);
            if (!*created_root) {
                show_error(L"内存不足");
                free(dir);
                return FALSE;
            }
        }
        dir[component_end] = saved;
    }
    free(dir);
    return TRUE;
}

// 创建、校验或复用替身文件，返回替身的可执行路径，由调用方负责释放
// 目标已存在时先按 mode 校验，校验不通过或目标不存在，则按 mode 重新生成
static WCHAR *surrogate_make_link(const WCHAR *source, const LAUNCH_MODE mode, const WCHAR *target,
                                  WCHAR **created_root) {
    if (!ensure_parent_directory(target, created_root)) {
        return nullptr;
    }

    const DWORD target_attributes = GetFileAttributesW(target);
    if (target_attributes != INVALID_FILE_ATTRIBUTES
        && (target_attributes & FILE_ATTRIBUTE_DIRECTORY)) {
        show_error(L"替身目标已存在且是目录，无法作为可执行文件使用");
        return nullptr;
    }

    // 检查已有的目标文件
    if (target_attributes != INVALID_FILE_ATTRIBUTES) {
        BOOL reuse = FALSE;
        if (mode == MODE_HARDLINK || mode == MODE_HARDLINK_OR_COPY) {
            reuse = is_same_file(source, target);
        }
        if (!reuse && (mode == MODE_COPY || mode == MODE_HARDLINK_OR_COPY)) {
            reuse = copy_matches_source(source, target);
        }
        if (reuse) {
            return _wcsdup(target);
        }
    }

    // 重新生成
    if (!delete_if_exists(target)) {
        return nullptr;
    }

    if (mode == MODE_HARDLINK || mode == MODE_HARDLINK_OR_COPY) {
        if (CreateHardLinkW(target, source, nullptr)) {
            return _wcsdup(target);
        }
        if (mode == MODE_HARDLINK) {
            // --mode hardlink 不允许回退，直接报告失败原因
            show_win32_error(L"硬链接创建失败（--mode hardlink 不回退，"
                             L"常见原因：源与目标不在同一文件系统）", GetLastError());
            return nullptr;
        }
    }

    if (CopyFileW(source, target, FALSE)) {
        return _wcsdup(target);
    }

    show_win32_error(L"复制替身文件失败", GetLastError());
    return nullptr;
}

// ── 路径解析 ────────────────────────────────────────────────

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
    while (true) {
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
        // 这两款游戏目前还没有启动器校验，但同属鹰角启动器，先留作备用，未经测试
        L"Arknights.exe",
        L"Popucom.exe",
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
    show_error(L"游戏目录中未找到 Endfield.exe / Arknights.exe / Popucom.exe");
    return nullptr;
}

// 按 MSVCRT 和 CommandLineToArgvW 的规则给参数加上引号并转义，最多需要 3 * len + 3 个字符
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
    MessageBoxW(nullptr, message, L"Hyps gryph-surrogate", MB_OK | MB_ICONERROR);
}

static void show_win32_error(const WCHAR *what, const DWORD code) {
    WCHAR buf[256];
    _snwprintf(buf, ARRAYSIZE(buf), L"%ls\n错误码: %lu", what, code);
    buf[ARRAYSIZE(buf) - 1] = L'\0';
    show_error(buf);
}
