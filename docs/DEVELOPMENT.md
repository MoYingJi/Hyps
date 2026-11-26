# 开发指南

## 模块边界

| 位置 | 职责与边界 |
| --- | --- |
| `core/`、`utils/` | 基础机制与工具，不加载 feature 或游戏实现 |
| `config/`、`environment.sh` | 配置声明、读取和环境绑定，不发现功能模块 |
| `launch/` | 启动计划、命令和游戏文件系统，不依赖具体游戏或外部产品 |
| `shared/` | 可选的共享运行能力，统一管理资源与生命周期，如 xwin-watch |
| `integrations/` | 外部产品的数据格式、API 和协议适配，如 HoYoPlay，不接管启动流程 |
| `features/` | 可组合的具体功能，消费启动能力或共享能力 |
| `games/`、`commands/` | 游戏行为与命令用例 |
| `bootstrap.sh` | 入口路径、运行用户检查与工作目录 |
| `libs.sh` | 基础库聚合入口 |
| `modules.sh`、`common.sh` | 应用组装与主流程 |

`scripts/<游戏>.sh` 将游戏名交给 `_Hyps run`，由 `commands/run.sh` 加载 `common.sh` 并执行 `hyps_main`。`game list` 和 `init` 通过读取入口脚本里的 `GAME_NAME` 识别游戏。

- 调用其他模块的函数时，显式 `source` 并提供 `#shellcheck source=...` 指令。共享能力不反向加载其消费者，也不通过另一个 feature 获取隐含依赖
- 启动与配置查询共用 `hyps_load_modules` 的模块清单，feature 发现集中于此。基础模块和共享模块直接声明依赖，避免通过 `libs.sh` 加载整个应用
- 加载模块只定义函数、保存声明和注册钩子。文件修改、挂载、启动进程等操作放到明确调用的函数或生命周期钩子中
- 模块可能在函数内被 source，模块级数组使用 `declare -g`。重复加载不能清空状态或重复激活资源
- 每份状态只有一个所有者：配置原始值归配置模块，环境解析结果归环境模块，主 runner 和命令归 Launch Plan，路径视图归 GameFS，窗口监控进程和订阅归 xwin-watch

source 保证 API 已定义，钩子的 `before`、`after` 保证同一阶段的执行顺序，两者需要分别声明。例如窗口计时依赖 xwin-watch，并需要在它的配置钩子之前注册监控需求。新增模块先明确依赖、状态所有者和执行阶段，没有独立职责时留在已有模块中。

配置声明、解析、环境变量和构建配置见[配置系统](CONFIGURATION.md)。

## 生命周期

| 阶段 | 约束与失败处理 |
| --- | --- |
| `load_config` | 检查功能条件、注册运行钩子、构建启动计划，无文件系统副作用；失败退出 |
| `prepare_offline` | runtime 之外的准备，如写 lower/upper、游戏补丁、恢复残留；失败进入 cleanup |
| `prepare` | runtime 内准备，overlay 开启时已挂载；失败进入 cleanup |
| `pre_start` | 启动前最后检查；失败进入 cleanup |
| `post_start` | 启动后；失败仍继续 |
| `cleanup` | 卸载前收尾，返回前必须停止对 runtime 的访问；失败仍继续 |
| `cleanup_offline` | 后端停止访问底层目录后恢复或删除 upper 补丁；条件未满足时跳过并保留恢复标记，钩子失败仍继续 |

通过 `register_hook <阶段> <函数> [优先级] [依赖关系]` 注册。核心在配置钩子后初始化 GameFS 和解析、检查环境，在 `prepare_offline` 与 `prepare` 之间挂载，在 `cleanup` 与 `cleanup_offline` 之间等待 runner 并卸载。完整顺序见 `common.sh`。

核心在每阶段前设置 GameFS phase。`defer_mkdir` 在 `prepare` 创建目录；必须在挂载前创建的目录应在 `prepare_offline` 中通过 `game_fs_write_path writable` 获取写路径。

需要 runtime 的外部程序由其所有者在 `cleanup` 返回前停止并等待，包括子进程、后台任务、文件描述符和工作目录引用。只发退出信号或只等主 PID 不算完成，也不能交给 `cleanup_offline`。主 runner 由 Launch Plan 终止并等待，不代表所有 Wine 后代已结束；feature 管理的程序由 feature 清理。此约定同样适用于部分初始化和启动失败，宿主无关进程不在清理范围内。

核心在全部 `cleanup` 返回后判断是否存在 `cleanup_offline` 钩子：

- 无离线钩子：优先普通卸载，失败时允许懒卸载，不主动终止服务于旧引用的 FUSE 服务
- 有离线钩子：普通卸载并等待服务退出；卸载失败时先同步写入，再仅终止本次启动的 FUSE 服务、等待退出并移除失效挂载。任一步失败都不执行离线钩子，旧引用的访问可能失败
- 懒卸载不能证明 upper 空闲。`$STATE_DIR/overlay/` 按 upper 记录 PID、进程启动时间和系统启动标识；旧服务仍在运行时拒绝重启或离线操作，不通过记录终止上次会话的进程

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

