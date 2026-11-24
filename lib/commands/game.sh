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

                # shellcheck disable=SC2034 # 供 source 的游戏实现使用
                GAME_NAME="$name"
                local game_impl="$SCRIPT_DIR/games/$name.sh"
                if [ -f "$game_impl" ]; then
                    #shellcheck source=/dev/null
                    source "$game_impl"
                fi

                if log_should_output DEBUG; then
                    load_game_config "$name"
                    game_fs_resolve_paths >/dev/null
                else
                    load_game_config "$name" 2>/dev/null
                    game_fs_resolve_paths >/dev/null 2>&1
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
        [[ "$game_name" =~ ^[[:alnum:]_-]+$ ]] || die 1 "无效的游戏名: $game_name"

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
            [ "$game_name" != "_common" ] || continue

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
