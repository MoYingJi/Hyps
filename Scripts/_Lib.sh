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
# PREFIX                游戏运行的 PREIFX          选填   <game>.conf     「由 runner 决定」
# MANGOHUD_CONFIGFILE   MangoHud 配置文件位置      选填   <game>.conf     「由 MangoHud 决定，未启用 MangoHud 则不适用」

# PROTON_TO_WINE_LINK         创建 Proton 前缀的软链接   选填   <g/c>.conf   <bool n>
# WINESERVER_KILL             游戏启动前运行杀死命令     选填   <g/c>.conf   <bool n>
# EXE_KILL                    游戏启动前杀死所有 exe     选填   <g/c>.conf   <bool n>
# MANGOHUD                    Wine 的包装 (mangohud)     选填   <g/c>.conf   <empty>
# GAMEMODE                    Wine 的包装 (gamemoderun)  选填   <g/c>.conf   <empty>
# TASKSET                     Wine 的包装 (taskset)      选填   <g/c>.conf   <empty>
# INTEL_CPU_POWER_READ        Intel CPU 能耗文件均可读   选填   <g/c>.conf   <bool n>
# GL_SHADER_DISK_CACHE        NVIDIA 缓存 是否启用       选填   <g/c>.conf   <bool n>
# GL_SHADER_DISK_CACHE_PATH   NVIDIA 缓存 路径           选填   <g/c>.conf   $CACHE_DIR/GLShaderCache/$GAME_NAME
# DX_CACHE                    DXVK/VKD3D 缓存 是否启用   选填   <g/c>.conf   <bool n>
# DX_CACHE_PATH               DXVK/VKD3D 缓存 路径       选填   <g/c>.conf   $CACHE_DIR/DXCache/$GAME_NAME
# NVIDIA_SMOOTH_MOTION        NVIDIA Smooth Motion       选填   <g/c>.conf   <bool n>

# HOSTNAME_STEAMDECK       伪装 Hostname                 选填   <game>.conf   <bool n>
# HOSTNAME_STEAMDECK_NAME  要伪装的 Hostname             选填   <game>.conf   STEAMDECK

# NETWORK_DROP             基于 systemd-run 的断网启动   选填   <game>.conf   <bool n>
# NETWORK_DROP_DURATION    NETWORK_DROP 断网时长 (秒)    选填   <game>.conf   5
# NETWORK_DROP_TABLE       NETWORK_DROP 断网管理类型     选填   <game>.conf   iptables「可选 iptables / nftables」
# NETWORK_DROP_SLICE       NETWORK_DROP 游戏所在 slice   选填   <game>.conf   game_$GAME_NAME
# NETWORK_DROP_NAME        NETWORK_DROP nft 表名称       选填   <game>.conf   $NETWORK_DROP_SLICE

# NETWORK_HOSTS            基于 Hosts 文件断网启动       选填   <game>.conf   <bool n>
# NETWORK_HOSTS_FILE       NETWORK_HOSTS 文件路径        选填   <game>.conf   /etc/hosts
# NETWORK_HOSTS_DURATION   NETWORK_HOSTS 断网时长 (秒)   选填   <game>.conf   5
# NETWOKR_HOSTS_CONTENT    NETWORK_HOSTS 断网规则        选必   <game>.conf
# NETWORK_HOSTS_REC_PERM   NETWORK_HOSTS 恢复文件权限    选填   <game>.conf   <bool t>
# NETWORK_HOSTS_ORI_PERM   NETWORK_HOSTS 文件原始权限    选填   <game>.conf   「默认修改前自动读取」

# NETWORK_NMCLI            Network Manager 断网启动      选填   <game>.conf   <bool n>
# NETWORK_NMCLI_DURATION   NETWORK_NMCLI 断网时长 (秒)   选填   <game>.conf   5


[ -z "$GAME_NAME" ] && exit 1

cd "$(dirname "$(realpath "$0")")/.."
[ -f "config.conf" ] && source config.conf

[ -z "$CONFIG_DIR" ] && CONFIG_DIR="${XDG_CONFIG_DIR:-$HOME/.config}/hypsc"
[ -z "$CACHE_DIR" ] && CACHE_DIR="${XDG_CACHE_DIR:-$HOME/.cache}/hypsc"

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
    fi
    # 创建链接
    ln -s . "$PREFIX/pfx"
fi

# 将 $PREFIX 的值 赋值给 名为 $PREFIX_VAR_NAME 的值的变量
# 我怎么感觉没这句注释更好理解呢?
[ -n "$PREFIX" ] && declare -x "$PREFIX_VAR_NAME=$PREFIX"

export "${PREFIX_VAR_NAME?}"

# 导出环境变量

# umu-launcher
export PROTONPATH
export GAMEID

# MangoHud
export MANGOHUD_CONFIGFILE


# NVIDIA Smooth Motion
[ "$NVIDIA_SMOOTH_MOTION" = "y" ] && NVPRESENT_ENABLE_SMOOTH_MOTION=1
export NVPRESENT_ENABLE_SMOOTH_MOTION

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

# MangoHud Intel CPU Power
if [ "$INTEL_CPU_POWER_READ" = "y" ]; then
    [ -z "$INTEL_CPU_POWER_FILE" ] && INTEL_CPU_POWER_FILE="/sys/class/powercap/intel-rapl\:0/energy_uj"

    if [ -f "$INTEL_CPU_POWER_FILE" ] && [ ! -r "$INTEL_CPU_POWER_FILE" ]; then
        echo "[sudo 请求] 使 Intel CPU 能量消耗可被所有人读取 需要 root 权限"
        sudo chmod a+r "$INTEL_CPU_POWER_FILE"
    fi
