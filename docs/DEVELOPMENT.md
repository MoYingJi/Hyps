# 开发指南

> 先写一点基础的

## 总览

项目主体在 `lib/` 下，用 bash 写，游戏和 CLI 入口点在 `scripts/`

在 `tools/` 下有一些小工具，都完全可以脱离本项目独立运行，有使用 Python 和 C 语言写的
 - C 语言推荐使用 clangd 作为 LSP，执行 `development/gen-compile-db.sh` 生成 `compile_commands.json` 文件给 clangd 用
 - `gryph-surrogate` 需要用 `mingw-w64` 交叉编译
 - `xwin-watch` 中，`protocols/` 下是协议 XML 文件，`generated/` 是 `wayland-scanner` 生成的文件，也一并提交到了 git，当协议 XML 文件有变动时，执行 `development/gen-wayland-protocols.sh` 重新生成文件到 `generated/`

## 生命周期

一共有七个阶段
 - `load_config`: 加载和校验配置。无文件系统副作用，不挂载。任意失败立即退出
 - `prepare_offline`: 必须在游戏 runtime 视图之外完成的准备（写 lower/upper、打游戏文件补丁、恢复上次残留）。有副作用，任意失败立即跳到 `cleanup`
 - `prepare`: 在 runtime 视图内完成的准备（overlay 开启时为 mount）。有副作用，任意失败立即跳到 `cleanup`
 - `pre_start`: 启动前最后检查。有副作用，任意失败立即跳到 `cleanup`
 - `post_start`: 启动后。有副作用，任意失败会继续执行
 - `cleanup`: runtime 视图卸载前的清理。有副作用，任意失败会继续执行
 - `cleanup_offline`: runtime 视图卸载后的清理（恢复/删除 upper 内的补丁文件）。有副作用，任意失败会继续执行

核心在两个阶段之间执行不是钩子的步骤：

```text
run_hooks load_config
game_fs_init
game_fs_apply_launch_plan
game_fs_require_launchable
run_hooks prepare_offline
game_fs_mount        # overlay 开启时
run_hooks prepare
...
run_hooks cleanup
game_fs_unmount
run_hooks cleanup_offline
```

核心在每个阶段前调用 `game_fs_set_phase`，写路径 helper 据此校验。可通过 `register_hook <阶段> <函数名> [优先级] [依赖关系]` 注册钩子。`defer_mkdir` 统一在 `prepare` 阶段创建（即 runtime 视图内）；如果某个目录必须在挂载前创建，应在 `prepare_offline` 中用 `game_fs_write_path writable` 显式创建

## GameFS

`lib/launch/game_fs.sh` 是游戏文件系统视图的唯一所有者。配置仍使用 `overlay.*`，`overlay.enabled` 控制开关，overlay 使用 FUSE OverlayFS。未启用 overlay 时，`runtime`、`writable`、`install` 都指向游戏安装目录

exe / install 根解析：

- 至少需要 `game.exe` 或 `game.install_dir`
- 只填 `game.exe`：install 由 `game_install_dir(exe)` 派生，没实现就留空
- 只填 `game.install_dir`：exe 由 `game_executable(install)` 派生
- 两者都填：使用配置，校验 exe 在 install 下
- `game_executable` 只返回一个主 exe，必须绝对路径、存在、位于 install 下；显式 `game.exe` 优先
- `game.cwd` 未配置时，install 已知取 install 根，否则取解析后 exe 所在目录
- install 未知时 `install_ok=0`，overlay 和依赖 install 的功能会报错；纯启动仍可用 `game.exe` / `game.cwd`

| 作用域 | overlay 关闭 | overlay 开启 | 用途 |
| --- | --- | --- | --- |
| `install` | 游戏安装目录 | lower | 读原版文件、检测真实文件系统 |
| `runtime` | 游戏安装目录 | mount | 游戏实际看到的合并视图 |
| `writable` | 游戏安装目录 | upper | 游戏写入落点，或挂载前写 upper |
| `all` | 游戏安装目录 | lower + upper | 离线失效/清理同时处理两份 |
| `prefix` / `userprofile` | prefix 内路径 | 同左 | 用户目录、注册表等 |
| `cache` / `data` / `state` / `temp` | XDG 路径 | 同左 | 通用数据 |

