#!/hint/bash
#shellcheck disable=1090,1091,2086,2164
# ↑ shellcheck: 我不如烂这算了

# 神秘小脚本

# 神秘小脚本内所使用的都是全局变量，且对于 conf 文件都是直接 source
# 所以在 conf 文件中添加其他变量可能会造成奇奇怪怪的效果

[ -z "$GAME_NAME" ] && exit 1

cd "$(dirname "$(realpath "$0")")/.."
[ -f "config.conf" ] && source config.conf

[ -z "$CONFIG_DIR" ] && CONFIG_DIR="${XDG_CONFIG_DIR:-$HOME/.config}/hypsc"
[ -z "$CACHE_DIR" ] && CACHE_DIR="${XDG_CACHE_DIR:-$HOME/.cache}/hypsc"

# 读取通用配置

COMMON_GAME_CONF="$CONFIG_DIR/Games/_common.conf"
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
if [ "$PROTON_TO_WINE_LINK" == "y" ] && [ ! -L "$PREFIX/pfx" ]; then
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
    INTEL_CPU_POWER_FILE="/sys/class/powercap/intel-rapl\:0/energy_uj"

    if [ -f "$INTEL_CPU_POWER_FILE" ] && [ ! -r "$INTEL_CPU_POWER_FILE" ]; then
        echo "[sudo 请求] 使 Intel CPU 能量消耗可被所有人读取 需要 root 权限"
        sudo chmod a+r "$INTEL_CPU_POWER_FILE"
    fi
fi

# 准备启动

[ "$WINESERVER_KILL" == "y" ] && [ -n "$WINESERVER_KILL_CMD" ] && $WINESERVER_KILL_CMD
[ "$EXE_KILL" == "y" ] && pkill -f "\.exe"


# 伪装 Hostname 为 STEAMDESK
if [ "$HOSTNAME_STEAMDECK" = "y" ]; then
    [ -z "$HOSTNAME_STEAMDECK_NAME" ] && HOSTNAME_STEAMDECK_NAME="STEAMDESK"

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

    if [ "$NETWORK_DROP" = "y" ]; then
        [ -z "$NETWORK_DROP_DURATION" ] && NETWORK_DROP_DURATION="5"
        [ -z "$NETWORK_DROP_UID" ] && NETWORK_DROP_UID="$(id -u)"
        [ -z "$NETWORK_DROP_SLICE" ] && NETWORK_DROP_SLICE="game_$GAME_NAME"
        [ -z "$NETWORK_DROP_UNIT" ] && NETWORK_DROP_UNIT="game_$GAME_NAME"
        [ -z "$NETWORK_DROP_TABLE" ] && NETWORK_DROP_TABLE="iptables"

        NETWORK_DROP_SLICE_PATH="user.slice/user-$NETWORK_DROP_UID.slice/user@$NETWORK_DROP_UID.service/$NETWORK_DROP_SLICE.slice"

        if [ "$NETWORK_DROP_TABLE" == "iptables" ]; then

            NETWORK_DROP_RULE="OUTPUT -p all -m cgroup --path /$NETWORK_DROP_SLICE_PATH -j DROP"

            NETWORK_DROP_RULE_ADD="iptables -A $NETWORK_DROP_RULE"
            NETWORK_DROP_RULE_DEL="iptables -D $NETWORK_DROP_RULE"

        elif [ "$NETWORK_DROP_TABLE" == "nftables" ]; then

            NETWORK_DROP_NAME="$NETWORK_DROP_SLICE"

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
