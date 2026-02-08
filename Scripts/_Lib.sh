#!/hint/bash
#shellcheck disable=1090,1091,2086,2164
# ↑ shellcheck: 我不如烂这算了

# 神秘小脚本

# 神秘小脚本内所使用的都是全局变量，且对于 conf 文件都是直接 source
# 所以在 conf 文件中添加其他变量可能会造成奇奇怪怪的效果

# 脚本所使用的部分环境变量
# 推荐填写处的 <runner>.conf 是指运行器配置文件，<game>.conf 填写的是游戏配置文件，<g/c>.conf 是指游戏通用配置文件或游戏配置文件均可
# 默认值的 <bool y/n> 是指该值只会被以 bool 类型被用到，且这些值要填只能为 y 或 n，<empty> 是指空值
# 要求的 选必 是指如果启用了某功能就必填

# 环境变量              简略描述                   要求   推荐填写处      默认值

# GAME_NAME             游戏名                     必填   「由脚本提供」
# CONFIG_DIR            配置目录                   选填   config.conf     $XDG_CONFIG_DIR/hypsc
# CACHE_DIR             缓存目录                   选填   config.conf     $XDG_CACHE_DIR/hypsc
# COMMON_GAME_CONF      游戏通用配置文件位置       选填   config.conf     $CONFIG_DIR/Games/_common.conf

# WINE                  游戏运行器位置             必填   <runner>.conf
# PREFIX_VAR_NAME       PREFIX 存储变量名          选填   <runner>.conf   WINEPREFIX
# WINESERVER_KILL_CMD   WineServer 退出命令        选填   <runner>.conf   「命令不执行」
# PROTONPATH            umu 使用的 proton 位置     选填   <runner>.conf   「由 umu 决定，非 umu-run 启动则不适用」
# GAMEID                umu 的 umu-id              选填   <runner>.conf   umu-default「由 umu 决定，非 umu-run 启动则不适用」

# RUNNER                游戏的运行器               必填   <game>.conf
# GAME                  游戏本体位置               必填   <game>.conf
# GAME_PATH             游戏运行路径               选填   <game>.conf     $(dirname "$GAME")
# GAME_ARGS             游戏启动参数               选填   <game>.conf
# PREFIX                游戏运行的 PREFIX          选填   <game>.conf     「由 runner 决定」

# PROTON_TO_WINE_LINK         创建 Proton 前缀的软链接   选填   <g/c>.conf   <bool n>
# WINESERVER_KILL             游戏启动前运行杀死命令     选填   <g/c>.conf   <bool n>
# EXE_KILL                    游戏启动前杀死所有 exe     选填   <g/c>.conf   <bool n>
# MANGOHUD                    Wine 的包装 (mangohud)     选填   <g/c>.conf   <empty>
# GAMEMODE                    Wine 的包装 (gamemoderun)  选填   <g/c>.conf   <empty>
# TASKSET                     Wine 的包装 (taskset)      选填   <g/c>.conf   <empty>
# GAMESCOPE                   Wine 的包装 (gamescope)    选填   <g/c>.conf   <empty>
# GAMESCOPE_ARGS              Gamescope 启动参数         选填   <g/c>.conf   <array empty>
# INTEL_CPU_POWER_READ        Intel CPU 能耗文件可读     选填   <g/c>.conf   <bool n>
# INTEL_CPU_POWER_FILE        Intel CPU 能耗文件         选填   <g/c>.conf   <array /sys/class/powercap/intel-rapl:0/energy_uj>
# GL_SHADER_DISK_CACHE        NVIDIA 缓存 是否启用       选填   <g/c>.conf   <bool n>
# GL_SHADER_DISK_CACHE_PATH   NVIDIA 缓存 路径           选填   <g/c>.conf   $CACHE_DIR/GLShaderCache/$GAME_NAME
# DX_CACHE                    DXVK/VKD3D 缓存 是否启用   选填   <g/c>.conf   <bool n>
# DX_CACHE_PATH               DXVK/VKD3D 缓存 路径       选填   <g/c>.conf   $CACHE_DIR/DXCache/$GAME_NAME
# MANGOHUD_CONFIGFILE         MangoHud 配置文件位置      选填   <g/c>.conf   「由 MangoHud 决定，未启用 MangoHud 则不适用」

