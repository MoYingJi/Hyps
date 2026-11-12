#!/usr/bin/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

command_game_list() {
    [ "$#" -eq 0 ] || die 1 "用法: game list"

    load_common_config

    local print_no_config_game="true"

    local sh basename name exe_path basename_style name_style exe_path_style
    local rows=""
    # $(...) 会剥掉命令替换末尾的换行，行分隔统一用显式 $'\n' 补
    rows+="$(printf "%s\t%s\t%s" \
        "$(style_table_header "脚本")" \
        "$(style_table_header "游戏名")" \
        "$(style_table_header "游戏可执行文件")"
    )"$'\n'
    for sh in "$SCRIPTS_DIR"/*; do
        basename="${sh##*/}"
        [[ "$basename" == _* ]] && continue

        basename_style="green,bold"

        game_script_name "$sh" name || name=""

        if [ -z "$name" ]; then
            name="无效"
            name_style="red"

            exe_path="无效"
            exe_path_style="red"
        else
            name_style="bright_blue"

            local has_config config_has_game_exe
            IFS=$'\t' read -r has_config config_has_game_exe exe_path <<< "$(
                if [ ! -f "$CONFIG_DIR/games/${name}.conf" ]; then
                    echo "false"
                    return 0
                fi

                if log_should_output DEBUG; then
                    load_game_config "$name"
                else
                    load_game_config "$name" 2>/dev/null
                fi

                local game_exe_value
                config_read game.exe game_exe_value
                printf "%s\t%s\t%s" "true" "$(bool_str config_has game.exe)" "$game_exe_value"
            )"

            if [ "$has_config" = "false" ]; then
                if [ "$print_no_config_game" = "true" ]; then
                    exe_path="未配置"
                    exe_path_style="bright_black"
                    name_style="bright_black"
                    basename_style="bright_black"
                else
                    continue
                fi
            elif [ "$config_has_game_exe" = "true" ]; then
                if [ -f "$(realpath -m "$exe_path")" ]; then
                    exe_path_style="bright_black"
                else
                    exe_path_style="red"
                fi
            else
                exe_path="无效"
                exe_path_style="red"
            fi
        fi

        rows+="$(printf "%s\t%s\t%s" \
            "$(style_quote "$basename_style" "$basename")" \
            "$(style_quote "$name_style" "$name")" \
            "$(style_quote "$exe_path_style" "$exe_path")"
        )"$'\n'
    done
    printf "%s" "$rows" | column -t -s $'\t'
}

help_game_list() {
    echo "  game list  列出所有游戏脚本及配置状态"
}

help_game_outdated() {
    echo "  game outdated [<游戏名>]  检查游戏版本与预下载；不指定游戏名时列出所有支持检查的游戏"
}

