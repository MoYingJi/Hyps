# Hyps

(目前自用) 在 Linux 上运行运行部分游戏的脚本

目前，这仅仅是个**启动脚本**和一些便捷工具，远远达不到启动器的要求！

目前支持或准备支持的游戏：

米家
- [x] 崩坏三
- [ ] ~~原神~~ (很难在现有代码的架构体系上修改适配目前更新的版本)
- [x] 崩坏：星穹铁道
- [x] 绝区零
- [ ] 崩坏：因缘精灵 (如果可能的话)

其他
- [x] 鸣潮
- [x] 明日方舟 PC
- [x] 明日方舟：终末地

目前支持或准备支持的功能：

- [x] 启动游戏（废话）
- [x] 使用 Gamemode 或 MangoHud 启动游戏
- [x] 使用 Taskset 关联 CPU 核心
- [x] 自定义 DXVK/VKD3D 缓存路径
- [x] 启用 NVIDIA 着色器缓存并自定义路径
- [x] 修改 NVIDIA DLSS (DXVK NVAPI) 相关设置
- [x] 修改权限以支持 MangoHud 读取 Intel CPU 功耗
- [x] 【部分游戏/通用】通过临时修改 Hosts 断网启动
- [x] 【原神/通用】通过注册表伪装 Hostname
- [x] 【原神/通用】游戏窗口关闭时杀死进程
- [x] 【原神】使用 FPS Unlocker 解锁帧率
- [ ] 【崩坏：星穹铁道】注册表解锁帧率

目前 **不支持** 的功能：

- 自动下载、安装或更新：游戏、启动器、Jadeite、Wine/Proton、DXVK/VKD3D 等
- 新增永久性的 Hosts 条目等

## 使用方法

1. clone 本项目

2. 你可以选择在本项目的 `config.conf` 中修改配置文件的路径，默认路径就是本项目的 `./Config` 文件夹，所以你也可以选择不改

3. 到配置文件夹的 `Games.examples` 目录下，找到 `_common.example.conf`，复制文件到配置文件夹的 `Games` 下，重命名为 `_common.conf` 并修改里面的配置。很多功能默认都被注释掉了，如有需要可以将其打开

4. 到配置文件夹的 `Games.examples` 目录下，选个你想玩的游戏，复制一个 `<name>.example.conf` 文件到配置文件夹的 `Games` 下，重命名为 `<name>.conf`，并修改里面的配置，比如 `RUNNER` 和一些路径

5. 运行 `Scripts` 文件夹下对应游戏的脚本

## Runner

`RUNNER` 即是你要运行游戏的运行器，这里提供了一些默认的运行器

<div style="overflow-x: auto; white-space: nowrap;">
    <table>
        <thead>
            <tr>
                <th>Runner</th>
                <th>依赖</th>
                <th>Arch 包</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td><code>proton-system</code></td>
                <td><code>proton-ge</code></td>
                <td><code>archlinuxcn/proton-ge-custom-bin</code></td>
            </tr>
            <tr>
                <td><code>umu-cachyos</code></td>
                <td><code>umu-run</code><br/><code>/usr/share/steam/compatibilitytools.d/proton-cachyos-custom/</code></td>
                <td><code>umu-launcher</code><br/><code>archlinuxcn/proton-ge-custom-bin</code></td>
            </tr>
            <tr>
                <td><code>umu-run</code></td>
                <td><code>umu-run</code><br/><code>/usr/share/steam/compatibilitytools.d/proton-ge-custom/</code></td>
                <td><code>umu-launcher</code><br/><code>archlinuxcn/proton-cachyos-slr</code></td>
            </tr>
        </tbody>
    </table>
</div>

一般情况下，推荐 `umu-run`

如果要新增 Runner，可以仿照现有配置自行添加。`WINE` 是将会调用的命令；`PREFIX_VAR_NAME` 是 Wine Prefix 的变量名，自定义 Prefix 会存入以此值为变量名的环境变量；`WINESERVER_KILL_CMD` 是用于杀死 wineserver 的命令，我感觉这设计得不好，我已经不用了；`PROTONPATH` 是 umu-run 中用于指定 proton 路径的环境变量