# PROTON_DLSS_UPGRADE         自动升级 DLSS 有关的 dll 文件         选填   <g/c>.conf   <bool n>
# PROTON_DLSS_VERSION         升级的 DLSS 版本                      选填   <g/c>.conf   <empty>
# PROTON_DLSS_INDICATOR       启用 DLSS 叠加层                      选填   <g/c>.conf   <bool n>
# PROTON_FSR4_UPGRADE         自动升级 FSR4 有关的 dll 文件         选填   <g/c>.conf   <bool n>
# PROTON_FSR4_VERSION         升级的 FSR4 版本                      选填   <g/c>.conf   <empty>
# PROTON_FSR4_INDICATOR       启用 FSR4 叠加层                      选填   <g/c>.conf   <bool n>
# PROTON_PREFER_SDL          【不知道 和手柄有关的 开了更好】       选填   <g/c>.conf   <bool n>
# NVIDIA_SMOOTH_MOTION        NVIDIA AI 插帧 (旧称 Smooth Motion)   选填   <g/c>.conf   <bool n>
# NVIDIA_REFLEX               NVIDIA Reflex 低延迟                  选填   <g/c>.conf   <bool n>

# HOSTNAME_STEAMDECK       伪装 Hostname                 选填   <game>.conf   <bool n>
# HOSTNAME_STEAMDECK_NAME  要伪装的 Hostname             选填   <game>.conf   STEAMDECK

# KILL_TARGET              游戏窗口关闭时杀死进程        选填   <game>.conf   <bool n>
# KILL_TARGET_PROCESS      KILL_TARGET 要杀死的进程      选必   <game>.conf

# XWIN_WATCH_WINDOW       XWIN_WATCH 要检测可窗口              选必   <g/c>.conf
# XWIN_WATCH_SLEEP        XWIN_WATCH 检测窗口出现的间隔 (秒)   选填   <g/c>.conf   5
# XWIN_WATCH_INTERVAL     XWIN_WATCH 检测窗口关闭的间隔 (秒)   选填   <g/c>.conf   $XWIN_WATCH_SLEEP
# XWIN_WATCH_ATTEMPTS     XWIN_WATCH 检测窗口出现尝试次数      选填   <g/c>.conf   20

# NETWORK_HOSTS            基于 Hosts 文件断网启动       选填   <game>.conf   <bool n>
# NETWORK_HOSTS_FILE       NETWORK_HOSTS 文件路径        选填   <game>.conf   /etc/hosts
# NETWORK_HOSTS_DURATION   NETWORK_HOSTS 断网时长 (秒)   选填   <game>.conf   -「填入 `-` 则代表调用 XWIN_WATCH 等待窗口出现」
# NETWOKR_HOSTS_CONTENT    NETWORK_HOSTS 断网规则        选必   <game>.conf
# NETWORK_HOSTS_REC_PERM   NETWORK_HOSTS 恢复文件权限    选填   <game>.conf   <bool y>
# NETWORK_HOSTS_ORI_PERM   NETWORK_HOSTS 文件原始权限    选填   <game>.conf   「默认修改前自动读取」

if [ "$UID" -eq 0 ]; then
    echo "你个小天才是怎么想到用 root 运行的（"
    exit 1
fi

[ -z "$GAME_NAME" ] && exit 1

