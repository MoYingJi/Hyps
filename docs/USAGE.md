# 使用指南

## 使用方法

1. 克隆本项目

2. 你可以选择在本项目的 `config.conf` 中修改配置文件的路径，默认路径就是本项目的 `./config` 文件夹，所以你也可以选择不改

3. 将配置目录中的 `config.example.conf` 复制为同目录下的 `config.conf`。在这里设置全局选项和游戏默认值，例如 `path.data` 或默认 `runner.name`

4. 到配置文件夹的 `games.examples` 目录下，选个你想玩的游戏，复制一个 `<name>.example.conf` 文件到配置文件夹的 `games` 下，重命名为 `<name>.conf`，并修改里面的配置，比如 `runner.name` 和一些路径

5. 运行 `./scripts/_Hyps run <游戏名>` 启动游戏，例如 `games/endfield.conf` 对应 `./scripts/_Hyps run endfield`。也可以运行 `scripts` 文件夹下对应游戏的脚本

游戏名须以 ASCII 小写字母开头，后续可用 ASCII 小写字母、数字和连字符（`^[a-z][a-z0-9-]*$`）。该规则也适用于自定义游戏配置。

或者直接运行 `./init.sh` 自动完成第 3～4 步（见下文「初始化」）

### 初始化

`./init.sh`（等价于 `./scripts/_Hyps init`）会检测基础环境并生成配置，省去手动复制示例配置的步骤：

```bash
./init.sh                  # 检测环境 + 初始化基础配置，并交互式选择要玩的游戏
./init.sh endfield         # 同上，并复制 endfield 的示例配置
./init.sh --check          # 只检测，不写入任何文件；必需项缺失时返回非 0
./init.sh --list           # 查看各游戏的示例配置与当前配置状态
./init.sh --force endfield # 覆盖已有配置前先备份为 .bak.<时间戳>
./init.sh --no-game        # 只初始化基础配置
```

初始化会创建配置目录，从 `config.example.conf` 复制全局配置，从 `games.examples` 复制所选的游戏配置，并把 `runners/*.conf` 同步到自定义配置目录。复制后按提示修改游戏配置里的 `game.exe`（或 `game.install_dir`）与 `runner.name`，即可启动游戏。

**旧配置迁移**　将 `games/_common.conf` 的设置合并到配置目录下的 `config.conf`，再移走旧文件。两份文件都有同一个键时，游戏默认值通常以旧 `_common.conf` 为准，`path.data`、`path.cache` 等目录以原先实际使用的路径为准。项目根的 `config.conf` 用于引导，请把其他设置移到配置目录下的 `config.conf`。`features.time_record.dir` 现在只接受全局配置，如果以前按游戏指定了目录，请把旧记录归入选定的全局历史根目录。用 `config schema` 可以查到每个键允许放在哪一层。

### 查看游戏信息

```bash
./scripts/_Hyps game list                    # 已配置的游戏：显示名、状态、安装目录
./scripts/_Hyps game list --all              # 包含未配置的游戏
./scripts/_Hyps game list --size --version   # 额外显示安装占用与本地版本
./scripts/_Hyps game info arknights          # 单个游戏：路径、占用、版本、游玩记录
./scripts/_Hyps game info arknights --remote # 额外查询最新版本与预下载
```

`game list` 只显示一眼能判断的信息，占用和版本默认不查。`game info` 展开完整路径、占用和游玩记录，状态异常时给出原因；占用会遍历安装目录，慢时可用 `--no-size` 跳过。列表只区分“就绪 / 配置错误 / 未配置”，游戏实现整体可选。

### 查看和检查配置

```bash
./scripts/_Hyps config schema yuanshen                 # 查看该游戏及通用模块的配置声明
./scripts/_Hyps config show endfield                   # 查看当前启用项的有效值及来源
./scripts/_Hyps config show --prefix features.time_record
./scripts/_Hyps config check endfield                  # 按声明检查放置位置、类型和约束
```

省略游戏名时加载引导和全局配置。`schema` 可以在初始化配置之前使用，`show` 和 `check` 只解析配置，游戏和 runner 的安装检查在启动时执行。位置错误会指出原文件、行号和允许的层级。涉及多个选项的组合约束仍会由对应功能检查。

默认值只补缺失的配置，显式空值、`false` 和空数组不会被默认值覆盖。布尔值拼写错误、未闭合数组等会报错，路径中的相对路径以项目根目录为基准，`path` 类型可用 `~` 或 `~/` 表示家目录。

### 模板与转义

双引号内的 `${配置键}` 引用可用的标量配置，例如 `${game.install_dir}`。同一个文件里可以引用写在后面的键。`${game.name}` 对应 `run` 命令的参数，也就是游戏配置文件名去掉 `.conf`。`${env.NAME}` 读取配置中的 runner 环境值。含模板的启动参数用数组写，每个元素展开后仍是一个参数。

**全局专用键**从全局配置读取引用，**引导专用键**只能引用引导值。`runner.name` 在预设加载前解析，可引用当时已读到的全局和游戏配置。未知、缺失或循环引用会报错。

```ini
# 全局 config.conf
features.time_record.dir = "${path.data}/play-history"

# games/endfield.conf
game.install_dir = "/games/Endfield"
game.exe = "${game.install_dir}/Endfield.exe"
game.prefix = "${path.data}/wine/${game.name}"
game.args = ["--log", "${path.state}/${game.name}.log"]
```

双引号内支持 `\\`、`\"`、`\n`、`\t`、`\r`、`\b`、`\f`、`\$`，未知转义和未闭合的引号会报出原文件和行号。`"\${path.data}"` 得到字面量 `${path.data}`。单引号按原样保留，旧配置中的 Windows 路径和注册表键可改用单引号，例如 `'C:\Games\Test\'`。无引号的值按字面读取，行尾的 `#` 用于注释。