自定义 `overlay.lower` 可以是 install 的祖先；`lower` / `runtime` / `writable` / `upper` / `all` 都会带上 install 相对 lower 的偏移

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
 - `game_fs_write_path`：解析路径并做写阶段校验
 - `game_fs_assert_mutation <scope>`：外部工具或复杂操作写前显式校验
 - `game_fs_root <scope>`：输出某个作用域的根
 - `game_fs_init` / `game_fs_mount` / `game_fs_unmount`：由核心调用；feature 不要自己挂载
 - `game_fs_resolve_paths`：解析 exe / install / cwd，并写回 `CONFIG`；供 `load_config` 和查询命令使用
 - `game_fs_set_phase`：核心和 CLI 设置当前阶段
 - `game_fs_require_launchable`：启动前检查；已有 overlay 挂载、旧后端尚未释放或依赖缺失时拒绝启动
 - `game_fs_require_offline`：CLI 用；overlay 挂载期间或旧后端尚未释放时拒绝离线操作
 - `game_fs_resolve_user_dirs`：延迟解析 prefix 中的用户目录

写路径的阶段规则（overlay 开启时）：
 - `load_config` / `init`：不允许写
 - `prepare_offline` / `cleanup_offline` / CLI `offline`：允许 `install`、`lower`、`upper`、`writable`、`all`，不允许 `runtime`
 - `prepare` / `pre_start` / `post_start` / `cleanup`：允许 `runtime`，不允许 `install`、`lower`、`upper`、`writable`、`all`
 - `prefix` / `userprofile` / `cache` / `data` / `state` / `temp` 不受 overlay 视图限制
 - overlay 关闭时所有作用域等价，全部允许

读路径不限制阶段，`fs_detect` 这类只读 `writable` 的 feature 不受影响。路径解析不保证对应视图当前可用；外部程序即使只读 runtime，也必须遵守上面的收尾约定。写操作必须走 `game_fs_write_path(s)` 或显式 `game_fs_assert_mutation`

游戏目录路径校验只解析父目录，保留末级符号链接；末级链接指向根外时仍可删除/修复，中间级链接越界会被拒绝。`userprofile` / `cache` 等前缀目录允许符号链接，只做词法越界检查

`GAME_FS[overlay_mounted_by_us]` 用于区分本次挂载与外部已有挂载：外部挂载不会在 cleanup 中被自动卸载，启动也会要求先手动处理

## 路径声明

游戏实现用可选的 `game_paths` 声明路径角色，Hyps 负责收集、解析和渲染，具体功能负责执行：

```bash
game_paths() {
    path_plan_declare userdata:screenshot userprofile "Pictures/ENDFIELD"
    path_plan_declare shader-cache all "Client/Saved/PSO"
    path_plan_note shader-cache "清理后可能需要手动重新触发编译"
}
```

- `userdata:screenshot`：截图目录。第四个参数是 `$SCREENSHOTS` 下的子目录，默认取 `GAME_PATH_NAME`，未设置或为空时回退到 `GAME_NAME`
- `shader-cache`：着色器缓存路径，可以是文件或目录；`all` 在 overlay 下会展开 lower + upper
- `path_plan_note <role> [text]`：只输出提示，不产生动作；空 text 表示声明了该 role，但没有路径和提示
- `path_plan_collect <role>` 返回 0 表示已声明，3 表示游戏没有声明该 role，4 表示游戏没有实现 `game_paths`
- `path_plan_paths <role>` 输出解析后的路径记录，截图和缓存功能各自消费
- `path_plan_render <role>` 只读展示

## 游戏实现

游戏实现放在 `lib/games/<GAME_NAME>.sh` 下，文件名必须与 `GAME_NAME` 一致。变量、接口语义和生命周期约束都写在 `lib/games/_game.example.sh` 的注释里，复制它作为骨架即可（该文件本身不会被加载）

## Launch Plan

Launch Plan 中有游戏运行时实际的 exe、工作目录、启动参数，管理 wrapper、bat 片段、`LD_PRELOAD`，决定是直接启动还是通过自定义 bat 脚本启动，组装 wine 侧的启动命令和总启动命令

`LP_GAME_EXE` / `LP_GAME_CWD` 由 `game_fs_apply_launch_plan` 从 GameFS 的 `runtime` 视图派生。overlay 不再作为独立 feature 修改 LaunchPlan

Game Handler 负责 wine 侧的组装，接受一个 nameref 参数，自行获取配置，并将 wine 侧的启动命令输出到给定的 nameref 数组内。默认的 Game Handler 会简单地获取和拼接 Launch Plan 内的游戏 exe 和启动参数。Feature 按需在 Launch Plan 注册 Game Handler。Game Handler 不能共存，同时只能有一个

> [!NOTE]
>
> Wine 侧的 Game Handler 同时只能有一个，与 Linux 侧可共存的 Runner Wrapper 不同。Wine 侧 Wrapper 直接与游戏接触，本来就互斥

## 工具开发

`development/gen-compile-db.sh` 为 clangd 生成编译数据库；`gryph-surrogate` 需要 mingw-w64 交叉编译。修改 xwin-watch 的 `protocols/` XML 后运行 `development/gen-wayland-protocols.sh`，生成的 `generated/` 文件也需要提交。