[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT="$(dirname "$(realpath "$0")")/.."
cd "$PROJECT_ROOT"
[ -f "config.conf" ] && source config.conf

[ -z "$CONFIG_DIR" ] && CONFIG_DIR="${XDG_CONFIG_DIR:-$HOME/.config}/hypsc"
[ -z "$CACHE_DIR" ] && CACHE_DIR="${XDG_CACHE_DIR:-$HOME/.cache}/hypsc"
[ -z "$TEMP_DIR" ] && TEMP_DIR="/tmp/hypsc"

[ -e "$TEMP_DIR" ] && rm -r "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# 读取通用配置

[ -f "$CONFIG_DIR/config.conf" ] && source "$CONFIG_DIR/config.conf"

[ -z "$COMMON_GAME_CONF" ] && COMMON_GAME_CONF="$CONFIG_DIR/Games/_common.conf"
[ -f "$COMMON_GAME_CONF" ] && source "$COMMON_GAME_CONF"

# 读取游戏配置

GAME_CONF="$CONFIG_DIR/Games/$GAME_NAME.conf"
[ ! -f "$GAME_CONF" ] && exit 1
source "$GAME_CONF"

[ -z "$RUNNER" ] && exit 1
[ -z "$GAME" ] && exit 1
[ -z "$GAME_PATH" ] && GAME_PATH="$(dirname "$GAME")"

# 读取 RUNNER 配置

RUNNER_CONF="$CONFIG_DIR/Runners/$RUNNER.conf"
source "$RUNNER_CONF"

[ -z "$WINE" ] && exit 1
[ -z "$PREFIX_VAR_NAME" ] && PREFIX_VAR_NAME="WINEPREFIX"

# 配置 WINE

# 如果 $PREFIX 为空，就找 名为 $PREFIX_VAR_NAME 的值的变量，赋值过来做些操作
# $PREFIX_VAR_NAME 就是 Runner 中定义的 存储 PREFIX 路径 的变量名
# Wine 中 PREFIX_VAR_NAME=WINEPREFIX
# Proton 中 PREFIX_VAR_NAME=STEAM_COMPAT_DATA_PATH
if [ -z "$PREFIX" ] && [ -n "$PREFIX_VAR_NAME" ] && [ -n "${!PREFIX_VAR_NAME}" ]; then
    PREFIX="${!PREFIX_VAR_NAME}"
fi

if [ -n "$PREFIX" ]; then
    PREFIX="$(realpath "$PREFIX")"

    mkdir -p "$PREFIX"

    # 在 PREFIX 创建由 pfx 到 . 的软链接
    # 和一些判断的逻辑
    if [ "$PROTON_TO_WINE_LINK" = "y" ] && [ ! -L "$PREFIX/pfx" ]; then
        # 判断是否原有 pfx
        if [ -d "$PREFIX/pfx" ]; then
            # 判断是否原有 wineprefix
            if [ -d "$PREFIX/dosdevices" ]; then
                # 使用原有 wineprefix 而删除 pfx
                rm -rf "$PREFIX/pfx"
            else
                # 将原有的 pfx 移动到 原目录
                mv "$PREFIX/pfx" "$PREFIX"
            fi
        else
            mkdir -p "$PREFIX/pfx"
        fi
        # 创建链接
        ln -s . "$PREFIX/pfx"
    fi
fi

if [ -z "$PREFIX" ]; then
    if [ "$PROTON_TO_WINE_LINK" = "y" ]; then
        echo "自动选择 PREFIX 无法也无需开启 PROTON_TO_WINE_LINK"
    fi
fi

# 将 $PREFIX 的值 赋值给 名为 $PREFIX_VAR_NAME 的值的变量
# 我怎么感觉没这句注释更好理解呢?
[ -n "$PREFIX" ] && declare -x "$PREFIX_VAR_NAME=$PREFIX"

export "${PREFIX_VAR_NAME?}"

# is yes
isy() {
    if [ "$1" = "y" ] ||
       [ "$1" = "Y" ] ||
       [ "$1" = "yes" ] ||
       [ "$1" = "Yes" ] ||
       [ "$1" = "YES" ] ||
       [ "$1" = "1" ]
    then
        return 0
    else
        return 1
    fi
}

# 导出环境变量

# Wine
export WINEDLLOVERRIDES

# umu-launcher
export PROTONPATH
export GAMEID
export UMU_USE_STEAM

# MangoHud
export MANGOHUD_CONFIGFILE

# SteamDeck
export STEAMDECK
export SteamDeck
export SteamOS

# Steam
export WINE_ENABLE_STEAM_STUB
export STEAM_COMPAT_CLIENT_INSTALL_PATH

# DXVK NVAPI
export DXVK_NVAPI_DRS_SETTINGS
export DXVK_NVAPI_DRS_NGX_DLSS_SR_OVERRIDE_RENDER_PRESET_SELECTION
export DXVK_NVAPI_DRS_NGX_DLSSG_MULTI_FRAME_COUNT
export DXVK_NVAPI_SET_NGX_DEBUG_OPTIONS
export DXVK_NVAPI_GPU_ARCH


# PROTON DLSS UPGRADE
isy "$PROTON_DLSS_UPGRADE" && PROTON_DLSS_UPGRADE=1
[ -n "$PROTON_DLSS_VERSION" ] && PROTON_DLSS_UPGRADE="$PROTON_DLSS_VERSION"
export PROTON_DLSS_UPGRADE

# PROTON DLSS INDICATOR
isy "$PROTON_DLSS_INDICATOR" && PROTON_DLSS_INDICATOR=1
export PROTON_DLSS_INDICATOR

# PROTON FSR4 UPGRADE
isy "$PROTON_FSR4_UPGRADE" && PROTON_FSR4_UPGRADE=1
[ -n "$PROTON_FSR4_VERSION" ] && PROTON_FSR4_UPGRADE="$PROTON_FSR4_VERSION"
export PROTON_DLSS_UPGRADE

# PROTON FSR4 INDICATOR
isy "$PROTON_FSR4_INDICATOR" && PROTON_FSR4_INDICATOR=1
export PROTON_FSR4_INDICATOR

# NVIDIA REFLEX 低延迟
isy "$NVIDIA_REFLEX" && DXVK_NVAPI_VKREFLEX=1
export DXVK_NVAPI_VKREFLEX

# NVIDIA Smooth Motion
isy "$NVIDIA_SMOOTH_MOTION" && NVPRESENT_ENABLE_SMOOTH_MOTION=1
export NVPRESENT_ENABLE_SMOOTH_MOTION

# Proton 手柄问题
isy "$PROTON_PREFER_SDL" && PROTON_PREFER_SDL=1
export PROTON_PREFER_SDL

# Proton Wayland
isy "$PROTON_ENABLE_WAYLAND" && PROTON_ENABLE_WAYLAND=1
export PROTON_ENABLE_WAYLAND

# Proton HDR
isy "$PROTON_ENABLE_HDR" && PROTON_ENABLE_HDR=1
export PROTON_ENABLE_HDR

# Vulkan HDR WSI
isy "$ENABLE_HDR_WSI" && ENABLE_HDR_WSI=1
export ENABLE_HDR_WSI


# GL_SHADER_DISK_CACHE
if [ "$GL_SHADER_DISK_CACHE" = "y" ]; then
    [ -z "$GL_SHADER_DISK_CACHE_PATH" ] && GL_SHADER_DISK_CACHE_PATH="$CACHE_DIR/GLShaderCache/$GAME_NAME"
    mkdir -p "$GL_SHADER_DISK_CACHE_PATH"
    GL_SHADER_DISK_CACHE_PATH="$(realpath "$GL_SHADER_DISK_CACHE_PATH")"

    export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
    export __GL_SHADER_DISK_CACHE_PATH="$GL_SHADER_DISK_CACHE_PATH"
fi

# DX_CACHE
if [ "$DX_CACHE" = "y" ]; then
    [ -z "$DX_CACHE_PATH" ] && DX_CACHE_PATH="$CACHE_DIR/DXCache/$GAME_NAME"
    mkdir -p "$DX_CACHE_PATH"
    DX_CACHE_PATH="$(realpath "$DX_CACHE_PATH")"

    export DXVK_STATE_CACHE_PATH="$DX_CACHE_PATH"
    export VKD3D_SHADER_CACHE_PATH="$DX_CACHE_PATH"
fi

# Intel CPU 功率可供检测
if [ "$INTEL_CPU_POWER_READ" = "y" ]; then
    [ "${#INTEL_CPU_POWER_FILE[@]}" -lt 1 ] && INTEL_CPU_POWER_FILE+=("/sys/class/powercap/intel-rapl:0/energy_uj")

    for file in "${INTEL_CPU_POWER_FILE[@]}"; do
        if [ -f "$file" ] && [ ! -r "$file" ]; then
            echo "[sudo 请求] 使 Intel CPU 能量消耗可被所有人读取 需要 root 权限"
            sudo chmod a+r "$file"
        fi
    done
fi

# 伪装 Hostname 为 STEAMDECK
if [ "$HOSTNAME_STEAMDECK" = "y" ]; then
    [ -z "$HOSTNAME_STEAMDECK_NAME" ] && HOSTNAME_STEAMDECK_NAME="STEAMDECK"

    BEFORE_GAME="$(cat << EOF
$BEFORE_GAME
reg add HKLM\\System\\CurrentControlSet\\Control\\ComputerName\\ActiveComputerName /v ComputerName /t REG_SZ /d $HOSTNAME_STEAMDECK_NAME /f
reg add HKLM\\System\\CurrentControlSet\\Control\\ComputerName\\ComputerName /v ComputerName /t REG_SZ /d $HOSTNAME_STEAMDECK_NAME /f
EOF
    )"
