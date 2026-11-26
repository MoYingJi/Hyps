#!/usr/bin/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

# 单个游戏的通用环境加载
# 会 source 游戏实现并写入 CONFIG / GAME_FS，批量查询时必须放进子 shell
# 单游戏命令（game info）在进程内直接调用即可，进程随后退出
# 游戏实现整体可选，没有实现时仍可用显式配置启动
# 返回: 0 就绪 / 2 未配置 / 1 配置错误，具体原因见 _GAME_REASON
_game_context_load() {
    local game_name="$1"
    local game_impl="$SCRIPT_DIR/games/$game_name.sh"

    _GAME_REASON=""

    #shellcheck disable=SC2034 # 供 source 的游戏实现使用
    GAME_NAME="$game_name"

    if [ -f "$game_impl" ]; then
        #shellcheck source=/dev/null
        source "$game_impl" || {
            _GAME_REASON="游戏实现加载失败"
            return 1
        }
    fi

    if [ ! -f "$CONFIG_DIR/games/$game_name.conf" ]; then
        return 2
    fi

    load_game_config "$game_name" || {
        _GAME_REASON="游戏配置加载失败"
        return 1
    }

    if ! config_has game.exe && ! config_has game.install_dir; then
        _GAME_REASON="缺少 game.exe 与 game.install_dir"
        return 1
    fi

    game_fs_resolve_paths || {
        _GAME_REASON="游戏路径解析失败"
        return 1
    }

    if ! config_has runner.exe && ! config_has runner.protonpath; then
        _GAME_REASON="缺少运行器"
        return 1
    fi

    # install 未知时 overlay 和依赖 install 的功能都不可用
    if [ "${GAME_FS[install_ok]:-0}" != "1" ]; then
        _GAME_REASON="无法确定安装目录，请设置 game.install_dir 或实现 game_install_dir"
        return 1
    fi

    return 0
}

# 列表只区分三种状态，具体原因留给 game info
declare -gA _GAME_STATUS_TEXT=(
    [0]="就绪"
    [1]="配置错误"
    [2]="未配置"
)
declare -gA _GAME_STATUS_STYLE=(
    [0]="green"
    [1]="red"
    [2]="bright_black"
)

# 把 _game_context_load 的返回码映射到展示状态
_game_status_of() {
    case "$1" in
        0) printf '0\n' ;;
        2) printf '2\n' ;;
        *) printf '1\n' ;;
    esac
}

# 收集列表字段，输出制表符分隔: 返回码 显示名 安装目录 占用 本地版本
# 必须在子 shell 中调用，返回码同时作为函数退出码
_game_list_collect() {
    local game_name="$1"
    local want_size="$2"
    local want_version="$3"
    local rc=0

    _game_context_load "$game_name" || rc=$?

    local display install size_text="-" version_text="-" config_install=""
    display="$(game_meta_display_name 2>/dev/null)" || display="$game_name"

    config_read game.install_dir config_install 2>/dev/null || true
    install="${GAME_FS[install_dir]:-$config_install}"
    install="$(path_shorten "$install" 44)"

    if [ "$want_size" -eq 1 ]; then
        local size_path="${GAME_FS[install_dir]:-$config_install}"
        if [ -n "$size_path" ] && [ -d "$size_path" ]; then
            size_text="$(format_size "$(path_size "$size_path")")"
        fi
    fi

    if [ "$want_version" -eq 1 ] && [ "$(type -t game_version_local)" = "function" ]; then
        # 输出变量不能和集成内部的局部变量重名，否则 nameref 会指向内部变量
        local exe="" local_version="" local_variant="" local_context=""
        config_read game.exe exe 2>/dev/null || true
        if [ -n "$exe" ] && game_version_local "$exe" local_version local_variant local_context 2>/dev/null \
            && [ -n "$local_version" ]; then
            version_text="$local_version"
            if [ -n "$local_variant" ]; then
                local variant_display="$local_variant"
                if [ "$(type -t game_version_variant_human_readable)" = "function" ]; then
                    variant_display="$(game_version_variant_human_readable "$local_variant" 2>/dev/null)" \
                        || variant_display="$local_variant"
                fi
                version_text="$local_version ($variant_display)"
            fi
        fi
    fi

    printf '%s\x1f%s\x1f%s\x1f%s\x1f%s\n' "$(_game_status_of "$rc")" \
        "$display" "$install" "$size_text" "$version_text"
    return "$rc"
}

