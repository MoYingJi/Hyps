#!/usr/bin/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

#shellcheck source=../init/check.sh
source "$SCRIPT_DIR/init/check.sh"

#shellcheck source=../init/setup.sh
source "$SCRIPT_DIR/init/setup.sh"

INIT_COMMON_LOADED=0

help_init() {
    cat << 'EOF'
初始化 Hyps 配置并检测基础环境

用法:
  init [选项] [游戏名]
  init check            仅检测环境，不写入文件
  init list             列出游戏示例配置与当前配置状态
  init config           只初始化基础配置（目录、_common.conf、runners）
  init game <游戏名>     初始化基础配置并复制指定游戏的示例配置

选项:
  --check               等价于 init check
  --list                等价于 init list
  --no-game             只初始化基础配置，不做游戏选择
  --force               目标配置已存在时先备份再覆盖
  -h, --help            显示本帮助

示例:
  ./init.sh
  ./init.sh endfield
  ./init.sh --check
EOF
}

_init_load_common_config() {
    [[ "$INIT_COMMON_LOADED" -eq 1 ]] && return 0
    load_common_config
    INIT_COMMON_LOADED=1
}

_init_run_check() {
    init_check_all
    init_check_report
    init_check_ok
}

_init_table() {
    if command_exists column; then
        column -t -s $'\t'
    else
        cat
    fi
}

_init_print_manual_hint() {
    printf '\n  下一步:\n'
    printf '    1. ./init.sh <游戏名>                     # 复制示例配置\n'
    printf '    2. 编辑 %s/games/<游戏名>.conf\n' "$CONFIG_DIR"
    printf '        修改 game.exe 与 runner.name\n'
    printf '    3. ./scripts/<对应脚本>.sh                 # 启动游戏\n'
}

command_init() {
    [[ "$UID" -ne 0 ]] || die 1 init "请以普通用户运行，不要使用 root"

    local do_check=0 do_list=0 no_game=0 force=0
    local game=""

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --check)    do_check=1 ;;
            --list)     do_list=1 ;;
            --no-game)  no_game=1 ;;
            --force|-f) force=1 ;;
            -h|--help)  help_init; return 0 ;;
            -*)         die 2 init "未知选项: '$1'（使用 -h 查看用法）" ;;
            *)
                [[ -z "$game" ]] || die 2 init "一次只能指定一个游戏名（多余: '$1'）"
                game="$1"
                ;;
        esac
        shift
    done

    if [[ "$do_check" -eq 1 && "$do_list" -eq 1 ]]; then
        die 2 init "--check 与 --list 不能同时使用"
    fi
    if [[ -n "$game" && ( "$do_check" -eq 1 || "$do_list" -eq 1 ) ]]; then
        die 2 init "--check / --list 不能与游戏名一起使用"
    fi
    if [[ -n "$game" && "$no_game" -eq 1 ]]; then
        die 2 init "游戏名与 --no-game 不能同时使用"
    fi

    _init_load_common_config

    if [[ "$do_list" -eq 1 ]]; then
        command_init_list "$@"
        return
    fi
    if [[ "$do_check" -eq 1 ]]; then
        _init_run_check
        return
    fi

    _init_run_check
    local check_status=$?
    if [[ "$check_status" -ne 0 ]]; then
        printf '\n%s\n' "$(style_quote red "存在必需项缺失，配置仍会生成，但请先处理 [✗] 项")"
    fi

    init_setup_all

    if [[ -n "$game" ]]; then
        init_setup_game "$game" "$force"
    elif [[ "$no_game" -eq 1 ]]; then
        printf '\n  已跳过游戏配置（--no-game）\n'
        _init_print_manual_hint
    elif [[ -t 0 ]]; then
        _init_select_games "$force"
    else
        printf '\n  非交互环境：使用 ./init.sh <游戏名> 复制对应的示例配置\n'
        _init_print_manual_hint
    fi

    printf '\n%s\n' "$(style_quote bold "[Hyps] 完成")"
    printf '  配置目录: %s\n' "$CONFIG_DIR"
    printf '  查看状态: ./scripts/_Hyps game list\n'

    return "$check_status"
}

command_init_check() {
    [[ "$#" -eq 0 ]] || die 1 init "init check 不接受参数"

    _init_load_common_config
    _init_run_check
}

command_init_list() {
    [[ "$#" -eq 0 ]] || die 1 init "init list 不接受参数"

    _init_load_common_config

    local -a games=()
    mapfile -t games < <(init_list_example_games)
    if [[ "${#games[@]}" -eq 0 ]]; then
        die 1 init "没有找到任何示例配置（games.examples）"
    fi

    local slug state launcher
    {
        printf '游戏\t配置状态\t启动脚本\t名称\n'
        for slug in "${games[@]}"; do
            state="$(init_game_config_state "$slug")"
            if launcher="$(init_find_launcher_script "$slug")"; then
                launcher="$(_init_short_path "$launcher")"
            else
                launcher="-"
            fi
            printf '%s\t%s\t%s\t%s\n' "$slug" "$state" "$launcher" "$(init_game_label "$slug")"
        done
    } | _init_table
}

command_init_config() {
    [[ "$#" -eq 0 ]] || die 1 init "init config 不接受参数"

    _init_load_common_config
    init_setup_all
}

command_init_game() {
    local force=0
    local game=""

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --force|-f) force=1 ;;
            -h|--help)  help_init; return 0 ;;
            -*)         die 2 init "未知选项: '$1'" ;;
            *)
                [[ -z "$game" ]] || die 2 init "一次只能指定一个游戏名（多余: '$1'）"
                game="$1"
                ;;
        esac
        shift
    done

    [[ -n "$game" ]] || die 2 init "用法: init game <游戏名> [--force]"

    _init_load_common_config
    init_setup_all
    init_setup_game "$game" "$force"
}

_init_select_games() {
    local force="$1"
    local -a games=()
    mapfile -t games < <(init_list_example_games)

    if [[ "${#games[@]}" -eq 0 ]]; then
        printf '\n  没有找到任何示例配置（games.examples），仓库可能不完整\n'
        return 0
    fi

    printf '\n可选游戏:\n'
    local i slug state
    for i in "${!games[@]}"; do
        slug="${games[$i]}"
        state="$(init_game_config_state "$slug")"
        printf '  %2d) %-14s %s（%s）\n' "$(( i + 1 ))" "$slug" "$(init_game_label "$slug")" "$state"
    done

    local line
    printf '\n选择要初始化的游戏（编号或名称，空格分隔；回车跳过）: '
    if ! IFS= read -r line; then
        printf '\n'
        return 0
    fi
    [[ -z "$line" ]] && return 0

    local choice idx
    for choice in $line; do
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            idx=$(( choice - 1 ))
            if [[ "$idx" -lt 0 || "$idx" -ge "${#games[@]}" ]]; then
                printf '  [警告] 无效编号: %s\n' "$choice"
                continue
            fi
            slug="${games[$idx]}"
        else
            if ! printf '%s\n' "${games[@]}" | grep -qx -- "$choice"; then
                printf '  [警告] 未知游戏: %s\n' "$choice"
                continue
            fi
            slug="$choice"
        fi
        init_setup_game "$slug" "$force"
    done
}