`wine.dll_overrides`、`mangohud.config` 现在要求数组，例如 `wine.dll_overrides = ["winemenubuilder.exe=d"]`。`env.WINEDLLOVERRIDES`、`env.MANGOHUD_CONFIG` 仍可使用已编码的字符串。

环境变量通常按「启动 Hyps 时已导出的值 > 显式 `env.NAME` > 语义配置 > 默认值」选择，着色器缓存重定向开启后会接管缓存目录。配置生成的环境只传给游戏 runner 及其子进程；需要同一 Wine 环境的准备批处理也会继承，宿主工具继续使用原始环境。

配置声明的开发接口见 [配置系统](CONFIGURATION.md)。

## 功能

### Overlay

Overlay 使用 FUSE OverlayFS 为游戏目录提供一个可写视图：游戏安装目录作为只读的 `lower` 层，游戏运行时对目录的修改写入 `upper` 层，不会直接改动安装目录。`upper` 会保留在多次运行之间，因此这不是每次启动都会重置的临时环境

在对应游戏的配置文件中启用即可：

```ini
overlay.enabled = true
#overlay.lower = "/path/to/game"  # 可选，默认就是游戏安装目录，自定义时必须包含 game.exe
```

挂载需要四个目录：`lower` 是原始游戏目录，`upper` 保存运行时产生的修改，`work` 是 OverlayFS 使用的工作目录，`mount` 是提供给游戏使用的合并视图。通常只需设置 `overlay.enabled`；`overlay.lower` 默认使用游戏安装目录，其余目录会默认创建在 `overlay.dir/<游戏名>/` 下：

```text
~/.local/share/hypsc/overlays/<游戏名>/
├── mount/
├── upper/
└── work/
```

`overlay.dir` 默认是 `${path.data}/overlays`，常见路径是 `~/.local/share/hypsc/overlays`。如需自定义位置，可设置 `overlay.dir`，也可以分别用 `overlay.mount`、`overlay.upper` 和 `overlay.work` 指定目录。自定义的 `upper` 和 `work` 应放在同一文件系统中

`overlay.lower` 未设置时默认使用游戏安装目录。只有需要把 lower 指向安装目录之外的路径时才需要显式设置；自定义 lower 必须包含配置中的 `game.exe`

overlay 需要知道游戏安装根。内置游戏会自动识别；其他游戏可以设置 `game.install_dir`。`game.exe` 和 `game.install_dir` 至少填一个

启用 overlay 需要安装 `fuse-overlayfs`，并确保 `/dev/fuse` 可用

如果上次异常退出留下了仍在挂载的 `overlay.mount`，启动会拒绝复用并提示先手动卸载，避免在挂载期间直接写 upper

### 着色器缓存

设置 `cache.shader.enabled = true` 即可。会增加游戏流畅度。若驱动更新 / 游戏更新，而游戏未重新预编译着色器，可以先用 `_Hyps shader-cache list <GAME_NAME>` 查看游戏声明的缓存，再用 `_Hyps shader-cache invalidate <GAME_NAME>` 删除。`[program]` 是 Hyps 通过环境变量提供的 program cache，不是游戏实现的声明。启用 overlay 时，游戏目录内的缓存会同时清理 lower 和 upper；如果 overlay 正在挂载，命令会拒绝执行，需要先关闭游戏并卸载

### 时间记录

默认开启时间记录

```bash
_Hyps time list  # 列出所有游戏的 启动次数、总游戏时长、最后一次启动时间
_Hyps time today # 列出所有游戏的 最后一次启动时间 和 今天游戏日常范围内的启动状态
_Hyps time report <GAME_NAME> # 每日刷新、今日状态与时长、下次刷新倒计时、最近 12 周热力图
```

`time report` 的每日刷新时间来自游戏声明或 `features.time_record.today.reset`，未设置时按本地 00:00 统计且不显示日常相关项。热力图每格一个游戏日，按当天时长分 5 档；有颜色时用方块深浅区分，重定向到文件时退回字符密度。

### 游戏版本

```bash
_Hyps game outdated           # 列出已配置且支持版本检查的游戏及版本状态（含预下载状态）
_Hyps game outdated [GAME_ID] # 详细检查指定游戏的版本、安装路径和预下载状态
```

## 删除

 - 删掉本项目的文件夹
 - 如果还设置了单独的配置文件夹，也别忘了
    - 项目根目录的 `config.conf` 设置了 `path.config = "./config"`。配置文件夹可以被设置到别的地方，或者删掉使用默认值 `$XDG_CONFIG_HOME/hypsc` (`~/.config/hypsc`)
 - `/tmp/hypsc` (`path.temp` 临时文件)
 - `$XDG_RUNTIME_DIR/hypsc` (`path.runtime`)
 - `$XDG_CACHE_HOME/hypsc` (`~/.cache/hypsc`)
    - 着色器缓存 (`cache.shader.enabled` 和 `cache.dx.enabled`)
    - 源码变更检测 (一些需要编译的小工具，校验和在 `checksums/`)
    - 需要编译的小工具的产物 (`bin/`)，删除后下次启动会重新编译 (fpsunlock 还需要 sudo 设置权限)
 - `$XDG_DATA_HOME/hypsc` (`~/.local/share/hypsc` `path.data`)
    - OverlayFS
    - Wine Prefix / Proton Compat Data
    - 游玩时间记录
 - `$XDG_STATE_HOME/hypsc` (`~/.local/state/hypsc` `path.state`)