fi

# Systemd Inhibit
# 隐藏的小功能 能用就用吧（
if [ "$SYSTEMD_INHIBIT" = "y" ]; then
    INHIBIT_WRAPPER="systemd-inhibit"

    [ -z "$SYSTEMD_INHIBIT_WHY" ] && SYSTEMD_INHIBIT_WHY="Game-Hyps $GAME_NAME"
    [ -z "$SYSTEMD_INHIBIT_WHAT" ] && SYSTEMD_INHIBIT_WHAT="idle:sleep"

    INHIBIT_WRAPPER="$INHIBIT_WRAPPER --why=$SYSTEMD_INHIBIT_WHY"
    INHIBIT_WRAPPER="$INHIBIT_WRAPPER --what=$SYSTEMD_INHIBIT_WHAT"

    WRAPPER_CMD="$INHIBIT_WRAPPER $WRAPPER_CMD"
fi

# Gamescope
if [ -n "$GAMESCOPE" ]; then
    if [ -n "$MANGOHUD" ]; then
        if [ "$MANGOHUD" = "mangohud" ]; then
            GAMESCOPE="$GAMESCOPE --mangohud"
            echo "[Hyps] 检测到 Gamescope 搭配 MangoHud 使用，换用 \`--mangohud\` 参数"
        else
            echo "[Hyps] WARN: Gamescope 与 MangoHud 不能同时使用！已关闭 MangoHud！"
        fi

        MANGOHUD=""
    fi

    if [ "${#GAMESCOPE_ARGS[@]}" -gt 0 ]; then
        GAMESCOPE="$GAMESCOPE ${GAMESCOPE_ARGS[*]}"
    fi
