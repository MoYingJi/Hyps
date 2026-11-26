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
- [x] 原神 (解决方案多变)
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
- [x] 清除着色器缓存（部分游戏）
- [x] 修改 NVIDIA DLSS (DXVK NVAPI) 相关设置
- [x] 修改权限以支持 MangoHud 读取 Intel CPU 功耗
- [x] 使用 FUSE OverlayFS 分离游戏运行时产生的数据或缓存
- [x] 记录游玩时间和历史
- [x] 【原神/通用】通过注册表伪装 Hostname
- [x] 【原神/通用】游戏窗口关闭时杀死进程
- [x] 【原神】使用 FPS Unlocker 解锁帧率
- [x] 【原神】强制 D3D12 图形 API（需要额外依赖）
- [x] 【崩坏：星穹铁道】注册表解锁帧率（需要 python3）
- [x] 【明日方舟：终末地】通过官方启动器直接启动游戏（需要 mingw-w64）

终末地的父进程检查与替身配置见 [docs/endfield-surrogate.md](endfield-surrogate.md)

目前 **不支持** 的功能：

- 自动下载、安装或更新：游戏、启动器、Wine/Proton、DXVK/VKD3D 等
- 新增永久性的 Hosts 条目等

## 依赖

 - `bash`: 主要的脚本用它编写
 - 一些基础的工具，如 `coreutils`、`grep`、`awk`、`sed`、`pkill`、`pgrep`、`sudo` 等
 - 下面列出的 Runner 中的依赖。主要就是一些版本的 Proton 和 umu-launcher
 - `sha256sum`、`md5sum`: 用来校验要编译的小工具，和验证游戏文件完整性
 - `curl`、`jq`、`openssl`: 查询游戏最新版本（`game outdated`）
 - `gcc`: 两个用 C 写的小工具
    - `tools/fpsunlock/unlocker.c` (还额外需要 `setcap`、`getcap`)
    - `tools/xwin-watch/xwin-watch.c`
 - `x86_64-w64-mingw32-gcc` (mingw-w64，配置了终末地启动桥或父进程替身时需要): 交叉编译 Windows 小程序，无需在 Windows 上编译
    - `tools/gryph-surrogate/gryph-surrogate.c`
 - `python3`: 一个用 python3 写的小工具
    - `tools/starrail-fps.py`
    - `tools/genshin-d3d12/patch-unitypy.py` (还额外需要 UnityPy，系统中安装了 uv 时会自动处理)
    - `tools/genshin-d3d12/patch-bytes.py` (另一个原生实现，直接按字节改)

## Runner

内置预设都依赖 `umu-run`（Arch 包 `umu-launcher`）。

| 预设 | Proton 目录（位于 `/usr/share/steam/compatibilitytools.d/`） | Arch 包 |
| --- | --- | --- |
| `umu-cachyos` | `proton-cachyos-slr` | `archlinuxcn/proton-cachyos-slr` |
| `umu-dwproton` | `dwproton` | `aur/dwproton-bin` |
| `umu-proton-ge` | `proton-ge-custom` | `archlinuxcn/proton-ge-custom-bin` |

## 文档

- [使用指南](USAGE.md) · 安装、旧配置迁移、模板和游戏功能
- [开发指南](DEVELOPMENT.md) · 模块边界与启动流程
- [配置系统](CONFIGURATION.md) · 声明、解析和环境绑定
