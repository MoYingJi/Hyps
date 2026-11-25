# 终末地父进程检查与替身配置

终末地 1.6 起要求游戏由官方启动器拉起，否则会报错「请通过官方启动器打开游戏」。Hyps 提供两种方式绕过这个检查：

- 替身父进程：把游戏 exe 硬链接或复制成 `Games.exe`，挂起它作为游戏的父进程
- 挂起官方启动器：直接启动官方启动器并挂起它作为父进程

两种方式都通过 `endfield.surrogate.*` 配置。

## 快速配置

不依赖官方启动器时，推荐 copy 模式：

```ini
endfield.surrogate.mode = "copy"
endfield.surrogate.exit_after = 30
game.umu_id = "umu-endfield"
```

已经安装了官方启动器时，也可以直接挂起它：

```ini
endfield.surrogate.mode = "launcher"
endfield.surrogate.launcher = "/path/to/Hypergryph Launcher"
endfield.surrogate.exit_after = 30
game.umu_id = "umu-endfield"
```

## 方式一：替身父进程

### 模式

`endfield.surrogate.mode` 取以下值：

| 值 | 行为 |
| --- | --- |
| `hardlink` | 硬链接，失败不回退 |
| `copy` | 复制 |
| `hardlink-or-copy` | 优先硬链接，失败时回退为复制 |

### overlay

- overlay 开启时，`hardlink-or-copy` 会自动按 `copy` 执行，避免游戏 exe 的 copy-up
- 显式 `hardlink` 在 overlay 下只会警告：硬链接会触发游戏 exe copy-up，而且要求 upper 与目标在同一文件系统；失败时由工具报错
- 从 `hardlink-or-copy` 降级为 `copy` 时，`hardlink_dir` / `hardlink_target` 会被忽略并警告

### 目标位置

替身目标可以统一设置，也可以按硬链接/复制分别设置：

| 配置项 | 作用 |
| --- | --- |
| `endfield.surrogate.dir` | 目录，文件名固定为 `Games.exe` |
| `endfield.surrogate.target` | 完整文件路径，可自定义文件名 |
| `endfield.surrogate.hardlink_dir` / `hardlink_target` | 只作用于硬链接，优先于无前缀配置 |
| `endfield.surrogate.copy_dir` / `copy_target` | 只作用于复制，优先于无前缀配置 |

规则如下：

- 同一前缀下，`dir` 与 `target` 只能二选一
- `hardlink_` / `copy_` 优先级高于无前缀的 `dir` / `target`
- 硬链接默认目标为 `<游戏目录>/../gryph-surrogate/Games.exe`。overlay 开启时游戏路径是 runtime 视图，所以默认目标会落在 overlay 数据目录
- 复制默认目标为 `$TEMP_DIR/Games.exe`（默认 `/tmp/hypsc/Games.exe`）
- 目标路径按配置原样使用，不经过 overlay。如果指向游戏目录，overlay 下会写到安装目录而不是 upper；建议放在 overlay 之外，或使用默认临时目录

### 其他选项

| 配置项 | 作用 |
| --- | --- |
| `endfield.surrogate.launcher` | 替身源文件，默认为游戏 exe 自身 |
| `endfield.surrogate.keep` | 游戏退出后保留替身文件和本次新建的目录 |
| `endfield.surrogate.show_info` | 通过信息框显示工具的 info 日志 |
| `endfield.surrogate.exit_after` | 游戏启动后等待 N 秒，结束挂起的父进程并退出，游戏继续运行 |
| `game.umu_id` | 标记实际游戏，用于匹配 ProtonFixes |

## 方式二：挂起官方启动器

```ini
endfield.surrogate.mode = "launcher"
endfield.surrogate.launcher = "/path/to/Hypergryph Launcher"
```

`endfield.surrogate.launcher` 可以是：

- 启动器目录：自动选择版本号最高的 `Games.exe`
- `Games.exe` 的完整路径

此模式不再使用 `dir` / `target` / `hardlink_*` / `copy_*` / `keep`。

## 与独立工具的关系

`tools/gryph-surrogate/` 是一个不依赖 Hyps 的独立工具。Hyps 把上面的配置翻译成工具参数：

- `mode` → `--mode`
- `dir` / `target` → `--target`
- `hardlink_dir` / `hardlink_target` → `--hardlink-target`
- `copy_dir` / `copy_target` → `--copy-target`
- `keep` → `--keep-surrogate`
- `show_info` → `--show-info`
- `exit_after` → `--launcher-exit-after`（秒转毫秒）

构建、CLI 参数、签名要求和清理规则以 [gryph-surrogate.c](../tools/gryph-surrogate/gryph-surrogate.c) 头部注释为准。

## 注意

- 替身必须来自真正签名的游戏 PE 或官方启动器，普通改名无法通过检查
- 游戏更新后签名证书可能更换，需要重新检查游戏目录里的 PE 签名证书
- `endfield.surrogate.dir` / `target` 不跟随 overlay，这是预期行为
- overlay 下优先使用 `copy`，不要依赖 `hardlink` 的 copy-up
