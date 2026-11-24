#!/hint/bash

[[ -n "${__INTEGRATIONS_HYP_SH_LOADED:-}" ]] && return 0
__INTEGRATIONS_HYP_SH_LOADED=1

#shellcheck source=../core/log.sh
source "$SCRIPT_DIR/core/log.sh"
#shellcheck source=../utils/fs.sh
source "$SCRIPT_DIR/utils/fs.sh"
#shellcheck source=../utils/command.sh
source "$SCRIPT_DIR/utils/command.sh"
#shellcheck source=../utils/ini.sh
source "$SCRIPT_DIR/utils/ini.sh"

integration_hyp_read_server_from_game_config() {
    local config_file="$1" # /path/to/config.ini
    local -n _server="$2"
    if [ -n "$3" ]; then local -n _game_version="$3"; else local _game_version=""; fi

    local channel sub_channel cps game_version
    { read -r channel; read -r sub_channel; read -r cps; read -r game_version; } \
        < <(ini_get channel sub_channel cps game_version < "$config_file")

    _game_version="$game_version"

    case "${channel}:${sub_channel}:${cps}" in
        "1:1:hyp_mihoyo")    _server="cn" ;;
        "14:0:hyp_mihoyo")   _server="bilibili" ;;
        "1:0:hyp_hoyoverse") _server="global" ;;
        *) return 1 ;;
    esac
}

integration_hyp_get_game_version_local() {
    local game_exe="$1"
    local -n _local_version="$2"
    local -n _local_variant="$3"
    local game_dir server version

    path_dirname "$game_exe" game_dir
    integration_hyp_read_server_from_game_config "$game_dir/config.ini" server version || return 1
    _local_version="$version"
    _local_variant="$server"
}

integration_hyp_variant_human_readable() {
    local variant="$1"
    case "$variant" in
        "cn")       printf '%s\n' "国服" ;;
        "global")   printf '%s\n' "国际服" ;;
        "bilibili") printf '%s\n' "Bilibili" ;;
        *)          printf '%s\n' "未知" ;;
    esac
}

_integration_hyp_get_api_domain() {
    local -n _domain="$1"
    local server="$2"

    case "$server" in
        "cn")       _domain="hyp-api.mihoyo.com" ;;
        "bilibili") _domain="hyp-api.mihoyo.com" ;;
        "global")   _domain="sg-hyp-api.hoyoverse.com" ;;
        *) return 1 ;;
    esac
}

_integration_hyp_get_launcher_id() {
    local -n _launcher_id="$1"
    local server="$2"
    local game="${3:-}"

    case "$server" in
        "cn")       _launcher_id="jGHBHlcOq1" ;;
        "global")   _launcher_id="VYTpXlbWo8" ;;
        "bilibili")
            case "$game" in
                "genshin")  _launcher_id="umfgRO5gh5" ;;
                "starrail") _launcher_id="6P5gHMNyK3" ;;
                "zenless")  _launcher_id="xV0f4r1GT0" ;;
                *) return 1 ;;
            esac ;;
        *) return 1 ;;
    esac
}

declare -gA _HYP_BRANCH_VERSION      # game_biz -> main.tag
declare -gA _HYP_BRANCH_PREDOWNLOAD  # game_biz -> pre_download.tag (无预下载时为空)
declare -gA _HYP_BRANCH_LOADED       # 缓存键 -> 1
# -g: 本文件常在函数作用域内被 source，普通 declare 会使数组成为该函数的局部变量，
# 其它上下文 (如命令替换子 shell) 看不到缓存，且赋值会静默降级为索引数组

# bilibili 每个游戏有独立 launcher_id，缓存键按 launcher_id 而非 variant
_integration_hyp_branches_cache_key() {
    local -n _cache_key="$1"
    local variant="$2"
    local game="${3:-}"

    if [ "$variant" = "bilibili" ]; then
        _integration_hyp_get_launcher_id _cache_key "$variant" "$game" || return 1
    else
        _cache_key="$variant"
        return 0
    fi
}

