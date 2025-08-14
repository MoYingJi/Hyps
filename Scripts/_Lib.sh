#!/hint/bash
#shellcheck disable=1090,1091,2086,2164

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

if [ -n "$PREFIX" ]; then
    mkdir -p "$PREFIX"
elif [ -n "$PREFIX_VAR_NAME" ] && [ -n "${!PREFIX_VAR_NAME}" ]; then
    mkdir -p "${!PREFIX_VAR_NAME}"
fi

# 在 PREFIX 创建由 pfx 到 . 的软链接
# 和一些判断的逻辑
if [ "$PROTON_TO_WINE_LINK" == "y" ]; then
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

[ -n "$PREFIX" ] && declare -x "$PREFIX_VAR_NAME=$PREFIX"

export "${PREFIX_VAR_NAME?}"



# 准备启动

[ "$WINESERVER_KILL" == "y" ] && $WINESERVER -k
[ "$EXE_KILL" == "y" ] && pkill -f "\.exe"

# 伪装 Hostname 为 STEAMDESK
if [ "$HOSTNAME_STEAMDECK" = "y" ]; then
    BEFORE_GAME="$(cat << EOF
$BEFORE_GAME
reg add HKLM\\System\\CurrentControlSet\\Control\\ComputerName\\ActiveComputerName /v ComputerName /t REG_SZ /d STEAMDECK /f
reg add HKLM\\System\\CurrentControlSet\\Control\\ComputerName\\ComputerName /v ComputerName /t REG_SZ /d STEAMDECK /f
EOF
    )"
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

        if [ "$NETWORK_TABLES" == "iptables" ]; then

            NETWORK_DROP_SLICE_PATH="/user.slice/user-$NETWORK_DROP_UID.slice/user@$NETWORK_DROP_UID.service/$NETWORK_DROP_SLICE.slice"
            NETWORK_DROP_RULE="OUTPUT -p all -m cgroup --path $NETWORK_DROP_SLICE_PATH -j DROP"

            NETWORK_DROP_RULE_ADD="iptables -A $NETWORK_DROP_RULE"
            NETWORK_DROP_RULE_DEL="iptables -D $NETWORK_DROP_RULE"

        elif [ "$NETWORK_TABLES" == "nftables" ]; then
            echo "nftables 暂不支持"
            echo "需要使用 iptables-nft 然后使用 iptables 规则"
        fi

        echo "启用网络丢包需要 root 权限"
        sudo -v
        systemd-run --user --scope --slice="$NETWORK_DROP_SLICE" --unit="$NETWORK_DROP_UNIT" $WINE "$TEMP_SCRIPT" & sudo sh -c """
            $NETWORK_DROP_RULE_ADD
            sleep $NETWORK_DROP_DURATION
            $NETWORK_DROP_RULE_DEL
        """
    else
        $WINE "$TEMP_SCRIPT"
    fi

    wait
}