fi

# MangoHud / Gamemode
[ -n "$MANGOHUD" ] && WINE="$MANGOHUD $WINE"
[ -n "$TASKSET" ] && WINE="$TASKSET $WINE"
[ -n "$GAMEMODE" ] && WINE="$GAMEMODE $WINE"
[ -n "$GAMESCOPE" ] && WINE="$GAMESCOPE -- $WINE"

# Jadeite Patch
if [ -n "$JADEITE_PATH" ]; then
    GAME_EXE_PREFIX="$GAME_EXE_PREFIX \"Z:\\$JADEITE_PATH\""
    GAME_ARGS="$JADEITE_ARGS -- $GAME_ARGS"
elif [ "$FORCE_JADEITE" = "y" ]; then
    echo "[Hyps] 本游戏强制使用 Jadeite! 请填写 Jadeite 路径!"
    exit 1
fi

# Hosts 断网启动检测参数
if [ "$NETWORK_HOSTS" = "y" ]; then
    if [ -z "$NETWORK_HOSTS_CONTENT" ]; then
        echo "[Hyps] WARN: 检测到 Hosts 断网启动参数，请在 \$NETWORK_HOSTS_CONTENT 填写要在 Hosts 文件附加的内容！"
        exit 1
    fi
fi



set_executable() {
    local file="$1"

    if [ ! -x "$file" ]; then
        chmod +x "$file"
    fi

    if [ ! -x "$file" ]; then
        echo "[Hyps] ERROR: $file 不可执行！请手动设置可执行权限！"
        exit 1
    fi
}