常用函数：
 - `game_fs_path <scope> <相对路径>`：只解析路径，不做阶段限制
 - `game_fs_paths <scope> <相对路径>`：每行输出 `<view>\t<绝对路径>`；`all` 在 overlay 关闭时输出 `install`，开启时输出 `lower`/`upper`
 - `game_fs_write_path` / `game_fs_write_paths`：解析路径并做写阶段校验
 - `game_fs_assert_mutation <scope>`：外部工具或复杂操作写前显式校验
 - `game_fs_root <scope>`：输出某个作用域的根
 - `game_fs_display <scope> <相对路径>`：输出 `$USERPROFILE/...` 这类展示路径
 - `game_fs_init` / `game_fs_mount` / `game_fs_unmount`：由核心调用；feature 不要自己挂载
 - `game_fs_resolve_paths`：解析 exe / install / cwd，并写回 `CONFIG`；供 `load_config` 和查询命令使用
 - `game_fs_set_phase`：核心和 CLI 设置当前阶段
 - `game_fs_require_launchable`：启动前检查；已有 overlay 挂载或依赖缺失时拒绝启动
 - `game_fs_require_offline`：CLI 用；overlay 挂载期间拒绝离线操作
 - `game_fs_resolve_user_dirs`：延迟解析 prefix 中的用户目录

写路径的阶段规则（overlay 开启时）：
 - `load_config` / `init`：不允许写
 - `prepare_offline` / `cleanup_offline` / CLI `offline`：允许 `install`、`lower`、`upper`、`writable`、`all`，不允许 `runtime`
 - `prepare` / `pre_start` / `post_start` / `cleanup`：允许 `runtime`，不允许 `install`、`lower`、`upper`、`writable`、`all`
 - `prefix` / `userprofile` / `cache` / `data` / `state` / `temp` 不受 overlay 视图限制
 - overlay 关闭时所有作用域等价，全部允许

读路径不限制阶段，`fs_detect` 这类只读 `writable` 的 feature 不受影响。写操作必须走 `game_fs_write_path(s)` 或显式 `game_fs_assert_mutation`

路径校验只解析父目录，保留末级符号链接。末级链接指向根外时仍可删除/修复，中间级链接越界会被拒绝

`GAME_FS[overlay_mounted_by_us]` 用于区分本次挂载与外部已有挂载：外部挂载不会在 cleanup 中被自动卸载，启动也会要求先手动处理

## 游戏实现

游戏实现放在 `lib/games/<GAME_NAME>.sh` 下，文件名必须与 `GAME_NAME` 一致

**实现方式**：游戏文件只写游戏特有的逻辑，并通过**可选函数**与通用模块对接。这些函数用 `type -t` 检测，不存在时不会报错

