# Hyps

> [!CAUTION]
>
> 铲屎山中...
>
> 当初没想到屎山会堆这么高，普通的启动脚本架构无法承受了。最近正在计划进行重构，**可能有较多的 breaking changes**

(目前自用) 在 Linux 上运行运行部分游戏的脚本

目前，这仅仅是个**启动脚本**和一些便捷工具，远远达不到启动器的要求！

目前支持或准备支持的游戏：

米家
- [x] 崩坏三
- [x] 原神 (解决方案多变，最后测试 7.0)
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
- [x] 使用 FUSE OverlayFS 分离游戏运行时产生的数据或缓存
- [x] 记录游玩时间和历史
- [x] 【部分游戏/通用】通过临时修改 Hosts 断网启动
- [x] 【原神/通用】通过注册表伪装 Hostname
- [x] 【原神/通用】游戏窗口关闭时杀死进程
- [x] 【原神】使用 FPS Unlocker 解锁帧率
- [x] 【崩坏：星穹铁道】注册表解锁帧率

目前 **不支持** 的功能：

- 自动下载、安装或更新：游戏、启动器、Wine/Proton、DXVK/VKD3D 等
- 新增永久性的 Hosts 条目等

## 使用方法

1. clone 本项目

2. 你可以选择在本项目的 `config.conf` 中修改配置文件的路径，默认路径就是本项目的 `./config` 文件夹，所以你也可以选择不改

3. 到配置文件夹的 `games.examples` 目录下，找到 `_common.example.conf`，复制文件到配置文件夹的 `games` 下，重命名为 `_common.conf` 并修改里面的配置。很多功能默认都被注释掉了，如有需要可以将其打开

4. 到配置文件夹的 `games.examples` 目录下，选个你想玩的游戏，复制一个 `<name>.example.conf` 文件到配置文件夹的 `games` 下，重命名为 `<name>.conf`，并修改里面的配置，比如 `runner.name` 和一些路径

5. 运行 `scripts` 文件夹下对应游戏的脚本

## 依赖

 - `bash`: 主要的脚本用它编写
 - 一些基础的工具，如 `coreutils`、`grep`、`awk`、`sed`、`pkill`、`pgrep`、`sudo` 等
 - 下面列出的 Runner 中的依赖。主要就是一些版本的 Proton 和 umu-launcher
 - `gcc`、`sha256sum`: 两个用 C 写的小工具（`sha256sum` 用来校验源代码以重新编译）
    - `tools/fpsunlock/unlocker.c`（还额外需要 `setcap`、`getcap`）
    - `tools/xwin-watch/xwin-watch.c`
 - `python3`: 一个用 python3 写的小工具
    - `tools/starrail-fps.py`

## Runner

`RUNNER` 即是你要运行游戏的运行器，这里提供了一些默认的运行器

<div>
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
                <td><code>umu-cachyos</code></td>
                <td><code>umu-run</code><br/><code>/usr/share/steam/compatibilitytools.d/proton-cachyos-slr/</code></td>
                <td><code>umu-launcher</code><br/><code>archlinuxcn/proton-cachyos-slr</code></td>
            </tr>
            <tr>
                <td><code>umu-dwproton</code></td>
                <td><code>umu-run</code><br/><code>/usr/share/steam/compatibilitytools.d/dwproton/</code></td>
                <td><code>umu-launcher</code><br/><code>aur/dwproton-bin</code></td>
            </tr>
            <tr>
                <td><code>umu-ge-proton</code></td>
                <td><code>umu-run</code><br/><code>/usr/share/steam/compatibilitytools.d/proton-ge-custom/</code></td>
                <td><code>umu-launcher</code><br/><code>archlinuxcn/proton-ge-custom-bin</code></td>
            </tr>
        </tbody>
    </table>
</div>

一般情况下，推荐 `umu-ge-proton`（部分游戏可以使用 `umu-dwproton` 以获得更好体验）

## 功能

刚重构完，还没写呢... ✋😭🤚

## 删除

删掉本项目的文件夹即可

如果还设置了单独的配置文件夹，也别忘了

本项目默认会在 `/tmp/hypsc` 留下一些与启动流程相关的启动脚本；在 `$XDG_CACHE_HOME/hypsc` (`~/.cache/hypsc`) 留下一些着色器缓存和用于校验源代码是否变动以便重新编译的哈希值；也可以检查下 `$XDG_DATA_HOME/hypsc` (`~/.local/share/hypsc`) 里面有没有东西，一些功能会在此处保留一些数据（如 Overlay 的默认配置下，还有记录的游玩时间和历史）