fi

# 准备启动

[ "$WINESERVER_KILL" = "y" ] && [ -n "$WINESERVER_KILL_CMD" ] && $WINESERVER_KILL_CMD
[ "$EXE_KILL" = "y" ] && pkill -f "\.exe"


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

# MangoHud / Gamemode
[ -n "$MANGOHUD" ] && WINE="$MANGOHUD $WINE"
[ -n "$TASKSET" ] && WINE="$TASKSET $WINE"
[ -n "$GAMEMODE" ] && WINE="$GAMEMODE $WINE"

# Jadeite Patch
if [ -n "$JADEITE_PATH" ]; then
    GAME_EXE_PREFIX="$GAME_EXE_PREFIX \"Z:\\$JADEITE_PATH\""
elif [ "$FORCE_JADEITE" = "y" ]; then
    echo "本游戏强制使用 Jadeite! 请填写 Jadeite 路径!"
    exit 1
fi



start_game() {
    # 创建临时的 bat 文件用于启动
    TEMP_SCRIPT="$(mktemp --suffix=.bat)"
    SCRIPT_CONTENT="$(cat << EOF
Z:
$BEFORE_GAME

cd "$GAME_PATH"
start "" $GAME_EXE_PREFIX "Z:\\$GAME"

$AFTER_GAME

del "%~f0" && exit
EOF
    )"
    echo -n "$SCRIPT_CONTENT" > "$TEMP_SCRIPT"

    cd "$GAME_PATH"

    # Hosts 断网
    if [ "$NETWORK_HOSTS" = "y" ] && [ -n "$NETWORK_HOSTS_CONTENT" ]; then
        [ -z "$NETWORK_HOSTS_FILE" ] && NETWORK_HOSTS_FILE="/etc/hosts"
        [ -z "$NETWORK_HOSTS_DURATION" ] && NETWORK_HOSTS_DURATION="5"
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
            echo -n "$NETWORK_HOSTS_CONTENT" >> "$NETWORK_HOSTS_FILE"

            ( # 后台运行部分 指定时间后删除内容
                sleep "$NETWORK_HOSTS_DURATION"

                local tempHosts
                tempHosts="$(sed "/^$flagStart/,/^$flagEnd/d" "$NETWORK_HOSTS_FILE")"
                echo -n "$tempHosts" > "$NETWORK_HOSTS_FILE"

                if [ "$NETWORK_HOSTS_REC_PREM" = "y" ] && [ -n "$NETWORK_HOSTS_ORI_PERM" ]; then
                    echo "[sudo 请求] 恢复 hosts 文件权限 需要 root 权限"
                    sudo chmod "$NETWORK_HOSTS_ORI_PERM" "$NETWORK_HOSTS_FILE"
                fi
            ) &
        fi
    fi

    # nmcli 断网
    if [ "$NETWORK_NMCLI" = "y" ]; then
        [ -z "$NETWORK_NMCLI_DURATION" ] && NETWORK_NMCLI_DURATION="5"
        nmcli n off
        (
            sleep "$NETWORK_NMCLI_DURATION"
            nmcli n on
        ) &
    fi

    # Systemd-run 断网
    if [ "$NETWORK_DROP" = "y" ]; then
        [ -z "$NETWORK_DROP_DURATION" ] && NETWORK_DROP_DURATION="5"
        [ -z "$NETWORK_DROP_UID" ] && NETWORK_DROP_UID="$(id -u)"
        [ -z "$NETWORK_DROP_SLICE" ] && NETWORK_DROP_SLICE="game_$GAME_NAME"
        [ -z "$NETWORK_DROP_UNIT" ] && NETWORK_DROP_UNIT="game_$GAME_NAME"
        [ -z "$NETWORK_DROP_TABLE" ] && NETWORK_DROP_TABLE="iptables"

        NETWORK_DROP_SLICE_PATH="user.slice/user-$NETWORK_DROP_UID.slice/user@$NETWORK_DROP_UID.service/$NETWORK_DROP_SLICE.slice"

        if [ "$NETWORK_DROP_TABLE" = "iptables" ]; then

            NETWORK_DROP_RULE="OUTPUT -p all -m cgroup --path /$NETWORK_DROP_SLICE_PATH -j DROP"

            NETWORK_DROP_RULE_ADD="iptables -A $NETWORK_DROP_RULE"
            NETWORK_DROP_RULE_DEL="iptables -D $NETWORK_DROP_RULE"

        elif [ "$NETWORK_DROP_TABLE" = "nftables" ]; then

            [ -z "$NETWORK_DROP_NAME" ] && NETWORK_DROP_NAME="$NETWORK_DROP_SLICE"

            NETWORK_DROP_RULE_ADD="""
                nft -f - << NFT
table inet $NETWORK_DROP_NAME {
    chain output {
        type filter hook output priority 0;
        socket cgroupv2 level 4 \"$NETWORK_DROP_SLICE_PATH\" counter drop
    }
}
NFT"""
            NETWORK_DROP_RULE_DEL="nft destroy table inet $NETWORK_DROP_NAME"
        fi

        echo "[sudo 请求] 启用网络丢包 需要 root 权限"
        sudo -v
        $WRAPPER_CMD systemd-run --user --scope --slice="$NETWORK_DROP_SLICE" --unit="$NETWORK_DROP_UNIT" $WINE "$TEMP_SCRIPT" & sudo sh -c """
            $NETWORK_DROP_RULE_ADD
            sleep $NETWORK_DROP_DURATION
            $NETWORK_DROP_RULE_DEL
        """
    else
        # 正常启动 不启用网络丢包
        $WRAPPER_CMD $WINE "$TEMP_SCRIPT"
    fi

    wait
}