游戏实现可以描述游戏本身，下面的函数都是可选实现。`GAME_NAME` 目前同时是游戏 ID、配置文件/脚本标识；显示名和路径名由游戏实现单独声明
 - `game_display_name`: 不接受参数，在 stdout 输出人类可读的游戏名（当前使用中文），用于 init 和 UI；未实现或为空时回退到 `GAME_NAME`
 - `game_path_name`: 不接受参数，在 stdout 输出路径友好的游戏名，只允许 `[A-Za-z0-9._-]+`；未实现或为空时回退到 `GAME_NAME`。只用于截图等用户可见目录，不用于内部数据目录
 - `game_install_dir`: 接受一个参数代表游戏本体 exe，即 `game.exe` 配置。在 stdout 输出游戏安装根目录 (通常是游戏文件夹本身)，这个根同时用于 overlay 的 lower 和 GameFS 的 install 视图。替代旧的 `overlay_auto_lower`；未实现时 install 视图留空，overlay 和依赖 install 的功能会报错，可以用 `game.install_dir` 显式指定根
 - `game_executable`: 接受 install 根，在 stdout 输出一个主 exe。只填 `game.install_dir` 时用它派生 `game.exe`；必须绝对路径、存在、位于 install 下。不同变体的 exe 名称由游戏实现自行判断（如原神国服/国际服）
 - `time_record_today_reset`: 不接受参数。在 stdout 输出游戏的日常刷新时间 (如 `04:00 Asia/Shanghai`)
 - `userdata_link`: 不接受参数，将游戏本体、prefix 内的用户数据 (如截图) 链接到一起。实现从 `GAME_FS` / `game_fs_write_path` 读取路径，路径均为 Linux 侧的路径。环境变量 `SCREENSHOTS` 为统一截图目录，常将已有截图移动到 `$SCREENSHOTS/<游戏目录>`，然后将游戏原截图目录软链接至此处。提供 `try_link_dir` 工具函数方便完成移动后创建链接这一重复操作。该函数在 `prepare` 阶段执行，此时 overlay 已挂载，因此能通过合并视图迁移 lower/upper 中已有的数据
 - `shader_cache_invalidate`: 不接受参数，删除游戏产出的着色器缓存。无需处理程序已负责的`__GL_SHADER_DISK_CACHE_PATH`、`DXVK_STATE_CACHE_PATH`、`VKD3D_SHADER_CACHE_PATH` 等，只负责游戏特定的部分。该命令离线执行，不挂载 overlay；游戏目录内的缓存应使用 `game_fs_write_paths all <相对路径>` 同时处理 lower 和 upper
 - `game_version_local`: 接受游戏可执行文件路径和两个 nameref 变量名，将本地版本和变体标识写入变量。本地版本只包含游戏本体已安装的版本。预下载内容不会安装到游戏本体，因此本函数不应返回预下载版本。当前没有本地预下载版本接口，`game_version_predownload_remote` 只报告远程预下载版本。变体标识允许为空。变体指游戏文件本身的分发变体 (如不同渠道的客户端)，而非区服，版本判断以本地文件对应的分发变体为准
 - `game_version_variant_human_readable`: 接受变体标识，在 stdout 输出适合显示的名称。仅当 `game_version_local` 返回了非空变体标识时才会被调用，未实现时直接显示变体标识本身
 - `game_version_remote`: 接受变体标识，在 stdout 输出远程版本
 - `game_version_predownload_remote`: 接受变体标识，在 stdout 输出预下载的远程版本，无预下载时输出空行。为可选实现，未实现的游戏在版本检查中不显示预下载状态

游戏实现中也可以直接注册生命周期钩子。游戏目录内的路径应通过 `game_fs_path` / `game_fs_write_path` 获取，不要直接读 `game.exe` 拼路径

## Launch Plan

Launch Plan 中有游戏运行时实际的 exe、工作目录、启动参数，管理 wrapper、bat 片段、`LD_PRELOAD`，决定是直接启动还是通过自定义 bat 脚本启动，组装 wine 侧的启动命令和总启动命令

`LP_GAME_EXE` / `LP_GAME_CWD` 由 `game_fs_apply_launch_plan` 从 GameFS 的 `runtime` 视图派生。overlay 不再作为独立 feature 修改 LaunchPlan

Game Handler 负责 wine 侧的组装，接受一个 nameref 参数，自行获取配置，并将 wine 侧的启动命令输出到给定的 nameref 数组内。默认的 Game Handler 会简单地获取和拼接 Launch Plan 内的游戏 exe 和启动参数。Feature 按需在 Launch Plan 注册 Game Handler。Game Handler 不能共存，同时只能有一个

> [!NOTE]
>
> 不像在 Linux 侧 Launch Plan 会提供 Runner Wrapper 这种允许共存的修改，在 Wine 侧只有一个独占的 Game Handler，这是有意为之，因为 Wine 侧的 Wrapper 通常直接与游戏接触，它们本来就互斥
