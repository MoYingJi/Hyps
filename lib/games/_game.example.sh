#!/hint/bash
# 游戏实现骨架
#
# 用法：复制为 lib/games/<GAME_NAME>.sh，文件名必须与 GAME_NAME 一致，再按需修改
# 本文件不是游戏：没有同名配置和启动脚本，不会被加载
#
# 生命周期约束
# - 单次启动只加载一个游戏实现
# - 批量查询从公共环境出发，每个游戏在独立子 shell 中加载、查询、整理，父级只接收输出和退出状态，不通过 unset 切换
# - 加载游戏文件只定义函数、初始化内存状态和注册钩子
# - 启动外部程序、挂载和文件修改放在明确调用的函数或生命周期钩子中，子 shell 不会撤销这些操作
# - 只写游戏特有的声明和逻辑：固定属性用变量，需要计算或执行的接口用函数
# - GAME_NAME 同时是游戏 ID、配置文件/脚本标识，显示名和路径名单独声明
# - 游戏目录内的路径通过 game_fs_path / game_fs_write_path 获取，不要直接用 game.exe 拼路径

#shellcheck disable=SC2034 # 元数据变量供通用模块读取

# 这提供了一些函数如 日志输出、终端颜色、path_dirname 等工具函数、path_plan / launch_plan 相关函数、配置声明和读取、生命周期钩子注册
# 这是幂等的，虽然 Hyps 已经会加载它了，这里加载是为了显式依赖它，让 bash-language-server / shellcheck 能正确识别函数和变量
#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

# 游戏元数据，均可选

# 人类可读的游戏名（中文），用于 init 和 UI，未设置或为空时回退到 GAME_NAME
GAME_DISPLAY_NAME="示例游戏"
# 路径友好的游戏名，只允许 [A-Za-z0-9._-]+，且不能是 . 或 ..，未设置或为空时回退到 GAME_NAME
# 只用于截图等用户可见目录，不用于内部数据目录
GAME_PATH_NAME="ExampleGame"
# 日常刷新时间，未声明时默认不显示，空值或假值表示不参与
# 用户配置 features.time_record.today.reset 优先于游戏声明
GAME_DAILY_RESET="04:00 Asia/Shanghai"

# 以下函数都是可选实现，通过 type -t 检测，不存在时不会报错

# 接受 game.exe，在 stdout 输出安装根目录（通常是游戏文件夹本身）
# 该根同时用于 overlay 的 lower 和 GameFS 的 install 视图
# 未实现时 install 视图留空，overlay 和依赖 install 的功能会报错，可用 game.install_dir 显式指定根
game_install_dir() {
    local game_exe="$1"
    local game_dir
    path_dirname "$game_exe" game_dir
    printf '%s\n' "$game_dir"
}

# 接受 install 根，在 stdout 输出一个主 exe
# 只填 game.install_dir 时用它派生 game.exe
# 必须绝对路径、存在、位于 install 下；不同变体的 exe 名称由游戏实现自行判断（如国服/国际服）
game_executable() {
    local install_dir="$1"
    printf '%s\n' "$install_dir/Game.exe"
}

# 不接受参数，声明游戏路径角色，不直接执行任何操作
# 用 path_plan_declare <role> <scope> <rel> [label] 和 path_plan_note <role> [text]
# 角色目前有 userdata:screenshot 和 shader-cache
game_paths() {
    path_plan_declare userdata:screenshot runtime "Screenshots"
    path_plan_declare shader-cache all "ShaderCache"
    path_plan_note shader-cache "这是一个示例游戏，哪来的着色器缓存（"
}

# game_version_local <game_exe> <version_nameref> <variant_nameref> <context_nameref>
# 写入本地版本、变体标识和远程查询上下文
# 本地版本只含游戏本体已安装的版本，不返回预下载版本
# 变体是游戏文件本身的分发变体（如不同渠道的客户端），而非区服，允许为空
# 上下文是不透明字符串，原样交给 game_version_remote
game_version_local() {
    local game_exe="$1"
    local -n _version="$2"
    local -n _variant="$3"
    local -n _context="$4"

    # 获取安装根目录
    local install_dir
    install_dir="$(game_install_dir "$game_exe")" || return 1

    _version="0.0.0" # 替换为真实读取
    _variant=""
    _context=""
}

# game_version_variant_human_readable <variant>
# 在 stdout 输出适合显示的名称
# 仅当 game_version_local 返回了非空变体标识时才会被调用，未实现时直接显示变体标识本身
game_version_variant_human_readable() {
    local variant="$1"
    case "$variant" in
        *) printf '%s\n' "未知" ;;
    esac
}

# game_version_remote <variant> <context> <remote_nameref> <predownload_nameref>
# 接受变体标识、上下文（即 game_version_local 写入的内容，必填，可为空字符串）和两个 nameref
# 将远程版本与预下载版本写入变量；无预下载时预下载写为空字符串，预下载版本可能高于远程版本
game_version_remote() {
    local variant="$1"
    local context="$2"
    local -n _remote_version="$3"
    local -n _predownload_version="$4"

    _remote_version="0.0.0" # 替换为真实查询
    _predownload_version=""
}

# 高级用法，可以像 feature 一样注册生命周期钩子、声明和读取配置，按需

# eg.* (Example Game 首字母做配置前缀简写，可按需随意取，保持唯一即可)
config_declare eg.hello_world_before_game.enabled bool \
    --in game-instance \
    --description "在游戏启动前显示 Hello World"
config_declare eg.hello_world_before_game.message string \
    --in game-instance \
    --when eg.hello_world_before_game.enabled \
    --default "Hello World" \
    --description "在游戏启动前显示的消息"

# 惯例函数命名，不遵守也行
# feat_ 功能前缀，eg_ 游戏前缀 (同上)，hello_world_before_game 功能名，pre_start 生命周期阶段名
feat_eg_hello_world_before_game_pre_start() {
    if config_is_true eg.hello_world_before_game.enabled; then
        local message
        config_read eg.hello_world_before_game.message message
        echo "$message"

        if [ ! -t 2 ]; then
            log_debug eg-hello "用户似乎并没有看我的 '$message'，伤心 qaq"
        fi
    fi
}

# 注册钩子
register_hook pre_start feat_eg_hello_world_before_game_pre_start
