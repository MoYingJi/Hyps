#!/hint/bash

[[ -n "${__INTEGRATIONS_GRYPH_SH_LOADED:-}" ]] && return 0
__INTEGRATIONS_GRYPH_SH_LOADED=1

#shellcheck source=../core/log.sh
source "$SCRIPT_DIR/core/log.sh"
#shellcheck source=../utils/fs.sh
source "$SCRIPT_DIR/utils/fs.sh"
#shellcheck source=../utils/command.sh
source "$SCRIPT_DIR/utils/command.sh"

# 鹰角启动器（明日方舟 / 终末地）接口与本地配置适配
# config.ini 用固定 AES-256-CBC 加密，密钥/IV 由反编译启动器得到，两个游戏通用
GRYPH_LAUNCHER_AES_KEY="c0f30e1ce763bbc21cc355a34303ac50399444bff68c4a22af398c0a166ee143"
GRYPH_LAUNCHER_AES_IV="33467861192750649501937264608400"

# 本地读取的查询参数由 game_version_local 写入，game_version_remote 在同一子 shell 内复用
declare -gA _GRYPH_LOCAL_VERSION _GRYPH_APPCODE _GRYPH_CHANNEL _GRYPH_SUB_CHANNEL

# 解密游戏根目录的 config.ini，输出明文
integration_gryph_decrypt_config() {
    local config_file="$1"
    local -n _plaintext="$2"

    if [ ! -f "$config_file" ]; then
        log_error gryph "找不到游戏配置文件: $config_file"
        return 1
    fi
    if ! command_exists openssl; then
        log_error gryph "需要 openssl 才能解密 $config_file"
        return 1
    fi
    if ! _plaintext="$(openssl enc -d -aes-256-cbc \
        -K "$GRYPH_LAUNCHER_AES_KEY" -iv "$GRYPH_LAUNCHER_AES_IV" \
        -in "$config_file" 2>/dev/null)"; then
        log_error gryph "无法解密游戏配置文件: $config_file"
        return 1
    fi
}

# 读取 config.ini 中版本检查所需的字段
# 通过 nameref 输出 version / appcode / region / channel / sub_channel
integration_gryph_read_launcher_config() {
    local config_file="$1"
    local -n _version="$2"
    local -n _appcode="$3"
    local -n _region="$4"
    local -n _channel="$5"
    local -n _sub_channel="$6"

    local plaintext line key value
    integration_gryph_decrypt_config "$config_file" plaintext || return 1

    _version=""
    _appcode=""
    _region=""
    _channel=""
    _sub_channel=""

    while IFS= read -r line; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*[#\;] ]] && continue
        [[ "$line" == \[* ]] && continue
        [[ "$line" == *=* ]] || continue

        key="${line%%=*}"
        value="${line#*=}"
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"

        case "$key" in
            version)     _version="$value" ;;
            appcode)     _appcode="$value" ;;
            region)      _region="$value" ;;
            channel)     _channel="$value" ;;
            sub_channel) _sub_channel="$value" ;;
        esac
    done <<< "$plaintext"

    [ -n "$_version" ] || {
        log_error gryph "配置文件中没有 version: $config_file"
        return 1
    }
}

# 由 region + channel 推导分发变体
# cn + 1 为官服、cn + 2 为 B 服、os 为国际服，与 hyp 集成使用同一套标识
integration_gryph_variant_from_config() {
    local -n _variant="$1"
    local region="$2"
    local channel="$3"

    case "$region:$channel" in
        cn:1) _variant="cn" ;;
        cn:2) _variant="bilibili" ;;
        os:*) _variant="global" ;;
        *)    _variant=""; return 1 ;;
    esac
}

integration_gryph_variant_human_readable() {
    case "$1" in
        cn)       printf '%s\n' "国服" ;;
        bilibili) printf '%s\n' "Bilibili" ;;
        global)   printf '%s\n' "国际服" ;;
        *)        printf '%s\n' "未知" ;;
    esac
}

