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
| `libs.sh` | 基础库聚合入口 |
| `modules.sh`、`common.sh` | 应用组装与主流程 |

- 调用其他模块的函数时，显式 `source` 并提供 `#shellcheck source=...` 指令。共享能力不反向加载其消费者，也不通过另一个 feature 获取隐含依赖
- 启动与配置查询共用 `hyps_load_modules` 的模块清单，feature 发现集中于此。基础模块和共享模块直接声明依赖，避免通过 `libs.sh` 加载整个应用
- 加载模块只定义函数、保存声明和注册钩子。文件修改、挂载、启动进程等操作放到明确调用的函数或生命周期钩子中
- 模块可能在函数内被 source，模块级数组使用 `declare -g`。重复加载不能清空状态或重复激活资源
- 每份状态只有一个所有者：配置原始值归配置模块，环境解析结果归环境模块，主 runner 和命令归 Launch Plan，路径视图归 GameFS，窗口监控进程和订阅归 xwin-watch

source 保证 API 已定义，钩子的 `before`、`after` 保证同一阶段的执行顺序，两者需要分别声明。例如窗口计时依赖 xwin-watch，并需要在它的配置钩子之前注册监控需求。新增模块先明确依赖、状态所有者和执行阶段，没有独立职责时留在已有模块中。

## 配置系统

### 声明与读取

声明放在所属模块或游戏实现中，加载时不计算默认值：

```bash
time_record_default_dir() {
    local -n result="$1"
    result="$DATA_DIR/time"
}

config_declare features.time_record.enabled bool --default true
config_declare features.time_record.dir path --default-fn time_record_default_dir
config_declare features.time_record.min_sec uint --default 60 \
    --when features.time_record.enabled

local dir origin
config_read features.time_record.dir dir
config_source features.time_record.dir origin
local -a args=()
config_read_array game.args args
```

类型：`string`、`bool`、`uint`、`int`、`path`、`array`、`args`、`string|array`、`enum`、`size`。`args` 接受数组或按空白分隔的字符串，通过 `config_read_array` 读取参数数组；`string|array` 接受标量或数组并保留结构；`enum` 用 `--choices a,b` 指定可选值，`size` 保留 `10G` 这类表达式。其他声明选项：

| 选项 | 契约 |
| --- | --- |
| `--default <值>` | 只补缺失值，按配置字面量解析，空字符串也可作为默认值 |
| `--default-fn <函数>` | 与 `--default` 互斥；接受值与结构的输出变量名，通过 nameref 写回，结构默认 `scalar`；返回 `3` 表示当前上下文无默认值，其他非零表示失败 |
| `--when <布尔键>` | 控制批量校验和有效值展示的适用范围，直接读取仍校验 |
| `--required` | 要求值存在且非空 |
| `--validate <函数>` | 接受规范化后的值，返回 `0` 表示通过 |
| `--description <说明>` | 供 `config schema` 展示 |

默认值函数可读取其他配置，循环依赖会报错，结果不缓存。默认值与校验函数不得修改文件、导出环境或注册钩子。相同声明可重复注册，不同内容的重复声明报错。

`CONFIG` / `CONFIG_SOURCE` / `CONFIG_KIND` 保存显式值、来源与结构，读取不写回默认值或规范化结果：

- `config_read <键> <输出变量> [结构输出变量]` 对缺失的可选值输出空字符串；`config_has <键>` 只判断显式值，不包含默认值
- `config_read_array` 每次替换整个输出数组；`config_is_true <键>` 读取布尔值并判断
- `config_set <键> <值> [来源] [scalar|array]` 覆盖显式值，默认按标量原样保存，数组需显式指定结构；`config_unset <键>` 删除值及元数据后恢复默认值
- `config_validate [前缀...]` 检查当前适用的已声明配置，多个前缀取并集，无匹配声明时报错

缺失、空字符串、`false`、空数组互不等价。标量仍允许转换，如 `"1"` 可用于整数配置；数组不能用于标量类型。引号包裹的内容始终是标量，不根据去掉引号后的内容再次推断数组。布尔拼写错误会报错，整数按十进制规范化，相对路径以项目根目录为基准。数组支持 `[a, b]` 与 `(a b)`，仅支持一维字符串和方括号末尾逗号，不执行 shell 表达式。数组在输入时完整校验，配置解析保留文件行号，格式错误或文件不可读时终止。