# 收集单个游戏的版本信息，写入 nameref 关联数组
# 键: name/exe/variant/local_version/remote_version/pre_version (原始数据)
#     local_ok/remote_ok/pre_ok (0|1 各项是否成功获取)
# 返回: 0 成功 / 1 本地读取失败 / 2 不支持版本检查
# remote/pre 失败不阻断展示；local 失败无检查意义，直接报错
#shellcheck disable=SC2154,SC2102,SC2031  # nameref 下标被误认为独立变量/范围
_game_outdated_collect() {
    local game_name="$1"
    local -n _info="$2"
    local mode="${3:-}"
    local game_impl="$SCRIPT_DIR/games/$game_name.sh"

    _info[name]="$game_name"
    _info[exe]="" _info[variant]=""
    _info[local_version]="" _info[remote_version]="" _info[pre_version]=""
    _info[local_ok]=0 _info[remote_ok]=0 _info[pre_ok]=0

    if [ ! -f "$CONFIG_DIR/games/$game_name.conf" ]; then
        if [[ "$mode" == "report" ]]; then
            die 1 config "游戏配置文件不存在：$CONFIG_DIR/games/$game_name.conf"
        fi
        return 2
    fi
    [ -f "$game_impl" ] || return 2

    unset -f game_version_local game_version_remote game_version_variant_human_readable game_version_predownload_remote
    #shellcheck source=/dev/null
    source "$game_impl"

    local has_local=0 has_remote=0 has_predownload=0
    [ "$(type -t game_version_local)" = "function" ] && has_local=1
    [ "$(type -t game_version_remote)" = "function" ] && has_remote=1
    [ "$(type -t game_version_predownload_remote)" = "function" ] && has_predownload=1

    # 列表模式需要 local+remote 双实现 (无法比较则无列表意义)，report 有什么报什么
    if [[ "$mode" != "report" ]]; then
        [ "$has_local" -eq 1 ] && [ "$has_remote" -eq 1 ] || return 2
    else
        [ "$has_local" -eq 1 ] || [ "$has_remote" -eq 1 ] || [ "$has_predownload" -eq 1 ] || return 2
    fi

    load_game_config "$game_name"
    config_read game.exe game_exe
    _info[exe]="$game_exe"

    if [ "$has_local" -eq 1 ]; then
        local variant=""
        if ! game_version_local "$game_exe" _info[local_version] variant \
            || [ -z "${_info[local_version]}" ]; then
            log_error game-outdated "无法读取 $game_name 的本地版本"
            return 1
        fi
        _info[local_ok]=1
        _info[variant]="$variant"
    fi

    if [ "$has_remote" -eq 1 ]; then
        local remote_version
        if remote_version="$(game_version_remote "${_info[variant]}")" \
            && [ -n "$remote_version" ]; then
            _info[remote_ok]=1
            _info[remote_version]="$remote_version"
        else
            log_error game-outdated "无法获取 $game_name 的远程版本"
        fi
    fi

    # 预下载与远程版本同源，远程失败时不再重复请求
    if [ "$has_predownload" -eq 1 ] && [ "${_info[remote_ok]}" -eq 1 ]; then
        local pre_tag
        if pre_tag="$(game_version_predownload_remote "${_info[variant]}")"; then
            _info[pre_ok]=1
            _info[pre_version]="$pre_tag"
        fi
    fi

    return 0
}

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
    _game_outdated_status gameinfo status status_style

    # 未实现 human_readable 时直接显示变体标识
    local variant_display="${_info[variant]}"
    if [ -n "$variant_display" ] \
        && [ "$(type -t game_version_variant_human_readable)" = "function" ]; then
        variant_display="$(game_version_variant_human_readable "$variant_display")"
    fi

    # 本地版本颜色跟随比较结论，无本地版本时保持默认蓝
    [ "${_info[local_ok]}" -eq 1 ] && local_style="$status_style"

    # 未定义对应函数显示 "-"，定义了但请求失败显示红字标记
    local remote_display pre_display
    if [ "$(type -t game_version_remote)" != "function" ]; then
        remote_display="-"
    elif [ "${_info[remote_ok]}" -eq 1 ]; then
        remote_display="${_info[remote_version]}"
    else
        remote_display="$(style_quote red "✗ 请求失败")"
    fi
    if [ "$(type -t game_version_predownload_remote)" != "function" ]; then
        pre_display="-"
    elif [ "${_info[pre_ok]}" -eq 1 ]; then
        if [ -n "${_info[pre_version]}" ]; then
            pre_display="$(style_quote bright_cyan "⇣ 可预下载 ${_info[pre_version]}")"
        else
            pre_display="$(style_quote bright_black "未开放")"
        fi
    else
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

# 收集 + 渲染，远程失败时已输出行并以 1 退出
_game_outdated_check() {
    local game_name="$1"
    local -A gameinfo=()

    _game_outdated_collect "$game_name" gameinfo "${2:-}"
    local collect_status=$?
    [ "$collect_status" -eq 0 ] || return "$collect_status"

    _game_outdated_render gameinfo "${2:-list}"
    [ "${gameinfo[remote_ok]}" -eq 1 ] || [ "$(type -t game_version_remote)" != "function" ]
}

command_game_outdated() {
    [ "$#" -le 1 ] || die 1 "用法: game outdated [<游戏名>]"

    load_common_config

    if [ "$#" -eq 1 ]; then
        local game_name
        game_name="$1"
        [[ "$game_name" =~ ^[[:alnum:]_-]+$ ]] || die 1 "无效的游戏名: $game_name"

        local -A gameinfo=()
        _game_outdated_collect "$game_name" gameinfo report
        local collect_status=$?
        [ "$collect_status" -ne 2 ] || die 1 game-outdated "游戏不支持版本检查: $game_name"
        [ "$collect_status" -eq 0 ] || return "$collect_status"

        _game_outdated_render gameinfo report | column -t -s $'\t'
        [ "${gameinfo[remote_ok]}" -eq 1 ] || [ "$(type -t game_version_remote)" != "function" ]
    else
        local results="" game_config game_name
        local errors=0
        for game_config in "$CONFIG_DIR"/games/*.conf; do
            [ -f "$game_config" ] || continue
            game_name="${game_config##*/}"
            game_name="${game_name%.conf}"
            [ "$game_name" != "_common" ] || continue

            local -A gameinfo=()
            _game_outdated_collect "$game_name" gameinfo
            case $? in
                0) results+="$(_game_outdated_render gameinfo list)"$'\n' ;;
                1) results+="$(_game_outdated_render gameinfo list)"$'\n'; errors=1 ;;
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