# 请求 getGameBranches 并解析所有游戏的版本与预下载信息
_integration_hyp_load_branches() {
    local game="$1"
    local variant="${2:-cn}"
    local cache_key
    _integration_hyp_branches_cache_key cache_key "$variant" "$game" || return 1
    [[ -n "${_HYP_BRANCH_LOADED[$cache_key]:-}" ]] && return 0

    local domain launcher_id body raw
    _integration_hyp_get_api_domain domain "$variant" || return 1
    _integration_hyp_get_launcher_id launcher_id "$variant" "$game" || return 1

    # curl 与 jq 的错误都直接输出到 stderr (jq 的 API 错误来自 halt_error)，不经过捕获
    if ! body="$(curl -fsS "https://$domain/hyp/hyp-connect/api/getGameBranches?launcher_id=$launcher_id")"; then
        log_error hyp "无法请求游戏分支信息 (variant=$variant)"
        return 1
    fi

    # 本函数可能在 command substitution 中被调用，用 log_error + return 1 报错
    if ! raw="$(jq -r '
            if .retcode != 0 then
                "API error [\(.retcode)]: \(.message // "unknown")\n" | halt_error(1)
            else
                .data.game_branches[]
                | [.game.biz, (.main.tag // ""), (.pre_download.tag // "")]
                | join("\u001f")
            end
        ' <<< "$body")"; then
        log_error hyp "无法获取游戏分支信息 (variant=$variant)"
        return 1
    fi

    # \x1f 分隔: bash read 会折叠连续的空白 IFS 字符，空字段 (如无预下载的 pre_download.tag) 会被吞掉
    local sep=$'\x1f'
    local biz tag pre
    while IFS="$sep" read -r biz tag pre; do
        # 后写覆盖前写，与原语义一致 (如 global 响应中重复的 bh3 条目)
        [ -n "$biz" ] || continue
        _HYP_BRANCH_VERSION["$biz"]="$tag"
        _HYP_BRANCH_PREDOWNLOAD["$biz"]="$pre"
    done <<< "$raw"

    _HYP_BRANCH_LOADED["$cache_key"]=1
    log_debug hyp "已加载游戏分支信息 (variant=$variant, launcher_id=$launcher_id): ${#_HYP_BRANCH_VERSION[@]} 个游戏"
}

# 解析 hyp 游戏的 game_biz 标识；biz 后缀按服务器区分
_integration_hyp_game_biz() {
    local -n _game_biz="$1"
    local game="$2"
    local variant="${3:-cn}"

    case "$game" in
        "genshin")  _game_biz="hk4e" ;;
        "starrail") _game_biz="hkrpg" ;;
        "zenless")  _game_biz="nap" ;;
        "honkai3")  _game_biz="bh3" ;;
        *) return 1 ;;
    esac

    case "$variant" in
        "cn" | "bilibili") _game_biz+="_cn" ;;
        "global")          _game_biz+="_global" ;;
        *) return 1 ;;
    esac
}

# 返回远程版本与预下载版本；无预下载时预下载为空
# 用法: integration_hyp_get_game_version_remote <game> <variant> <context> <remote_nameref> <predownload_nameref>
# context 不参与查询 (hyp 的 getGameBranches 只需 game 与 variant)，保留位置与 gryph 一致
integration_hyp_get_game_version_remote() {
    local game="$1"
    local variant="${2:-cn}"
    local -n _remote_version="$4"
    local -n _predownload_version="$5"
    local game_biz

    _integration_hyp_game_biz game_biz "$game" "$variant" || return 1
    _integration_hyp_load_branches "$game" "$variant" || return 1

    _remote_version="${_HYP_BRANCH_VERSION[$game_biz]:-}"
    [ -n "$_remote_version" ] || {
        log_error hyp "API 未返回 $game ($game_biz, variant=$variant) 的版本"
        return 1
    }
    _predownload_version="${_HYP_BRANCH_PREDOWNLOAD[$game_biz]:-}"
}

integration_hyp_extract_pkg_version() {
    local pkg_version_file="$1"
    local target_remote_name="$2"

    if [ -z "$pkg_version_file" ] || [ ! -f "$pkg_version_file" ]; then
        die 1 hyp "未找到 pkg_version 文件"
    fi

    if [ -z "$target_remote_name" ]; then
        die 1 hyp "未指定目标远程文件名"
    fi

    if command_exists jq; then
        jq -r --arg target "$target_remote_name" '
            select(.remoteName == $target) |
            [.md5, (.fileSize | tostring)] | @tsv
        ' "$pkg_version_file"
    else
        grep -F "\"remoteName\": \"$target_remote_name\"" "$pkg_version_file" \
            | sed -E 's/.*"md5": "([^"]+)".*"fileSize": ([0-9]+).*/\1\t\2/'
    fi
}

integration_hyp_verify_file_with_pkg_version() {
    local pkg_version_file="$1"
    local target_remote_name="$2"
    local file_to_verify="$3"

    if [ ! -f "$file_to_verify" ]; then
        die 1 hyp "文件不存在: $file_to_verify"
    fi

    local expected_md5 expected_size
    IFS=$'\t' read -r expected_md5 expected_size < <(integration_hyp_extract_pkg_version "$pkg_version_file" "$target_remote_name")

    local actual_md5 actual_size
    actual_md5=$(md5sum "$file_to_verify" | awk '{print $1}')
    actual_size=$(stat -c%s "$file_to_verify")

    [ "$expected_md5" == "$actual_md5" ] && [ "$expected_size" == "$actual_size" ]
}