### 开放命名空间

```bash
config_declare_namespace plugin.limits uint
config_declare_namespace plugin.limits.special bool
config_declare plugin.limits.special.count uint --default 1
```

具体键完整覆盖命名空间约束，否则按点分隔匹配最长前缀：`plugin.limits.workers` 为 uint，`plugin.limits.special.enabled` 为 bool。命名空间不包含前缀自身，不继承父级条件或校验。

命名空间支持 `--choices`、`--when`、`--validate`、`--description`，不支持默认值或 `--required`，只约束实际出现的成员。`config_is_declared` 同时识别具体键和命名空间，`config_validate <前缀>` 接受尚无成员的已声明命名空间。`env.*` 的环境输出与 `nvapi.drs.*` 的聚合仍由所属模块负责。

### 加载与操作检查

字段优先级从低到高为 **schema 默认值 < 共用配置 < 选中的 runner 预设 < 游戏配置**。runner 名称优先取游戏配置，否则继承共用配置；显式空名称跳过预设。

`load_common_config` 读取 bootstrap 与共用配置、解析目录变量，目录仍允许环境覆盖。`load_game_config <游戏名>` 选择 runner 并合并配置。这两步不创建目录、不检查游戏或 runner 是否安装。

`config_require <键> [value|file|dir|executable]` 只检查本次操作的存在性要求。启动调用 `config_require_launch`，仅提供 `runner.protonpath` 时由它查找 Proton 并派生 `runner.exe`；离线命令可单独调用 `config_require_game_paths`，无需 runner。