check_cached_compile() {
    local var_name="$1"
    local bin_default="$2"
    local src_default="$3"
    local sha256_file_default="$4"

    local var_name_bin="$var_name"_BIN
    local var_name_src="$var_name"_SRC
    local var_name_sha256_file="$var_name"_SHA256_FILE

    local bin_file="${!var_name_bin:=$bin_default}"
    local src_file="${!var_name_src:=$src_default}"
    local sha256_file="${!var_name_sha256_file:=$sha256_file_default}"

    bin_file="$(realpath "$bin_file")"
    src_file="$(realpath "$src_file")"
    sha256_file="$(realpath "$sha256_file")"

    declare -g "$var_name_bin=$bin_file"
    declare -g "$var_name_src=$src_file"
    declare -g "$var_name_sha256_file=$sha256_file"

    # 判断是否需要重新编译
    if [ -f "$bin_file" ] && [ -f "$src_file" ] && [ -f "$sha256_file" ]; then 
        # 读取先前的 sha256
        local cached_sha256
        cached_sha256="$(cat "$sha256_file")"
        # 计算源文件的 sha256
        local src_sha256
        src_sha256="$(sha256sum "$src_file" | awk '{print $1}')"
        # 如果不一致，则删除二进制，重新编译
        if [ "$cached_sha256" != "$src_sha256" ]; then
            rm -f "$bin_file"
        fi
    fi

    if [ -f "$bin_file" ] && [ -f "$src_file" ] && [ ! -f "$sha256_file" ]; then 
        rm -f "$bin_file"
    fi
}



# 哪些要用到 XWin Watch
[ "$KILL_TARGET" = "y" ] && XWIN_WATCH="y"

if [ "$NETWORK_HOSTS" = "y" ]; then
    if [ -z "$NETWORK_HOSTS_DURATION" ] || [ "$NETWORK_HOSTS_DURATION" = "-" ]; then
        XWIN_WATCH="y"
    fi 
fi