# 变体对应的接口域名与 channel / sub_channel，后两者取自本地 config.ini
_integration_gryph_get_endpoint() {
    local -n _base="$1"
    local -n _channel="$2"
    local -n _sub_channel="$3"
    local game="$4"
    local variant="$5"

    case "$variant" in
        cn | bilibili) _base="https://launcher.hypergryph.com/api" ;;
        global)        _base="https://launcher.gryphline.com/api" ;;
        *) return 1 ;;
    esac

    _channel="${_GRYPH_CHANNEL["$game:$variant"]:-}"
    _sub_channel="${_GRYPH_SUB_CHANNEL["$game:$variant"]:-}"
    [ -n "$_channel" ] || return 1
    _sub_channel="${_sub_channel:-$_channel}"
}

# 请求 get_latest，输出原始 JSON
# local_version 非空时带上 version 参数，接口会据此返回 patch / pre_patch
_integration_gryph_get_latest_raw() {
    local -n _raw="$1"
    local game="$2"
    local variant="$3"
    local local_version="${4:-}"

    local base channel sub_channel appcode url
    if ! _integration_gryph_get_endpoint base channel sub_channel "$game" "$variant"; then
        log_error gryph "无法确定 $game ($variant) 的接口参数"
        return 1
    fi
    appcode="${_GRYPH_APPCODE["$game:$variant"]:-}"
    if [ -z "$appcode" ]; then
        log_error gryph "缺少 $game ($variant) 的 appCode"
        return 1
    fi
    if ! command_exists curl || ! command_exists jq; then
        log_error gryph "查询版本需要 curl 和 jq"
        return 1
    fi

    url="$base/game/get_latest?appcode=$appcode&channel=$channel&sub_channel=$sub_channel"
    [ -n "$local_version" ] && url="$url&version=$local_version"

    if ! _raw="$(curl -fsS "$url" 2>&1)"; then
        log_error gryph "无法请求版本接口: $url"
        return 1
    fi

    local code
    if ! code="$(jq -r '.code // 0' <<< "$_raw" 2>/dev/null)"; then
        log_error gryph "版本接口返回了无法解析的内容"
        return 1
    fi
    if [ "$code" != "0" ]; then
        log_error gryph "版本接口错误 [$code]: $(jq -r '.message // "unknown"' <<< "$_raw" 2>/dev/null)"
        return 1
    fi
}

integration_gryph_get_game_version_local() {
    local game="$1"
    local game_exe="$2"
    local -n _local_version="$3"
    local -n _local_variant="$4"

    local game_dir config_file version appcode region channel sub_channel variant
    path_dirname "$game_exe" game_dir
    config_file="$game_dir/config.ini"

    integration_gryph_read_launcher_config "$config_file" \
        version appcode region channel sub_channel || return 1

    _local_version="$version"

    if ! integration_gryph_variant_from_config variant "$region" "$channel"; then
        log_warn gryph "无法识别的区服/渠道: region='$region' channel='$channel'"
        _local_variant=""
        return 0
    fi
    _local_variant="$variant"
    _GRYPH_LOCAL_VERSION["$game:$variant"]="$version"
    _GRYPH_APPCODE["$game:$variant"]="$appcode"
    _GRYPH_CHANNEL["$game:$variant"]="$channel"
    _GRYPH_SUB_CHANNEL["$game:$variant"]="$sub_channel"
}

# 返回远程版本与预下载版本；无预下载时预下载为空
# 用法: integration_gryph_get_game_version_remote <game> <variant> <remote_nameref> <predownload_nameref>
integration_gryph_get_game_version_remote() {
    local game="$1"
    local variant="${2-cn}"
    local -n _remote_version="$3"
    local -n _predownload_version="$4"

    # 带上本地版本，一次请求同时拿到最新版本与预下载信息
    local local_version="${_GRYPH_LOCAL_VERSION["$game:$variant"]:-}"
    local raw
    _integration_gryph_get_latest_raw raw "$game" "$variant" "$local_version" || return 1

    _remote_version="$(jq -r '.version // empty' <<< "$raw" 2>/dev/null)"
    [ -n "$_remote_version" ] || {
        log_error gryph "接口未返回 $game ($variant) 的版本"
        return 1
    }
    _predownload_version="$(jq -r '.pre_patch.version // empty' <<< "$raw" 2>/dev/null)"
}