启动先校验配置，再运行 `load_config` 钩子以激活功能。查询直接读取配置，不运行激活钩子；关闭时间记录不影响查询历史，缓存预览不创建目录。组合选项的互斥和操作条件由功能自己检查。CLI 用法见 [使用文档](README.md#查看和检查配置)，未声明的键在 `config check` 中警告。

### 环境与构建设置

```bash
#shellcheck source=../environment.sh
source "$SCRIPT_DIR/environment.sh"

env_declare MY_FEATURE bool --encode bool01 --default false
config_declare features.example.cache_size size --default 2G
env_bind features.example.cache_size MY_CACHE_BYTES --encode bytes
```

`env_declare NAME type` 声明 `env.NAME` 并绑定同名输出，接受配置声明和绑定选项。`env_bind <键> <变量名>` 支持 `--encode`、`--when`、`--check file|dir`、`--policy inherit|replace`，绑定与配置自身的条件都必须满足。名称须为合法 shell 变量名；相同绑定可重复注册，不同选项报错。

内置编码器为 `string`、`bool01`、`bytes`、`comma`、`colon`、`semicolon`，后三者要求数组；对应的 `*_list` 还接受已编码字符串，按结构选择编码方式。自定义 `env_encode_<名称>` 接受规范化值、输出变量名、来源键、结构，通过 nameref 写回字符串，只能计算输出。`wine.dll_overrides`、`mangohud.config` 是数组，`env.WINEDLLOVERRIDES` 等使用 `string|array`。

候选优先级为 **replace 策略 > 已导出的输入环境（含空值）> 显式 env.NAME > 显式语义配置 > 默认值**。仅对最高优先级候选编码和检查路径，同级不同值报错，配置类型仍独立校验。shader cache 目录用 `replace`，使准备、运行与清理使用同一路径，其余绑定默认遵守输入环境优先。

`environment_capture` 在配置与钩子之前保存输入快照；`environment_resolve` 只计算结果，`environment_check` 在准备阶段前检查最终路径。`environment_read <变量> <输出变量>` 对缺失项返回 `1`、显式空值返回 `0`，`environment_source` 查询来源。

`environment_command_get <输出数组> <程序> [参数...]` 要求解析成功，检查路径后组装 `env -- NAME=value ... 程序 参数...`，调用方直接执行，不向当前 shell 导出：

```bash
local -a command=()
environment_command_get command "$runner_exe" "${runner_args[@]}" || return $?
"${command[@]}" &
local pid="$!"
```

异步执行不要再包后台 shell 函数或子 shell，否则 `$!` 可能指向包装进程。是否携带游戏环境由调用方按操作决定：

| 命令 | 环境作用域 |
| --- | --- |
| 游戏 wrapper → runner → 游戏 | 解析后的游戏环境，附加 Launch Plan 的 `LD_PRELOAD` |
| 直接模式的准备批处理 runner | 同一份游戏环境，不附加游戏 preload；失败时停止启动并清理 |
| 脚本模式的 prepare / before / 游戏 / after | 同一次 runner 调用，共享环境与 preload |
| 编译、补丁、挂载、下载、窗口监控等宿主工具 | 原始宿主环境 |
| 指定 Wine prefix 的控制命令 | 调用方显式传入所需变量，如 `WINEPREFIX` |

作用域覆盖 runner 及其后代，不能缩到单个游戏 exe。Hyps 已继承的输入变量仍属于宿主环境。

动态目标可用 `environment_register_provider <函数>`，解析时通过 `environment_offer` 提供与 `env_bind` 相同的候选；跨变量规则用 `environment_register_finalizer <函数>`。两者也必须无环境导出或激活副作用。

runner 将 `game.prefix` 绑定到 `runner.prefix_var`，`GAMEID` / `UMU_ID` 按最终优先级统一，同级冲突或最终为空时报错。预设的兜底 ID 应写 `game.umu_id = "umu-default"`，以供游戏覆盖；`env.UMU_ID` 表达优先级更高的环境覆盖。`LD_PRELOAD` 由 Launch Plan 独占管理。

构建配置由 `config/build.sh` 独立处理，在 `load_config` 通过 `build_read_args` 按以下优先级生成参数数组：

| 内部结果 | 环境覆盖，从高到低 | 配置与默认值 |
| --- | --- | --- |
| `BUILD_CC` | `HYPS_CC` > `CC` | `compile.CC`，默认 `gcc` |
| `BUILD_CFLAGS` | `HYPS_CFLAGS` > `CFLAGS` | `compile.CFLAGS`，默认空数组 |
| `BUILD_MINGW_CC` | `HYPS_MINGW_CC` | `compile.mingw.CC`，默认 `x86_64-w64-mingw32-gcc` |
| `BUILD_MINGW_CFLAGS` | `HYPS_MINGW_CFLAGS` | `compile.mingw.CFLAGS`，默认空数组 |

四个 `compile.*` 配置项和选中的环境字符串都按 `args` 类型解析，例如 `compile.CC = "ccache gcc"` 或 `HYPS_CC='["ccache", "gcc"]'`。`BUILD_*` 是每次加载重新生成的内部数组，不能作为输入。

显式空值覆盖低优先级来源；选中的来源格式错误时直接报错，不回退到低优先级来源。引号、反斜杠和 shell 表达式不求值，含空格的参数应使用数组，如 `HYPS_CFLAGS='["-DNAME=hello world", "-O2"]'`。空编译器在构建时报错，不回退到默认编译器。

MinGW 构建只接受 `HYPS_MINGW_CC`、`HYPS_MINGW_CFLAGS` 环境覆盖，不继承宿主的 `CC`、`CFLAGS`。

ToolSpec 的编译器结果也使用数组，执行、缓存指纹和编译数据库均保留完整编译器命令及参数。`development/gen-compile-db.sh` 使用相同的环境覆盖优先级和解析规则，不读取配置文件，未设置的 flags 默认使用 `-Wall -Wextra`。

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

游戏实现放在 `lib/games/<GAME_NAME>.sh` 下，文件名必须与 `GAME_NAME` 一致

单次启动只加载一个游戏实现。批量查询从未加载具体游戏实现的公共环境出发，每个游戏在独立子 shell 中完成加载、查询和结果整理，父级只接收输出和退出状态，不通过 `unset` 切换游戏

加载游戏文件只定义函数、初始化内存状态和注册钩子。启动外部程序、挂载和文件修改放在明确调用的函数或生命周期钩子中，子 shell 不会撤销这些操作

游戏文件只写游戏特有的声明和逻辑，固定属性用变量，需要计算或执行行为的接口用函数。`GAME_NAME` 同时是游戏 ID、配置文件/脚本标识，显示名和路径名由游戏实现单独声明

下面的变量都是可选声明：

```bash
GAME_DISPLAY_NAME="原神"
GAME_PATH_NAME="YuanShen"
GAME_DAILY_RESET="04:00 Asia/Shanghai"
```

- `GAME_DISPLAY_NAME`：人类可读的游戏名（当前使用中文），用于 init 和 UI，未设置或为空时回退到 `GAME_NAME`
- `GAME_PATH_NAME`：路径友好的游戏名，只允许 `[A-Za-z0-9._-]+`，且不能是 `.` 或 `..`，未设置或为空时回退到 `GAME_NAME`。只用于截图等用户可见目录，不用于内部数据目录
- `GAME_DAILY_RESET`：日常刷新时间，未设置时使用 `04:00 Asia/Shanghai`，空值或假值表示不参与日常状态判断。用户配置 `features.time_record.today.reset` 优先于游戏声明

下面的函数都是可选实现，通过 `type -t` 检测，不存在时不会报错：

 - `game_install_dir`: 接受一个参数代表游戏本体 exe，即 `game.exe` 配置。在 stdout 输出游戏安装根目录 (通常是游戏文件夹本身)，这个根同时用于 overlay 的 lower 和 GameFS 的 install 视图。替代旧的 `overlay_auto_lower`；未实现时 install 视图留空，overlay 和依赖 install 的功能会报错，可以用 `game.install_dir` 显式指定根
 - `game_executable`: 接受 install 根，在 stdout 输出一个主 exe。只填 `game.install_dir` 时用它派生 `game.exe`；必须绝对路径、存在、位于 install 下。不同变体的 exe 名称由游戏实现自行判断（如原神国服/国际服）
 - `game_paths`: 不接受参数，声明游戏路径角色；使用 `path_plan_declare <role> <scope> <rel> [label]` 和 `path_plan_note <role> [text]`，不直接执行任何操作。角色目前有 `userdata:screenshot` 和 `shader-cache`
 - `game_version_local`: 接受游戏可执行文件路径和三个 nameref 变量名，写入本地版本、变体标识和远程查询上下文。本地版本只含游戏本体已安装的版本，不返回预下载版本。变体是游戏文件本身的分发变体 (如不同渠道的客户端)，而非区服，允许为空。上下文是不透明字符串，原样交给 `game_version_remote`
 - `game_version_variant_human_readable`: 接受变体标识，在 stdout 输出适合显示的名称。仅当 `game_version_local` 返回了非空变体标识时才会被调用，未实现时直接显示变体标识本身
 - `game_version_remote`: 接受变体标识、上下文 (即 `game_version_local` 写入的内容，必填，可为空字符串) 和两个 nameref 变量名，将远程版本与预下载版本写入变量。无预下载时预下载写为空字符串，预下载版本可能高于远程版本

游戏目录内的路径应通过 `game_fs_path` / `game_fs_write_path` 获取，不要直接读 `game.exe` 拼路径

## Launch Plan

Launch Plan 中有游戏运行时实际的 exe、工作目录、启动参数，管理 wrapper、bat 片段、`LD_PRELOAD`，决定是直接启动还是通过自定义 bat 脚本启动，组装 wine 侧的启动命令和总启动命令

`LP_GAME_EXE` / `LP_GAME_CWD` 由 `game_fs_apply_launch_plan` 从 GameFS 的 `runtime` 视图派生。overlay 不再作为独立 feature 修改 LaunchPlan

Game Handler 负责 wine 侧的组装，接受一个 nameref 参数，自行获取配置，并将 wine 侧的启动命令输出到给定的 nameref 数组内。默认的 Game Handler 会简单地获取和拼接 Launch Plan 内的游戏 exe 和启动参数。Feature 按需在 Launch Plan 注册 Game Handler。Game Handler 不能共存，同时只能有一个

> [!NOTE]
>
> Wine 侧的 Game Handler 同时只能有一个，与 Linux 侧可共存的 Runner Wrapper 不同。Wine 侧 Wrapper 直接与游戏接触，本来就互斥

## 工具开发

`development/gen-compile-db.sh` 为 clangd 生成编译数据库；`gryph-surrogate` 需要 mingw-w64 交叉编译。修改 xwin-watch 的 `protocols/` XML 后运行 `development/gen-wayland-protocols.sh`，生成的 `generated/` 文件也需要提交。