# XWin Watch
if [ "$XWIN_WATCH" = "y" ]; then
    [ -z "$XWIN_WATCH_PATH" ] && XWIN_WATCH_PATH="./Tools/xwin-watch"

    check_cached_compile "XWIN_WATCH" \
        "$XWIN_WATCH_PATH/xwin-watch" \
        "$XWIN_WATCH_PATH/xwin-watch.c" \
        "$CACHE_DIR/xwin-watch.c.sha256"
    
    if [ -z "$XWIN_WATCH_WINDOW" ]; then
        echo "[xwin-watch] 缺少要监测的窗口名称"
        exit 1
    fi

    # 如果程序不存在 但源文件存在 则尝试编译
    if [ ! -f "$XWIN_WATCH_BIN" ] && [ -f "$XWIN_WATCH_SRC" ]; then
        echo "[xwin-watch] 编译 $XWIN_WATCH_SRC"
        gcc "$XWIN_WATCH_SRC" -o "$XWIN_WATCH_BIN" -lX11
    fi

    if [ ! -f "$XWIN_WATCH_BIN" ]; then
        echo "[xwin-watch] 编译失败或源文件不存在"
        exit 1
    else
        sha256sum "$XWIN_WATCH_SRC" | awk '{print $1}' > "$XWIN_WATCH_SHA256_FILE"
    fi

    # 确保可执行
    set_executable "$XWIN_WATCH_BIN"

    [ -z "$XWIN_WATCH_SLEEP" ] && XWIN_WATCH_SLEEP="5"
    [ -z "$XWIN_WATCH_INTERVAL" ] && XWIN_WATCH_INTERVAL="$XWIN_WATCH_SLEEP"
    [ -z "$XWIN_WATCH_ATTEMPTS" ] && XWIN_WATCH_ATTEMPTS="20"

    if [[ "$XWIN_WATCH_SLEEP" =~ [^0-9] ]]; then
        echo "[xwin-watch] 错误: XWIN_WATCH_SLEEP 必须为数字"
        exit 1
    fi

    XWIN_WATCH_CMD="$XWIN_WATCH_BIN -w $XWIN_WATCH_WINDOW -s $XWIN_WATCH_SLEEP"

    [[ "$XWIN_WATCH_ATTEMPTS" =~ ^[0-9]+$ ]] && XWIN_WATCH_CMD="$XWIN_WATCH_CMD -a $XWIN_WATCH_ATTEMPTS"
    [[ "$XWIN_WATCH_INTERVAL" =~ ^[0-9]+$ ]] && XWIN_WATCH_CMD="$XWIN_WATCH_CMD -i $XWIN_WATCH_INTERVAL"
fi

# Kill Target
if [ "$KILL_TARGET" = "y" ]; then
    XWIN_WATCH_ON_CLOSED="$(cat << EOF
$XWIN_WATCH_ON_CLOSED
killall $KILL_TARGET_PROCESS
EOF
    )"
fi

trap cleanup SIGTERM
trap cleanup SIGINT

cleanup() {
    # TODO
    echo "[Hyps] 终止"
    exit
}



gen_script() {
    # 创建临时的 bat 文件用于启动
    TEMP_SCRIPT="$TEMP_DIR/start.bat"
    SCRIPT_CONTENT="$(cat << EOF
Z:
$BEFORE_GAME

cd "$GAME_PATH"
start "" $GAME_EXE_PREFIX "Z:\\$GAME" $GAME_ARGS

$AFTER_GAME

:: del "%~f0" && exit
EOF
    )"
    echo -n "$SCRIPT_CONTENT" > "$TEMP_SCRIPT"
}