# 找到某个游戏对应的启动脚本
_game_launcher_script() {
    local game_name="$1"
    local scripts_dir="${SCRIPTS_DIR:-${PROJECT_ROOT:-.}/scripts}"
    local sh name
    for sh in "$scripts_dir"/*; do
        [ -f "$sh" ] || continue
        [[ "${sh##*/}" == _* ]] && continue
        game_script_name "$sh" name || continue
        [ "$name" = "$game_name" ] || continue
        printf '%s\n' "$sh"
        return 0
    done
    return 1
}

command_game_list() {
    local want_size=0 want_version=0 show_all=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --size) want_size=1 ;;
            --version) want_version=1 ;;
            --all) show_all=1 ;;
            -h | --help) help_game_list; return 0 ;;
            *) die 2 "用法: game list [--all] [--size] [--version]" ;;
        esac
        shift
    done

    load_common_config

    # 游戏集合取启动脚本与配置文件的并集，避免只有配置的游戏消失
    local -a games=()
    local -A seen=()
    local scripts_dir="${SCRIPTS_DIR:-${PROJECT_ROOT:-.}/scripts}"
    local sh basename name conf
    for sh in "$scripts_dir"/*; do
        [ -f "$sh" ] || continue
        basename="${sh##*/}"
        [[ "$basename" == _* ]] && continue
        game_script_name "$sh" name || continue
        [ -n "$name" ] || continue
        [ -n "${seen[$name]:-}" ] && continue
        seen[$name]=1
        games+=("$name")
    done
    for conf in "$CONFIG_DIR"/games/*.conf; do
        [ -f "$conf" ] || continue
        name="${conf##*/}"
        name="${name%.conf}"
        [ "$name" = "_common" ] && continue
        game_name_valid "$name" || continue
        [ -n "${seen[$name]:-}" ] && continue
        seen[$name]=1
        games+=("$name")
    done

    local -a header=("游戏" "名称" "状态" "安装目录")
    [ "$want_size" -eq 1 ] && header+=("占用")
    [ "$want_version" -eq 1 ] && header+=("版本")

    local header_line="" cell
    for cell in "${header[@]}"; do
        header_line+="$(style_table_header "$cell")"$'\t'
    done
    header_line="${header_line%$'\t'}"

    local rows="$header_line"$'\n'
    local row rc display install size_text version_text status_text status_style name_style line
    for name in "${games[@]}"; do
        if log_should_output DEBUG; then
            row="$(_game_list_collect "$name" "$want_size" "$want_version")" || true
        else
            row="$(_game_list_collect "$name" "$want_size" "$want_version" 2>/dev/null)" || true
        fi

        if [ -z "$row" ]; then
            rc=1
            display="$name"
            install=""
            size_text="-"
            version_text="-"
        else
            IFS=$'\x1f' read -r rc display install size_text version_text <<< "$row"
        fi
        case "$rc" in
            0 | 1 | 2) ;;
            *) rc=1 ;;
        esac

        if [ "$show_all" -eq 0 ] && [ "$rc" -eq 2 ]; then
            continue
        fi
        [ -n "$install" ] || install="-"

        status_text="${_GAME_STATUS_TEXT[$rc]}"
        status_style="${_GAME_STATUS_STYLE[$rc]}"
        name_style="bright_blue"
        [ "$rc" -eq 2 ] && name_style="bright_black"

        line="$(style_quote "$name_style" "$name")"$'\t'
        line+="$(style_quote bright_white "$display")"$'\t'
        line+="$(style_quote "$status_style" "$status_text")"$'\t'
        line+="$(style_quote bright_black "$install")"
        [ "$want_size" -eq 1 ] && line+=$'\t'"$(style_quote cyan "$size_text")"
        [ "$want_version" -eq 1 ] && line+=$'\t'"$(style_quote bright_black "$version_text")"
        rows+="$line"$'\n'
    done

    printf "%s" "$rows" | column -t -s $'\t'
}

