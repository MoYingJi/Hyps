# 开发指南

> 先写一点基础的

## 总览

项目主体在 `lib/` 下，用 bash 写，游戏和 CLI 入口点在 `scripts/`

在 `tools/` 下有一些小工具，都完全可以脱离本项目独立运行，有使用 Python 和 C 语言写的
 - C 语言推荐使用 clangd 作为 LSP，执行 `development/gen-compile-db.sh` 生成 `compile_commands.json` 文件给 clangd 用
 - `gryph-surrogate` 需要用 `mingw-w64` 交叉编译
 - `xwin-watch` 中，`protocols/` 下是协议 XML 文件，`generated/` 是 `wayland-scanner` 生成的文件，也一并提交到了 git，当协议 XML 文件有变动时，执行 `development/gen-wayland-protocols.sh` 重新生成文件到 `generated/`

## 生命周期

一共有五个阶段
 - `load_config`: 加载和校验配置。无副作用，任意失败立即退出
 - `prepare`: 准备。有副作用，任意失败立即跳到 `cleanup`
 - `pre_start`: 启动前。有副作用，任意失败立即跳到 `cleanup`
 - `post_start`: 启动后。有副作用，任意失败会继续执行
 - `cleanup`: 退出前清理。有副作用，任意失败会继续执行

可通过 `register_hook <阶段> <函数名> [优先级] [依赖关系]` 注册

## 游戏实现

游戏实现放在 `lib/games/<GAME_NAME>.sh` 下

游戏实现可以描述游戏本身，实现哪些函数都可选的
 - `overlay_auto_lower`: 接受一个参数代表游戏本体 exe，即 `game.exe` 配置。在 stdout 输出游戏在 overlay 中推荐的 lower 目录 (通常是游戏文件夹本身)
 - `time_record_today_reset`: 不接受参数。在 stdout 输出游戏的日常刷新时间 (如 `04:00 Asia/Shanghai`)
 - `userdata_link`: 将游戏本体、prefix 内的用户数据 (如截图) 链接到一起。接受三个参数，第一个是 prefix 的 drive_c 路径，第二个是 prefix 内用户的 USERPROFILE 路径，第三个是 `game.exe`。还有一个环境变量 `SCREENSHOTS` 为统一截图目录，常将已有截图复制到 `$SCREENSHOTS/<游戏目录>`，然后将游戏原截图目录软链接至此处。路径均为 Linux 侧的路径。提供 `try_link_dir` 工具函数方便完成复制后创建链接这一重复操作
 - `shader_cache_invalidate` 接受和 `userdata_link` 相同的参数。删除游戏的着色器缓存 (无需处理程序已负责的 `__GL_SHADER_DISK_CACHE_PATH`、`DXVK_STATE_CACHE_PATH`、`VKD3D_SHADER_CACHE_PATH` 等，只负责游戏产出的**游戏特定**的着色器部分)

游戏实现中也可以直接注册生命周期钩子

## Launch Plan

Launch Plan 中有游戏运行时实际的 exe、工作目录、启动参数，管理 wrapper、bat 片段、`LD_PRELOAD`，决定是直接启动还是通过自定义 bat 脚本启动，组装 wine 侧的启动命令和总启动命令

Game Handler 负责 wine 侧的组装，接受一个 nameref 参数，自行获取配置，并将 wine 侧的启动命令输出到给定的 nameref 数组内。默认的 Game Handler 会简单地获取和拼接 Launch Plan 内的游戏 exe 和启动参数。Feature 按需在 Launch Plan 注册 Game Handler。Game Handler 不能共存，同时只能有一个

> [!NOTE]
>
> 不像在 Linux 侧 Launch Plan 会提供 Runner Wrapper 这种允许共存的修改，在 Wine 侧只有一个独占的 Game Handler，这是有意为之，因为 Wine 侧的 Wrapper 通常直接与游戏接触，它们本来就互斥