run_prepare() {
    # 准备启动
    [ "$WINESERVER_KILL" = "y" ] && [ -n "$WINESERVER_KILL_CMD" ] && $WINESERVER_KILL_CMD
    [ "$EXE_KILL" = "y" ] && pkill -f "\.exe"

    # Hosts 断网
    if [ "$NETWORK_HOSTS" = "y" ] && [ -n "$NETWORK_HOSTS_CONTENT" ]; then
        [ -z "$NETWORK_HOSTS_FILE" ] && NETWORK_HOSTS_FILE="/etc/hosts"
        [ -z "$NETWORK_HOSTS_DURATION" ] && NETWORK_HOSTS_DURATION="-"
        [ -z "$NETWORK_HOSTS_REC_PREM" ] && NETWORK_HOSTS_REC_PREM="y"
        NETWORK_HOSTS_FILE="$(realpath "$NETWORK_HOSTS_FILE")"

        if [ -f "$NETWORK_HOSTS_FILE" ]; then
            if [ ! -w "$NETWORK_HOSTS_FILE" ]; then
                [ "$NETWORK_HOSTS_REC_PREM" = "y" ] && [ -z "$NETWORK_HOSTS_ORI_PERM" ] && NETWORK_HOSTS_ORI_PERM=$(stat -c "%a" "$HOSTS_FILE")

                echo "[sudo 请求] 使 hosts 文件可被写入 需要 root 权限"
                sudo chmod a+w "$NETWORK_HOSTS_FILE"
            fi

            [ -z "$NETWORK_HOSTS_FLAG" ] && NETWORK_HOSTS_FLAG="Hyps Gaming Network Hosts"
            local flagStart="# $NETWORK_HOSTS_FLAG $GAME_NAME Start"
            local flagEnd="# $NETWORK_HOSTS_FLAG $GAME_NAME End"

            NETWORK_HOSTS_CONTENT="""
$flagStart
$NETWORK_HOSTS_CONTENT
$flagEnd
"""
            cat "$NETWORK_HOSTS_FILE" > "$TEMP_DIR/hosts"
            echo -n "$NETWORK_HOSTS_CONTENT" >> "$NETWORK_HOSTS_FILE"

            NETWORK_HOSTS_REC_CMD="$(cat << EOF
echo "[\$(date +%H:%M:%S)] 恢复 Hosts"

cat "$TEMP_DIR/hosts" > "$NETWORK_HOSTS_FILE"

if [ "$NETWORK_HOSTS_REC_PREM" = "y" ] && [ -n "$NETWORK_HOSTS_ORI_PERM" ]; then
    echo "[sudo 请求] 恢复 hosts 文件权限 需要 root 权限"
    sudo chmod "$NETWORK_HOSTS_ORI_PERM" "$NETWORK_HOSTS_FILE"
fi
EOF
            )"

            if [ "$NETWORK_HOSTS_DURATION" != "-" ]; then
                (
                    # 后台运行部分
                    sleep "$NETWORK_HOSTS_DURATION"
                    eval "$NETWORK_HOSTS_REC_CMD"
                ) &
                BACKGROUND_PID+=("$!")
            else
                # 调用 XWin Watch
                XWIN_WATCH_ON_EXISTS="$(cat << EOF
$XWIN_WATCH_ON_EXISTS
$NETWORK_HOSTS_REC_CMD
EOF
                )"
            fi
        fi
    fi

    # XWin Watch 窗口监测程序
    if [ "$XWIN_WATCH" = "y" ]; then
        if [ -n "$XWIN_WATCH_ON_EXISTS" ]; then
            TEMP_WIN_EXISTS="$TEMP_DIR/win-exists.sh"
            echo "$XWIN_WATCH_ON_EXISTS" > "$TEMP_WIN_EXISTS"
            set_executable "$TEMP_WIN_EXISTS"
            XWIN_WATCH_CMD="$XWIN_WATCH_CMD -e \"$TEMP_WIN_EXISTS\""
        fi

        if [ -n "$XWIN_WATCH_ON_CLOSED" ]; then
            TEMP_WIN_CLOSED="$TEMP_DIR/win-closed.sh"
            echo "$XWIN_WATCH_ON_CLOSED" > "$TEMP_WIN_CLOSED"
            set_executable "$TEMP_WIN_CLOSED"
            XWIN_WATCH_CMD="$XWIN_WATCH_CMD -c \"$TEMP_WIN_CLOSED\""
        fi

        ( eval "$XWIN_WATCH_CMD" ) &
        BACKGROUND_PID+=("$!")
    fi
}



start_game() {
    WIN_EXECUTABLE=""

    if [ "$SKIP_SCRIPT" = "y" ]; then
        WIN_EXECUTABLE="$GAME"
    else
        gen_script
        WIN_EXECUTABLE="$TEMP_SCRIPT"
    fi
    
    run_prepare

    cd "$GAME_PATH"

    eval $WRAPPER_CMD $WINE "$WIN_EXECUTABLE" &
    BACKGROUND_PID+=("$!")

    wait

    cleanup
}