help_game_list() {
    echo "  game list [--all] [--size] [--version]  列出已配置的游戏及状态；--all 包含未配置的游戏"
}

# 输出单个信息小节，键值用制表符分隔，交给 column 对齐
_game_info_section() {
    local title="$1"
    printf '\n%s\n' "$(style_quote bright_white,bold "$title")"
    column -t -s $'\t' | sed 's/^/  /'
}

_game_info_kv() {
    printf '%s\t%s\n' "$(style_quote bright_black "$1")" "$2"
}

help_game_info() {
    echo "  game info <游戏名> [--size|--no-size] [--remote]  查看单个游戏的详细信息"
}

command_game_info() {
    local game_name=""
    local want_size=1 want_remote=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --size) want_size=1 ;;
            --no-size) want_size=0 ;;
            --remote) want_remote=1 ;;
            -h | --help) help_game_info; return 0 ;;
            -*) die 2 game "未知选项: '$1'" ;;
            *)
                [ -z "$game_name" ] || die 2 game "一次只能指定一个游戏名"
                game_name="$1"
                ;;
        esac
        shift
    done
    [ -n "$game_name" ] || die 2 game "用法: game info <游戏名> [--size|--no-size] [--remote]"
    game_name_valid "$game_name" || die 1 game "无效的游戏名: $game_name"

    # 每日刷新需要时间记录功能的声明和用户覆盖，按需加载
    if [ "$(type -t feat_time_record_load_config)" != "function" ]; then
        #shellcheck source=../features/time_record.sh
        source "$SCRIPT_DIR/features/time_record.sh"
    fi

    load_common_config

    local rc=0
    _game_context_load "$game_name" || rc=$?
    [ "$rc" -ne 2 ] || die 1 game "游戏未配置: $game_name"

    # 初始化完整路径视图以获取 overlay 和 prefix，失败时保留已解析的部分
    game_fs_init >/dev/null 2>&1 || true

    local display path_name launcher config_file reset
    display="$(game_meta_display_name 2>/dev/null)" || display="$game_name"
    path_name="$(game_meta_path_name 2>/dev/null)" || path_name="$game_name"
    if launcher="$(_game_launcher_script "$game_name")"; then
        launcher="${launcher#"$PROJECT_ROOT"/}"
    else
        launcher="-"
    fi
    config_file="$(path_shorten "$CONFIG_DIR/games/$game_name.conf" 60)"
    config_read features.time_record.today.reset reset 2>/dev/null || true
    [ -n "$reset" ] || reset="未设置"

    {
        _game_info_kv "游戏 ID" "$(style_quote bright_blue "$game_name")"
        _game_info_kv "显示名" "$(style_quote bright_white "$display")"
        _game_info_kv "路径名" "$path_name"
        _game_info_kv "启动脚本" "$launcher"
        _game_info_kv "配置文件" "$config_file"
        _game_info_kv "每日刷新" "$reset"
        local status_rc status_display
        status_rc="$(_game_status_of "$rc")"
        status_display="$(style_quote "${_GAME_STATUS_STYLE[$status_rc]}" "${_GAME_STATUS_TEXT[$status_rc]}")"
        [ "$status_rc" -eq 1 ] && [ -n "${_GAME_REASON:-}" ] && status_display+=" ($_GAME_REASON)"
        _game_info_kv "状态" "$status_display"
    } | _game_info_section "基本信息"

    local install exe cwd prefix config_install="" config_exe=""
    config_read game.install_dir config_install 2>/dev/null || true
    config_read game.exe config_exe 2>/dev/null || true
    install="${GAME_FS[install_dir]:-$config_install}"
    exe="${GAME_FS[game_exe_install]:-$config_exe}"
    cwd="${GAME_FS[game_cwd_install]:-}"
    prefix="${GAME_FS[prefix]:-}"
    [ -n "$prefix" ] || config_read game.prefix prefix 2>/dev/null || true

    # 先算占用，路径小节里统一跟在对应路径后面
    local install_size="-" upper_size="-" prefix_size="-"
    if [ "$want_size" -eq 1 ]; then
        if [ -n "$install" ] && [ -d "$install" ]; then
            install_size="$(format_size "$(path_size "$install")")"
        fi
        if [ "${GAME_FS[overlay_enabled]:-0}" = "1" ] && [ -n "${GAME_FS[overlay_upper]:-}" ] \
            && [ -d "${GAME_FS[overlay_upper]}" ]; then
            upper_size="$(format_size "$(path_size "${GAME_FS[overlay_upper]}")")"
        fi
        if [ -n "$prefix" ] && [ -d "$prefix" ]; then
            prefix_size="$(format_size "$(path_size "$prefix")")"
        fi
    fi

    {
        local install_display
        install_display="$(style_quote bright_black "$(path_shorten "${install:--}" 0)")"
        [ "$install_size" = "-" ] || install_display+=" $(style_quote cyan "$install_size")"
        _game_info_kv "安装目录" "$install_display"

        local exe_state=""
        if [ -n "$exe" ]; then
            if [ -f "$exe" ]; then
                exe_state=" $(style_quote green "存在")"
            else
                exe_state=" $(style_quote red "不存在")"
            fi
        fi
        _game_info_kv "可执行文件" "$(style_quote bright_black "$(path_shorten "${exe:--}" 0)")$exe_state"
        _game_info_kv "工作目录" "$(style_quote bright_black "$(path_shorten "${cwd:--}" 0)")"
        local prefix_display
        prefix_display="$(style_quote bright_black "$(path_shorten "${prefix:--}" 0)")"
        [ "$prefix_size" = "-" ] || prefix_display+=" $(style_quote cyan "$prefix_size")"
        _game_info_kv "Wine 前缀" "$prefix_display"

        if config_is_true overlay.enabled; then
            _game_info_kv "Overlay" "$(style_quote green "开启")"
            _game_info_kv "  lower" "$(style_quote bright_black "$(path_shorten "${GAME_FS[overlay_lower]:--}" 0)")"
            local upper_display
            upper_display="$(style_quote bright_black "$(path_shorten "${GAME_FS[overlay_upper]:--}" 0)")"
            [ "$upper_size" = "-" ] || upper_display+=" $(style_quote cyan "$upper_size")"
            _game_info_kv "  upper" "$upper_display"
            local mount_state="未挂载"
            [ "${GAME_FS[overlay_mounted]:-0}" = "1" ] && mount_state="已挂载"
            _game_info_kv "  mount" "$(style_quote bright_black "$(path_shorten "${GAME_FS[overlay_mount]:--}" 0)") ($mount_state)"
        else
            _game_info_kv "Overlay" "$(style_quote bright_black "关闭")"
        fi
    } | _game_info_section "路径"

    local has_local=0 has_remote=0
    [ "$(type -t game_version_local)" = "function" ] && has_local=1
    [ "$(type -t game_version_remote)" = "function" ] && has_remote=1
    # 输出变量避开集成内部的局部变量名，否则 nameref 会指向内部变量
    local local_version="" info_variant="" info_context=""
    if [ "$has_local" -eq 1 ] && [ -n "$exe" ]; then
        game_version_local "$exe" local_version info_variant info_context 2>/dev/null || local_version=""
    fi

    local latest_ok=0 latest_version="" pre_version=""
    if [ "$want_remote" -eq 1 ] && [ "$has_remote" -eq 1 ]; then
        if game_version_remote "$info_variant" "$info_context" latest_version pre_version 2>/dev/null \
            && [ -n "$latest_version" ]; then
            latest_ok=1
        fi
    fi

    {
        if [ -n "$local_version" ]; then
            local variant_display="$info_variant" local_text="$local_version"
            if [ -n "$info_variant" ] && [ "$(type -t game_version_variant_human_readable)" = "function" ]; then
                variant_display="$(game_version_variant_human_readable "$info_variant" 2>/dev/null)" \
                    || variant_display="$info_variant"
            fi
            [ -z "$variant_display" ] || local_text+=" ($variant_display)"
            _game_info_kv "本地版本" "$(style_quote bright_blue "$local_text")"
        elif [ "$has_local" -eq 1 ]; then
            _game_info_kv "本地版本" "$(style_quote red "读取失败")"
        else
            _game_info_kv "本地版本" "$(style_quote bright_black "不支持")"
        fi

        if [ "$has_remote" -ne 1 ]; then
            _game_info_kv "最新版本" "$(style_quote bright_black "不支持")"
        elif [ "$want_remote" -ne 1 ]; then
            _game_info_kv "最新版本" "$(style_quote bright_black "使用 --remote 查询")"
        elif [ "$latest_ok" -eq 1 ]; then
            _game_info_kv "最新版本" "$(style_quote bright_blue "$latest_version")"
            if [ -n "$pre_version" ]; then
                _game_info_kv "预下载" "$(style_quote bright_cyan "$pre_version")"
            else
                _game_info_kv "预下载" "$(style_quote bright_black "未开放")"
            fi
        else
            _game_info_kv "最新版本" "$(style_quote red "请求失败")"
        fi
    } | _game_info_section "版本"

    local time_dir="" time_data count dur last
    config_read features.time_record.dir time_dir 2>/dev/null || true
    time_data="$time_dir/$game_name"
    {
        if [ -n "$time_dir" ] && [ -d "$time_data" ]; then
            count="$(time_record_count "$time_data")"
            dur="$(time_record_total_dur "$time_data")"
            last="$(time_record_last_start "$time_data")"
            _game_info_kv "启动次数" "$(style_quote cyan "$count")"
            _game_info_kv "总时长" "$(format_dur "$dur")"
            if [ -n "$last" ]; then
                _game_info_kv "最后启动" "$(style_quote bright_black "$(format_time "$last")")"
            else
                _game_info_kv "最后启动" "$(style_quote bright_black "-")"
            fi
        else
            _game_info_kv "记录" "$(style_quote bright_black "暂无记录")"
        fi
    } | _game_info_section "游玩"

    printf '\n%s\n' "$(style_quote bright_black "相关命令: config show $game_name / time report $game_name / game outdated $game_name")"
}

