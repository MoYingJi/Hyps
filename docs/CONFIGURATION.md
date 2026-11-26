# 配置系统

## 声明与读取

声明放在所属模块或游戏实现中，加载时不计算默认值：

```bash
config_declare features.time_record.enabled bool --default true
config_declare features.time_record.dir path --in global --default '"${path.data}/time"'
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
| `--default <值>` | 只补缺失值，使用配置文件的字面量和模板语法，空字符串也可作为默认值 |
| `--default-fn <函数>` | 与 `--default` 互斥；接受值与结构的输出变量名，通过 nameref 写回，结构默认 `scalar`；返回 `3` 表示当前上下文无默认值，其他非零表示失败 |
| `--in <层级列表>` | 允许写入的配置层，逗号分隔，默认 `global,game-instance` |
| `--when <布尔键>` | 控制批量校验和有效值展示的适用范围，直接读取仍校验 |
| `--required` | 要求值存在且非空 |
| `--validate <函数>` | 接受规范化后的值，返回 `0` 表示通过 |
| `--description <说明>` | 供 `config schema` 展示 |

默认值函数可读取其他配置，循环依赖会报错，结果不缓存。默认值与校验函数不得修改文件、导出环境或注册钩子。相同声明可重复注册，不同内容的重复声明报错。

`CONFIG` / `CONFIG_SOURCE` / `CONFIG_KIND` 保存显式值、来源与结构。合并时保留文件字面量，读取时解码转义、展开引用，再规范化类型和检查约束。数组逐元素展开。只读的 `${game.name}` 来自当前游戏配置的文件名（去掉 `.conf`）。无游戏上下文时，依赖它的值按未设置处理。读取不写回默认值或规范化结果：

- `config_read <键> <输出变量> [结构输出变量]` 对缺失的可选值输出空字符串；`config_has <键>` 只判断显式值，不包含默认值
- `config_read_array` 每次替换整个输出数组；`config_is_true <键>` 读取布尔值并判断
- `config_set <键> <值> [来源] [scalar|array]` 覆盖显式值，默认按标量原样保存，数组需显式指定结构。值中的模板字符按字面保留。`config_unset <键>` 删除值及元数据后恢复默认值
- `config_validate [前缀...]` 检查当前适用的已声明配置，多个前缀取并集，无匹配声明时报错

缺失、空字符串、`false`、空数组互不等价。标量仍允许转换，如 `"1"` 可用于整数配置；数组不能用于标量类型。引号包裹的内容始终是标量，不根据去掉引号后的内容再次推断数组。布尔拼写错误会报错，整数按十进制规范化，相对路径以项目根目录为基准。数组支持 `[a, b]` 与 `(a b)`，仅支持一维字符串和方括号末尾逗号，不执行 shell 表达式。数组在输入时完整校验，配置解析保留文件行号，格式错误或文件不可读时终止。

`path` 类型在规范化时把开头的 `~` 和 `~/` 展开为 `$HOME`，展开发生在模板引用之后、`realpath` 之前，因此引号不影响结果。`~user` 形式无法可靠解析，直接报错；`HOME` 未设置时报错；其他位置的 `~` 属于路径本身，保持字面。`string` 类型不展开，`runner.protonpath`、`mangohud.exe` 这类需要接受程序名或 Proton 名称的键仍是 `string`。

## 开放命名空间

```bash
config_declare_namespace plugin.limits uint
config_declare_namespace plugin.limits.special bool
config_declare plugin.limits.special.count uint --default 1
```

具体键完整覆盖命名空间约束，否则按点分隔匹配最长前缀：`plugin.limits.workers` 为 uint，`plugin.limits.special.enabled` 为 bool。命名空间不包含前缀自身，不继承父级条件或校验。

命名空间支持 `--choices`、`--when`、`--validate`、`--description` 和 `--in`，只约束实际出现的成员。`config_is_declared` 同时识别具体键和命名空间，`config_validate <前缀>` 接受尚无成员的已声明命名空间。`env.*` 的环境输出与 `nvapi.drs.*` 的聚合仍由所属模块负责。

## 加载与操作检查

配置文件按下面的优先级从低到高合并，schema 默认值只补缺失值。

| 层级 | 文件 |
| --- | --- |
| `bootstrap` | `$PROJECT_ROOT/config.conf` |
| `global` | `$CONFIG_DIR/config.conf` |
| `runner` | `$CONFIG_DIR/runners/<名称>.conf` |
| `game-instance` | `$CONFIG_DIR/games/<游戏名>.conf` |

`load_global_config` 先读引导配置确定 `CONFIG_DIR`，再读全局配置并解析目录变量。目录仍允许环境覆盖。`load_game_config <游戏名>` 优先从游戏实例取 `runner.name`，否则继承全局值。显式空名称跳过预设。加载过程只读取配置，安装检查由具体命令发起。

普通模板读取选定 runner 和游戏配置合并后的有效值。全局专用键及其引用链使用全局快照，引导专用键只能读取引导值。`runner.name` 在读取预设前解析并保留原来源。模板语法与转义见[使用指南](USAGE.md#模板与转义)。

位置检查使用每层原始键和行号，覆盖或 `--when` 条件不会隐藏放错层的键。游戏实现注册新声明之后，加载器会复查引导和全局配置。`--in` 约束文件来源，默认值、环境覆盖和 `config_set` 的程序派生值按各自规则处理。

`config_require <键> [value|file|dir|executable]` 只检查本次操作的存在性要求。启动调用 `config_require_launch`，仅提供 `runner.protonpath` 时由它查找 Proton 并派生 `runner.exe`；离线命令可单独调用 `config_require_game_paths`，无需 runner。

配置查询和启动共用游戏实现的配置声明。加载时在内存中注册钩子，启动在配置校验后运行 `load_config` 钩子以激活功能。批量查询把每个游戏的配置声明、函数和钩子表隔离在独立子 shell 中。关闭时间记录不影响查询历史，缓存预览不创建目录。组合选项的互斥和操作条件由功能自己检查。CLI 用法见 [使用指南](USAGE.md#查看和检查配置)，未声明的键在 `config check` 中警告。

## 环境与构建设置

```bash
#shellcheck source=../environment.sh
source "$SCRIPT_DIR/environment.sh"

env_declare MY_FEATURE bool --encode bool01 --default false
config_declare features.example.cache_size size --default 2G
env_bind features.example.cache_size MY_CACHE_BYTES --encode bytes
```

`env_declare NAME type` 声明 `env.NAME` 并绑定同名输出，接受配置声明和绑定选项。`env.*` 默认允许写在 `global,runner,game-instance`。`env_bind <键> <变量名>` 支持 `--encode`、`--when`、`--check file|dir`、`--policy inherit|replace`，绑定与配置自身的条件都必须满足。名称须为合法 shell 变量名；相同绑定可重复注册，不同选项报错。

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

显式空值覆盖低优先级来源，选中的来源格式错误时直接报错。环境来源的标量按空白分隔，数组使用配置的引号和转义规则，其中的模板按字面保留。含空格的参数应使用数组，如 `HYPS_CFLAGS='["-DNAME=hello world", "-O2"]'`。空编译器在构建时报错。

MinGW 构建只接受 `HYPS_MINGW_CC`、`HYPS_MINGW_CFLAGS` 环境覆盖，不继承宿主的 `CC`、`CFLAGS`。

ToolSpec 的编译器结果也使用数组，执行、缓存指纹和编译数据库均保留完整编译器命令及参数。`development/gen-compile-db.sh` 使用相同的环境覆盖优先级和解析规则，不读取配置文件，未设置的 flags 默认使用 `-Wall -Wextra`。