## 新增游戏适配

其实非常简单，在 `Scripts` 文件夹下新建一个脚本，仿照其他脚本写一下就好了

`GAME_NAME` 就是决定了配置文件 `Games/${GAME_NAME}.conf` 的名字的，同时也会决定 DXVK/VKD3D 或 NVIDIA 的缓存路径

个人觉得，最好抄绝区零的配置，相对简单一点，配置文件里只留基础的 `RUNNER`、`GAME` 就能运行了，不过最好还是写一下 `PREFIX`，个人习惯隔离运行环境

## 配置原理

运行游戏时，此脚本会读取 `Games` 下的 `_common.conf`，然后根据游戏名读取游戏特定配置 `<name>.conf`，最后读取 `Runners` 文件夹中的 `<runner>.conf`

读取操作其实就是 `source`，在配置中定义一些变量，就可以在脚本中引用，也因此，大多数配置是不关心你写在什么位置的，你既可以在 `_common.conf` 里写，也可以在 `<name>.conf` 里写，甚至是在 `<runner>.conf` 里写！

大多数可以设置的变量已经写在了 [`_Lib.sh`](../Scripts/_Lib.sh) 文件最前面的注释中，也给出了推荐填写处，不过在这里的东西大多在示例里都有

这几个配置的优先级从小到大是 `_common.conf` < `<name>.conf` < `<runner>.conf` <br/>
`_common.conf` < `<name>.conf` 是能理解的 <br/>
`<runner>.conf` 最大是因为脚本需要读取前两个文件才能得知需要用哪一个 Runner，因此这个文件最后被读取，会覆盖前面的配置，尽量少而必要地在这里写东西吧

## 功能

这里只介绍部分功能的简单使用，这些功能还有其它用法，本项目也有更多功能，`Scripts/_Lib.sh` 的头部的一大堆注释里有这些功能的选项

### 临时 Hosts 修改

部分游戏需要在启动时修改 `/etc/hosts` 以启动，首先在游戏配置文件里加上

```bash
NETWORK_HOSTS="y"
NETWORK_HOSTS_CONTENT="0.0.0.0 example.com" # 替换为自定义内容
```

