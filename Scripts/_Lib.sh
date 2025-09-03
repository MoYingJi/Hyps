#!/hint/bash
#shellcheck disable=1090,1091,2086,2164
# ↑ shellcheck: 我不如烂这算了

# 神秘小脚本

# 神秘小脚本内所使用的都是全局变量，且对于 conf 文件都是直接 source
# 所以在 conf 文件中添加其他变量可能会造成奇奇怪怪的效果

[ -z "$GAME_NAME" ] && exit 1

cd "$(dirname "$(realpath "$0")")/.."
source config.conf

[ -z "$CONFIG_DIR" ] && CONFIG_DIR="${XDG_CONFIG_DIR:-$HOME/.config/hypsc}"

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
[ -z "$WINESERVER" ] && exit 1
[ -z "$PREFIX_VAR_NAME" ] && PREFIX_VAR_NAME="WINEPREFIX"

# 配置 WINE

[ -n "$MANGO_HUD" ] && WINE="$MANGO_HUD $WINE"
[ -n "$GAMEMODE" ] && WINE="$GAMEMODE $WINE"

# 如果 $PREFIX 为空，就找 名为 $PREFIX_VAR_NAME 的值的变量，赋值过来做些操作
# $PREFIX_VAR_NAME 就是 Runner 中定义的 存储 PREFIX 路径 的变量名
# Wine 中 PREFIX_VAR_NAME=WINEPREFIX
# Proton 中 PREFIX_VAR_NAME=STEAM_COMPAT_DATA_PATH
if [ -z "$PREFIX" ] && [ -n "$PREFIX_VAR_NAME" ] && [ -n "${!PREFIX_VAR_NAME}" ]; then
    PREFIX="${!PREFIX_VAR_NAME}"
fi

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



# 准备启动

[ "$WINESERVER_KILL" == "y" ] && $WINESERVER -k
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

        echo "启用网络丢包需要 root 权限"
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