help_game_outdated() {
    echo "  game outdated [<游戏名>]  检查游戏版本与预下载；不指定游戏名时列出所有支持检查的游戏"
}

# 每个游戏在独立子 shell 中加载，收集和渲染共用该环境
# 返回: 0 成功 / 1 查询失败 / 2 不支持版本检查
# 远程失败仍输出结果，本地失败不输出
_game_outdated_collect() (
    local game_name="$1"
    local mode="${2:-list}"
    local game_impl="$SCRIPT_DIR/games/$game_name.sh"
    local -A gameinfo=(
        [name]="$game_name"
        [exe]="" [variant]="" [local_context]=""
        [local_version]="" [remote_version]="" [pre_version]=""
        [local_ok]=0 [remote_ok]=0 [pre_ok]=0
    )

    #shellcheck disable=SC2034 # 供游戏实现使用
    GAME_NAME="$game_name"

    if [ ! -f "$CONFIG_DIR/games/$game_name.conf" ]; then
        if [[ "$mode" == "report" ]]; then
            die 1 config "游戏配置文件不存在：$CONFIG_DIR/games/$game_name.conf"
        fi
        return 2
    fi
    [ -f "$game_impl" ] || return 2

    #shellcheck source=/dev/null
    source "$game_impl" || return 1

    local has_local=0 has_remote=0
    [ "$(type -t game_version_local)" = "function" ] && has_local=1
    [ "$(type -t game_version_remote)" = "function" ] && has_remote=1

    # 列表模式需要 local+remote 双实现 (无法比较则无列表意义)，report 有什么报什么
    if [[ "$mode" != "report" ]]; then
        [ "$has_local" -eq 1 ] && [ "$has_remote" -eq 1 ] || return 2
    else
        [ "$has_local" -eq 1 ] || [ "$has_remote" -eq 1 ] || return 2
    fi

    load_game_config "$game_name"
    game_fs_resolve_paths || {
        log_error game-outdated "无法解析 $game_name 的游戏路径"
        return 1
    }
    local game_exe
    config_read game.exe game_exe
    gameinfo[exe]="$game_exe"

    if [ "$has_local" -eq 1 ]; then
        local local_variant=""
        if ! game_version_local "$game_exe" "gameinfo[local_version]" local_variant "gameinfo[local_context]" \
            || [ -z "${gameinfo[local_version]}" ]; then
            log_error game-outdated "无法读取 $game_name 的本地版本"
            return 1
        fi
        gameinfo[local_ok]=1
        gameinfo[variant]="$local_variant"
    fi

    if [ "$has_remote" -eq 1 ]; then
        local fetched_remote="" fetched_pre=""
        if game_version_remote "${gameinfo[variant]}" "${gameinfo[local_context]}" fetched_remote fetched_pre \
            && [ -n "$fetched_remote" ]; then
            gameinfo[remote_ok]=1
            gameinfo[remote_version]="$fetched_remote"
            gameinfo[pre_ok]=1
            gameinfo[pre_version]="$fetched_pre"
        else
            log_error game-outdated "无法获取 $game_name 的远程版本"
        fi
    fi

    _game_outdated_render gameinfo "$mode"
    [ "${gameinfo[remote_ok]}" -eq 1 ] || [ "$has_remote" -eq 0 ]
)