默认为调用 [XWin Watch](#xwin-watch) 等待指定窗口出现（需要指定 `XWIN_WATCH_WINDOW`），也可以指定 `NETWORK_HOSTS_DURATION` 为数字来指定秒数

### XWin Watch

用于监视 X11/Xwayland 窗口的小功能

```bash
XWIN_WATCH_WINDOW="窗口名称" # 替换窗口名称

# 还有一些可选的配置项，一般不动也可以

XWIN_WATCH_SLEEP="5" # 检测窗口出现的间隔 (秒)
XWIN_WATCH_INTERVAL="5" # 检测窗口消失的间隔 (秒)
XWIN_WATCH_ATTEMPTS="20" # 检测窗口出现的尝试次数

# 如果不需要执行指定命令，到这里就可以了

XWIN_WATCH_ON_EXISTS="echo 窗口出现"
XWIN_WATCH_ON_CLOSED="echo 窗口消失"
XWIN_WATCH_ON_FAILED="echo 检测失败"
```

程序启动时，会间隔 `XWIN_WATCH_SLEEP` 秒循环检测窗口出现，最多尝试 `XWIN_WATCH_ATTEMPTS` 次，如果没检测到就运行 `XWIN_WATCH_ON_FAILED`，如果检测到了就运行 `XWIN_WATCH_ON_EXISTS`。此时，如果 `XWIN_WATCH_ON_CLOSED` 没东西要执行就立即退出，有东西要执行则程序会间隔 `XWIN_WATCH_INTERVAL` 秒循环检测窗口消失，检测到窗口消失时执行 `XWIN_WATCH_ON_CLOSED`。程序非正常退出前会执行 `XWIN_WATCH_ON_FAILED`

### Overlay

使用 FUSE OverlayFS

overlayfs 是好文明！如果不知道的建议去查阅相关资料。在本项目中，其主要用途是在只读游戏本体的情况下运行游戏。有时，游戏是 NTFS 这种在 Linux 下的灵车文件系统，或者直接是只读的，就需要这项功能

```bash
OVERLAY="y"
OVERLAY_LOWER="/path/to/game" # 手动指定一个 lowerdir
OVERLAY_DIR="/path/to/rw/dir" # 指定一个可读写的目录
# GAME 选项保持原样，会自动处理
```

此时，fuse overlayfs 被挂载在 `$OVERLAY_DIR/mount` 里，游戏也真正运行在这里，这里是可读写的，写入都会保存在 `$OVERLAY_DIR/upper` 里而不会真正写到 `$OVERLAY_LOWER`

目前此功能还有些问题，比如无法自动卸载

## 其他

### 下载和更新游戏

我推荐直接使用 Wine 运行官方启动器

对于鸣潮，可能需要[特殊解决方案](https://moyingji.github.io/record/linux-wuwa-launcher)，或者使用 [ww-cli](https://github.com/timetetng/wutheringwaves-cli-manager)

### NVIDIA 显卡未被调用

如果在混合模式遇到无法调用 NVIDIA 独立显卡（仅使用了核显），可以尝试 `./Tools/nvidia-env.sh`，使用方法是在对应游戏的配置文件中加上一行 `source ./Tools/nvidia-env.sh`

### NVIDIA DLSS

详见
 - [Passing driver settings · jp7677/dxvk-nvapi Wiki](https://github.com/jp7677/dxvk-nvapi/wiki/Passing-driver-settings)
 - [DLSS / Smooth Motion / Reflex — NVIDIA Driver Installation Guide](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/gaming.html)

总之，可以在配置（包括游戏特定配置和 `_common.conf`）中添加一些<ruby>配置项<rp>（<rt>环境变量<rp>）</ruby>传递驱动设置

```bash
# 这里是部分常见设置
PROTON_DLSS_UPGRADE=1 # 自动更新 DLSS
PROTON_DLSS_INDICATOR=1 # 启用 DLSS 指示器
DXVK_NVAPI_DRS_NGX_DLSS_SR_OVERRIDE_RENDER_PRESET_SELECTION=render_preset_m # 设置 DLSS 超分辨率预设
DXVK_NVAPI_VKREFLEX=1 # 启用 NVIDIA Reflex 的 Vulkan 层
```

### Hosts 权限

部分游戏需要临时修改 `/etc/hosts` 以启动，因此需要打开 `NETWORK_HOSTS` 选项，这个选项会修改 hosts，当没有写入权限时会索要 sudo 以临时使 hosts 可写（a+w）。但放心，hosts 会在脚本结束前被恢复原状，包括权限（会再索要一次 sudo 以恢复权限，如果 sudo 过期时间较长，可能不需要手动干预）

要使得脚本不索要 sudo，推荐让自己可写 hosts，个人推荐做法是新建一个用户组

```bash
sudo groupadd hosts
sudo usermod -aG hosts $(whoami)
sudo chgrp hosts /etc/hosts
sudo chmod g+w /etc/hosts
```

## 删除

删掉本项目的文件夹即可

如果还设置了单独的配置文件夹，也别忘了

本项目默认会在 `/tmp/hypsc` 留下一些与启动流程相关的启动脚本；在 `$XDG_CACHE_HOME/hypsc` (`~/.cache/hypsc`) 留下一些着色器缓存和用于校验源代码是否变动以便重新编译的哈希值；也可以检查下 `$XDG_DATA_HOME/hypsc` (`~/.local/share/hypsc`) 里面有没有东西，目前还没有用到，但后面可能用
