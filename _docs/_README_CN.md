# Hyps

(目前自用) 在 Linux 上运行运行部分游戏的脚本

目前，这仅仅是个**启动脚本**和一些便捷工具，远远达不到启动器的要求！

目前支持或准备支持的游戏：

米家
- [x] 崩坏三
- [x] 原神
- [x] 崩坏：星穹铁道
- [x] 绝区零
- [ ] 崩坏：因缘精灵 (如果可能的话)

其他
- [x] 鸣潮
- [ ] 明日方舟：终末地 (如果可能的话)

目前支持或准备支持的功能：

- [x] 启动游戏
- [x] 使用 Gamemode 或 MangoHud 启动游戏
- [x] 使用 Taskset 关联 CPU 核心
- [x] 自定义 DXVK/VKD3D 缓存路径
- [x] 启用 NVIDIA 着色器缓存并自定义路径
- [x] 启用 NVIDIA Smooth Motion
- [x] 修改权限以支持 MangoHud 读取 Intel CPU 功耗
- [x] 【部分游戏/通用】通过临时修改 Hosts 断网启动
- [x] 【原神/通用】通过注册表伪装 Hostname
- [x] 【原神/通用】游戏窗口关闭时杀死进程
- [x] 【原神】使用 FPS Unlocker 解锁帧率
- [ ] 【崩坏：星穹铁道】注册表解锁帧率

目前 **不支持** 的功能：

- 自动下载、安装或更新：游戏、启动器、Jadeite、Wine/Proton、DXVK 等
- 新增永久性的 Hosts 条目以禁止日志上传、分析等

## 使用方法

1. clone 本项目

2. 你可以选择在本项目的 `config.conf` 中修改配置文件的路径，默认路径就是本项目的 `./Config` 文件夹，所以你也可以选择不改

3. 到配置文件夹的 `Games.examples` 目录下，找到 `_common.example.conf`，复制文件到配置文件夹的 `Games` 下，重命名为 `_common.conf` 并修改里面的配置。很多功能默认都被注释掉了，如有需要可以将其打开

4. 到配置文件夹的 `Games.examples` 目录下，选个你想玩的游戏，复制一个 `<name>.example.conf` 文件到配置文件夹的 `Games` 下，重命名为 `<name>.conf`，并修改里面的配置，比如 `RUNNER` 和一些路径

5. 运行 `Scripts` 文件夹下对应游戏的脚本

## Runner

`RUNNER` 即是你要运行游戏的运行器，默认提供了 `proton-system` 和 `umu-run` 两个运行器，如果你的运行器不在这两个里面，请仿照默认配置自行添加

`proton-system` 对应 `proton-ge` 命令

`umu-run` 对应 `umu-run` 命令，同时指定了 Proton 路径为系统 Proton。

如果你是 Arch Linux，那么安装 `aur/proton-ge-custom-bin` 即可使用 `proton-system`，安装 `umu-launcher` 和 `aur/proton-ge-custom-bin` 即可使用 `umu-run`

一般情况下，我个人会推荐 `proton-system`，如果遇到问题可以改用 `umu-run`

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