# 比较结论，三态: 已是最新 / 可更新 / 无法判断 (远程不可得时)
#shellcheck disable=SC2178,SC2034  # nameref 输出参数
_game_outdated_status() {
    local -n _info="$1"
    local -n out_status="$2"
    local -n out_style="$3"

    if [ "${_info[remote_ok]}" -eq 1 ]; then
        if [ "${_info[local_ok]}" -eq 1 ] \
            && [[ "${_info[local_version]}" == "${_info[remote_version]}" ]]; then
            out_status="✓ 已是最新"
            out_style="green"
        else
            out_status="↑ 可更新"
            out_style="bright_yellow"
        fi
    else
        out_status="✗ 无法判断"
        out_style="bright_black"
    fi
}

# 带样式的展示行 (tab 分隔)，mode: "list" | "report"
# 依赖 collect 已执行 (game_version_* 函数仍处于加载状态)
#shellcheck disable=SC2178,SC2031  # nameref 下标被误认为独立变量
_game_outdated_render() {
    local -n _info="$1"
    local mode="${2:-list}"

    local status status_style local_style="bright_blue"
    _game_outdated_status "$1" status status_style

    # 未实现 human_readable 时直接显示变体标识
    local variant_display="${_info[variant]}"
    if [ -n "$variant_display" ] \
        && [ "$(type -t game_version_variant_human_readable)" = "function" ]; then
        variant_display="$(game_version_variant_human_readable "$variant_display")"
    fi

    # 本地版本颜色跟随比较结论，无本地版本时保持默认蓝
    [ "${_info[local_ok]}" -eq 1 ] && local_style="$status_style"

    # 未定义版本检查时显示 "-"，请求失败显示红字标记
    local remote_display pre_display
    if [ "$(type -t game_version_remote)" != "function" ]; then
        remote_display="-"
        pre_display="-"
    elif [ "${_info[remote_ok]}" -eq 1 ]; then
        remote_display="${_info[remote_version]}"
        if [ -n "${_info[pre_version]}" ]; then
            pre_display="$(style_quote bright_cyan "⇣ 可预下载 ${_info[pre_version]}")"
        else
            pre_display="$(style_quote bright_black "未开放")"
        fi
    else
        remote_display="$(style_quote red "✗ 请求失败")"
        pre_display="$(style_quote red "✗ 请求失败")"
    fi

    if [[ "$mode" == "report" ]]; then
        printf "%s\t%s\n" "$(style_quote bright_black "游戏名")" "$(style_quote bright_blue,bold "${_info[name]}")"
        printf "%s\t%s\n" "$(style_quote bright_black "游戏路径")" "$(style_quote bright_black "${_info[exe]}")"
        if [ -n "$variant_display" ]; then
            printf "%s\t%s\n" "$(style_quote bright_black "文件变体")" "$(style_quote bright_blue "$variant_display")"
        fi
        if [ "${_info[local_ok]}" -eq 1 ]; then
            printf "%s\t%s\n" "$(style_quote bright_black "本地版本")" "$(style_quote "$local_style" "${_info[local_version]}")"
        fi
        printf "%s\t%s\n" "$(style_quote bright_black "最新版本")" "$remote_display"
        printf "%s\t%s\n" "$(style_quote bright_black "状态")" "$(style_quote "$status_style" "$status")"
        printf "%s\t%s\n" "$(style_quote bright_black "预下载")" "$pre_display"
    else
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$(style_quote bright_blue "${_info[name]}")" \
            "$(style_quote bright_black "$variant_display")" \
            "$(style_quote "$local_style" "${_info[local_version]}")" \
            "$remote_display" \
            "$(style_quote "$status_style" "$status")" \
            "$pre_display"
    fi
}

