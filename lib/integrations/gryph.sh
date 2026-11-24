#!/hint/bash

[[ -n "${__INTEGRATIONS_GRYPH_SH_LOADED:-}" ]] && return 0
__INTEGRATIONS_GRYPH_SH_LOADED=1

#shellcheck source=../core/log.sh
source "$SCRIPT_DIR/core/log.sh"
#shellcheck source=../utils/fs.sh
source "$SCRIPT_DIR/utils/fs.sh"
#shellcheck source=../utils/command.sh
source "$SCRIPT_DIR/utils/command.sh"
#shellcheck source=../utils/ini.sh
source "$SCRIPT_DIR/utils/ini.sh"

# 鹰角启动器（明日方舟 / 终末地）接口与本地配置适配
# config.ini 用固定 AES-256-CBC 加密，密钥/IV 由反编译启动器得到，两个游戏通用
GRYPH_LAUNCHER_AES_KEY="c0f30e1ce763bbc21cc355a34303ac50399444bff68c4a22af398c0a166ee143"
GRYPH_LAUNCHER_AES_IV="33467861192750649501937264608400"

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
        -in "$config_file")"; then
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

    local plaintext
    local -a fields
    integration_gryph_decrypt_config "$config_file" plaintext || return 1

    mapfile -t fields < <(ini_get version appcode region channel sub_channel <<< "$plaintext")
    _version="${fields[0]}"
    _appcode="${fields[1]}"
    _region="${fields[2]}"
    _channel="${fields[3]}"
    _sub_channel="${fields[4]}"

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

# 请求 get_latest，输出原始 JSON
# context 为 integration_gryph_get_game_version_local 输出的 ini 文本 (appcode / channel / sub_channel / version)
# version 非空时带上 version 参数，接口会据此返回 patch / pre_patch
_integration_gryph_get_latest_raw() {
    local -n _raw="$1"
    local game="$2"
    local variant="$3"
    local context="$4"

    local base appcode channel sub_channel version url
    local -a fields
    case "$variant" in
        cn | bilibili) base="https://launcher.hypergryph.com/api" ;;
        global)        base="https://launcher.gryphline.com/api" ;;
        *)
            log_error gryph "无法确定 $game ($variant) 的接口地址"
            return 1 ;;
    esac

    mapfile -t fields < <(ini_get appcode channel sub_channel version <<< "$context")
    appcode="${fields[0]}"
    channel="${fields[1]}"
    sub_channel="${fields[2]:-$channel}"
    version="${fields[3]}"

    if [ -z "$appcode" ] || [ -z "$channel" ]; then
        log_error gryph "缺少 $game ($variant) 的 appCode 或 channel"
        return 1
    fi
    if ! command_exists curl || ! command_exists jq; then
        log_error gryph "查询版本需要 curl 和 jq"
        return 1
    fi

    url="$base/game/get_latest?appcode=$appcode&channel=$channel&sub_channel=$sub_channel"
    [ -n "$version" ] && url="$url&version=$version"

    # curl 的错误信息直接输出到 stderr，不经过捕获，失败时再补充上下文
    if ! _raw="$(curl -fsS "$url")"; then
        log_error gryph "无法请求版本接口: $url"
        return 1
    fi
}

# 本地版本、变体标识，以及远程查询所需的 context (ini 文本) 通过 nameref 输出
# 用法: integration_gryph_get_game_version_local <game> <game_exe> <version_nameref> <variant_nameref> <context_nameref>
integration_gryph_get_game_version_local() {
    local game="$1"
    local game_exe="$2"
    local -n _local_version="$3"
    local -n _local_variant="$4"
    local -n _local_context="$5"

    local game_dir config_file version appcode region channel sub_channel variant
    path_dirname "$game_exe" game_dir
    config_file="$game_dir/config.ini"

    integration_gryph_read_launcher_config "$config_file" \
        version appcode region channel sub_channel || return 1

    _local_version="$version"
    _local_context="$(printf 'appcode=%s\nchannel=%s\nsub_channel=%s\nversion=%s\n' \
        "$appcode" "$channel" "$sub_channel" "$version")"

    if ! integration_gryph_variant_from_config variant "$region" "$channel"; then
        log_warn gryph "$game: 无法识别的区服/渠道: region='$region' channel='$channel'"
        _local_variant=""
        return 0
    fi
    _local_variant="$variant"
}

# 返回远程版本与预下载版本；无预下载时预下载为空
# 用法: integration_gryph_get_game_version_remote <game> <variant> <context> <remote_nameref> <predownload_nameref>
# context 为 integration_gryph_get_game_version_local 输出的内容，不可为空
integration_gryph_get_game_version_remote() {
    local game="$1"
    local variant="${2-cn}"
    local context="$3"
    local -n _remote_version="$4"
    local -n _predownload_version="$5"

    # 同一次请求同时返回最新版本与预下载信息，用一次 jq 解析全部字段
    local raw fields code message version predownload
    _integration_gryph_get_latest_raw raw "$game" "$variant" "$context" || return 1

    if ! fields="$(jq -r '[(.code // 0 | tostring), (.message // "unknown"), (.version // ""), (.pre_patch.version // "")] | join("\u001f")' <<< "$raw")"; then
        log_error gryph "版本接口返回了无法解析的内容"
        return 1
    fi
    # \x1f 为非空白分隔符，空字段 (如无预下载) 不会被 read 合并
    IFS=$'\x1f' read -r code message version predownload <<< "$fields"

    if [ "$code" != "0" ]; then
        log_error gryph "版本接口错误 [$code]: $message"
        return 1
    fi
    if [ -z "$version" ]; then
        log_error gryph "接口未返回 $game ($variant) 的版本"
        return 1
    fi
    _remote_version="$version"
    _predownload_version="$predownload"
}
