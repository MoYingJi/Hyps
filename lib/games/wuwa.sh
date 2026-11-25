#!/hint/bash
#shellcheck disable=SC2034 # 游戏元数据由通用模块读取

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

# 游戏元数据

GAME_DISPLAY_NAME="鸣潮"
GAME_PATH_NAME="WutheringWaves"
GAME_DAILY_RESET="04:00 Asia/Shanghai"

# 游戏安装根与可执行文件

game_install_dir() {
    local game_exe="$1"
    local game_dir
    case "$game_exe" in
        */"Wuthering Waves.exe")
            path_dirname "$game_exe" game_dir
            printf '%s\n' "$game_dir"
            ;;
        */"Client/Binaries/Win64/Client-Win64-Shipping.exe")
            realpath -m "$game_exe/../../../.."
            ;;
        *)
            log_error game-fs "无法识别游戏路径: $game_exe"
            return 1
            ;;
    esac
}

game_executable() {
    local install_dir="$1"
    printf '%s\n' "$install_dir/Client/Binaries/Win64/Client-Win64-Shipping.exe"
}

# 游戏路径声明

game_paths() {
    path_plan_declare userdata:screenshot runtime "Client/Saved/ScreenShot"
    path_plan_declare shader-cache all "Client/Saved/PSO"
}

# 游戏版本
#
# 本地版本取启动器大版本，不含游戏内热更资源版本
# 热更版本在 Client/Saved/Resources/<大版本>/ 下，由游戏自身维护，不经过启动器，不能用于版本比较

# 各渠道版本清单，token 来自 KRApp.conf，属稳定公开值，硬编码以免依赖启动器安装目录
WUWA_INDEX_URL_CN="https://prod-cn-alicdn-gamestarter.kurogame.com/launcher/game/10003_oLNgHF1CESo51DGHN2odtp40e3oI1HfZ/G152/official/index.json"
WUWA_INDEX_URL_BILIBILI="https://prod-cn-alicdn-gamestarter.kurogame.com/launcher/game/10004_IY6xmlAusbImBjWrpPj1OwNuirXEO44x/G152/bilibili/index.json"
WUWA_INDEX_URL_GLOBAL="https://prod-alicdn-gamestarter.kurogame.com/launcher/game/G153/50004_obOHXFrFanqsaIEOmuKroCcbZkQRBC7c/index.json"

# 输出 SDK 配置路径，未找到返回 1
wuwa_sdk_config_path() {
    local install_dir="$1"
    local file
    for file in "$install_dir"/Client/Binaries/Win64/ThirdParty/KrPcSdk_*/KRSDKRes/KRSDKConfig.json; do
        if [ -f "$file" ]; then
            printf '%s\n' "$file"
            return 0
        fi
    done
    return 1
}

# 用法: game_version_local <game_exe> <version_nameref> <variant_nameref> <context_nameref>
game_version_local() {
    local game_exe="$1"
    local -n _version="$2"
    local -n _variant="$3"
    local -n _context="$4"

    local install_dir
    if ! install_dir="$(game_install_dir "$game_exe")"; then
        return 1
    fi
    if ! command_exists jq; then
        log_error wuwa "查询鸣潮版本需要 jq"
        return 1
    fi

    local root_config="$install_dir/launcherDownloadConfig.json"
    local common_config="$install_dir/launcherDownloadConfig/common.json"

    # 优先 common 包版本，其次根配置的大版本，最后退回 SDK 配置的游戏版本
    local version="" sdk_config
    if [ -f "$common_config" ]; then
        version="$(jq -r '.version // ""' "$common_config" 2>/dev/null)"
    fi
    if [ -z "$version" ] && [ -f "$root_config" ]; then
        version="$(jq -r '.version // ""' "$root_config" 2>/dev/null)"
    fi
    if [ -z "$version" ] && [ -f "$root_config" ]; then
        version="$(jq -r '(.bundles // {}) | to_entries | .[0].value.version // ""' "$root_config" 2>/dev/null)"
    fi
    if [ -z "$version" ] && sdk_config="$(wuwa_sdk_config_path "$install_dir")"; then
        version="$(jq -r '.KR_GameVersion // ""' "$sdk_config" 2>/dev/null)"
    fi

    if [ -z "$version" ]; then
        log_error wuwa "无法读取鸣潮本地版本: $install_dir"
        return 1
    fi

    # 渠道由根配置的 appId 判定，10003 国服、10004 B 服、50004 国际服
    local app_id="" variant=""
    if [ -f "$root_config" ]; then
        app_id="$(jq -r '.appId // ""' "$root_config" 2>/dev/null)"
    fi
    case "$app_id" in
        10003) variant="cn" ;;
        10004) variant="bilibili" ;;
        50004) variant="global" ;;
        "")    variant="" ;;
        *)     log_warn wuwa "无法识别的鸣潮渠道: appId='$app_id'"; variant="" ;;
    esac

    _version="$version"
    _variant="$variant"
    _context=""
}

# 用法: game_version_remote <variant> <context> <remote_nameref> <predownload_nameref>
game_version_remote() {
    local variant="$1"
    local -n _remote_version="$3"
    local -n _predownload_version="$4"

    local url
    case "$variant" in
        cn)       url="$WUWA_INDEX_URL_CN" ;;
        bilibili) url="$WUWA_INDEX_URL_BILIBILI" ;;
        global)   url="$WUWA_INDEX_URL_GLOBAL" ;;
        *)
            log_error wuwa "无法确定鸣潮版本接口: variant='$variant'"
            return 1
            ;;
    esac
    if ! command_exists curl || ! command_exists jq; then
        log_error wuwa "查询鸣潮版本需要 curl 和 jq"
        return 1
    fi

    # 接口强制 gzip，必须 --compressed
    local raw
    if ! raw="$(curl -fsS --compressed "$url")"; then
        log_error wuwa "无法请求版本接口: $url"
        return 1
    fi

    # 3.8 起为 resourcePacks 结构，旧格式为 default.config，兼容两者
    # 预下载在同构的 predownload 块里，缺失或为 null 时视为未开放
    local fields version predownload
    if ! fields="$(jq -r '
        def pick($c):
          if ($c.resourcePacks.common.version? // "") != "" then $c.resourcePacks.common.version
          elif (($c.resourcePacks // {}) | length) > 0 then ($c.resourcePacks | to_entries | .[0].value.version)
          elif ($c.default.config.version? // "") != "" then $c.default.config.version
          elif ($c.config.version? // "") != "" then $c.config.version
          else "" end;
        [ pick(.), (if (.predownload? // null) != null then pick(.predownload) else "" end) ] | join("\u001f")
    ' <<< "$raw")"; then
        log_error wuwa "版本接口返回了无法解析的内容"
        return 1
    fi
    IFS=$'\x1f' read -r version predownload <<< "$fields"

    if [ -z "$version" ]; then
        log_error wuwa "接口未返回鸣潮 ($variant) 的版本"
        return 1
    fi
    _remote_version="$version"
    _predownload_version="$predownload"
}

game_version_variant_human_readable() {
    case "$1" in
        cn)       printf '%s\n' "国服" ;;
        bilibili) printf '%s\n' "Bilibili" ;;
        global)   printf '%s\n' "国际服" ;;
        *)        printf '%s\n' "未知" ;;
    esac
}