command_game_outdated() {
    [ "$#" -le 1 ] || die 1 "用法: game outdated [<游戏名>]"

    load_common_config

    if [ "$#" -eq 1 ]; then
        local game_name
        game_name="$1"
        game_name_valid "$game_name" || die 1 "无效的游戏名: $game_name"

        local report
        report="$(_game_outdated_collect "$game_name" report)"
        local collect_status=$?
        [ "$collect_status" -ne 2 ] || die 1 game-outdated "游戏不支持版本检查: $game_name"
        [ -z "$report" ] || printf '%s\n' "$report" | column -t -s $'\t'
        return "$collect_status"
    else
        local results="" game_config game_name row
        local errors=0
        for game_config in "$CONFIG_DIR"/games/*.conf; do
            [ -f "$game_config" ] || continue
            game_name="${game_config##*/}"
            game_name="${game_name%.conf}"
            game_name_valid "$game_name" || continue

            row="$(_game_outdated_collect "$game_name")"
            case $? in
                0) results+="$row"$'\n' ;;
                2) continue ;;
                *)
                    [ -z "$row" ] || results+="$row"$'\n'
                    errors=1
                    ;;
            esac
        done

        {
            printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
                "$(style_table_header "游戏名")" \
                "$(style_table_header "变体")" \
                "$(style_table_header "本地版本")" \
                "$(style_table_header "最新版本")" \
                "$(style_table_header "状态")" \
                "$(style_table_header "预下载")"
            printf "%s" "$results"
        } | column -t -s $'\t'

        return "$errors"
    fi
}
