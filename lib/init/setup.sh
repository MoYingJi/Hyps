#!/hint/bash

[[ -n "${__INIT_SETUP_SH_LOADED:-}" ]] && return 0
__INIT_SETUP_SH_LOADED=1

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

# 初始化：配置目录与示例配置的脚手架
# 约定：只创建缺失的配置，已有配置默认不覆盖（--force 时先备份）

init_game_label() {
    local game="$1"
    local impl="$SCRIPT_DIR/games/$game.sh"
    local label=""

    if [ -f "$impl" ]; then
        label="$(
            # shellcheck disable=SC2034 # 供 source 的游戏实现和 game_meta_display_name 使用
            GAME_NAME="$game"
            #shellcheck source=/dev/null
            source "$impl" >/dev/null 2>&1
            game_meta_display_name
        )" || label=""
    fi

    [ -n "$label" ] || label="$game"
    printf '%s\n' "$label"
}

_init_short_path() {
    local path="$1"
    if [[ "$path" == "$PROJECT_ROOT/"* ]]; then
        printf '%s\n' "${path#"$PROJECT_ROOT"/}"
    else
        printf '%s\n' "$path"
    fi
}

# 示例配置目录：优先使用配置目录内的 games.examples，其次回退到仓库
init_example_dir() {
    local dir
    for dir in "$CONFIG_DIR/games.examples" "$PROJECT_ROOT/config/games.examples"; do
        if [[ -d "$dir" ]]; then
            printf '%s\n' "$dir"
            return 0
        fi
    done
    return 1
}

# 用法: init_example_path <游戏名>
init_example_path() {
    local slug="$1"
    local dir
    for dir in "$CONFIG_DIR/games.examples" "$PROJECT_ROOT/config/games.examples"; do
        if [[ -f "$dir/${slug}.example.conf" ]]; then
            printf '%s\n' "$dir/${slug}.example.conf"
            return 0
        fi
    done
    return 1
}

init_list_example_games() {
    local dir file slug
    dir="$(init_example_dir)" || return 1
    for file in "$dir"/*.example.conf; do
        [[ -f "$file" ]] || continue
        slug="${file##*/}"
        slug="${slug%.example.conf}"
        game_name_valid "$slug" || continue
        printf '%s\n' "$slug"
    done
}

# 用法: init_find_launcher_script <游戏名>
init_find_launcher_script() {
    local want="$1"
    local sh name
    for sh in "${SCRIPTS_DIR:-$PROJECT_ROOT/scripts}"/*.sh; do
        [[ -f "$sh" ]] || continue
        [[ "${sh##*/}" == _* ]] && continue
        game_script_name "$sh" name || continue
        if [[ "$name" == "$want" ]]; then
            printf '%s\n' "$sh"
            return 0
        fi
    done
    return 1
}

# 只读解析游戏配置，输出状态（不修改任何配置）
# runner.name 不是必需的：与 lib/config.sh 一致，runner.exe 或 runner.protonpath 有任意其一即可
init_game_config_state() (
    local slug="$1"
    local file="$CONFIG_DIR/games/$slug.conf"

    if [[ ! -f "$file" ]]; then
        printf '未配置\n'
        return 0
    fi

    local impl="$SCRIPT_DIR/games/$slug.sh"
    #shellcheck disable=SC2034 # 供加载的游戏实现使用
    GAME_NAME="$slug"
    if [[ -f "$impl" ]]; then
        #shellcheck source=/dev/null
        source "$impl" || return 1
    fi
    load_game_config "$slug" || {
        printf '配置错误\n'
        return 0
    }

    local exe install runner runner_exe runner_proton
    config_read game.exe exe
    config_read game.install_dir install
    config_read runner.name runner
    config_read runner.exe runner_exe
    config_read runner.protonpath runner_proton

    if [[ -z "$exe" && -z "$install" ]]; then
        printf '缺少 game.exe 或 game.install_dir\n'
        return 0
    fi
    if [[ -n "$exe" && "$exe" == *"/path/to/"* ]]; then
        printf '示例占位未修改\n'
        return 0
    fi
    if [[ -n "$exe" && ! -f "$exe" ]]; then
        printf 'game.exe 无效\n'
        return 0
    fi
    if [[ -n "$install" && "$install" == *"/path/to/"* ]]; then
        printf '示例占位未修改\n'
        return 0
    fi
    if [[ -n "$install" && ! -d "$install" ]]; then
        printf 'game.install_dir 无效\n'
        return 0
    fi

    # install-only 配置需要游戏实现能派生 exe
    if [[ -z "$exe" && -n "$install" ]]; then
        local derived=""
        if declare -F game_executable >/dev/null; then
            derived="$(game_executable "$install")" || derived=""
        fi
        if [[ -z "$derived" ]]; then
            printf '缺少 game.exe（该游戏不支持从 game.install_dir 派生）\n'
            return 0
        fi
        if [[ ! -f "$derived" ]]; then
            printf 'game.install_dir 无法派生有效 game.exe\n'
            return 0
        fi
    fi

    if [[ -z "$runner_exe" && -z "$runner_proton" ]]; then
        if [[ -n "$runner" ]]; then
            printf '未知 runner: %s\n' "$runner"
        else
            printf '缺少 runner.name\n'
        fi
        return 0
    fi

    printf '已配置\n'
)

init_setup_dirs() {
    local dir
    for dir in "$CONFIG_DIR" "$CONFIG_DIR/games" "$CONFIG_DIR/runners" "$CACHE_DIR" "$DATA_DIR" "$TEMP_DIR"; do
        if [[ -d "$dir" ]]; then
            log_debug init "目录已存在: $dir"
            continue
        fi
        mkdir -p -- "$dir" || die 1 init "无法创建目录: '$dir'"
        printf '  [创建] 目录: %s\n' "$dir"
    done
}

init_setup_global() {
    local dst="$CONFIG_DIR/config.conf"
    local src="$CONFIG_DIR/config.example.conf"

    if [[ -e "$dst" || -L "$dst" ]]; then
        printf '  [跳过] 全局配置已存在: %s\n' "$dst"
        return 0
    fi

    [[ -f "$src" ]] || src="$PROJECT_ROOT/config/config.example.conf"
    cp --no-clobber -- "$src" "$dst" || die 1 init "复制失败: '$src' -> '$dst'"
    printf '  [创建] 全局配置: %s（来自 %s）\n' "$dst" "$(_init_short_path "$src")"
}

init_setup_runners() {
    local src_dir="$PROJECT_ROOT/config/runners"
    local dst_dir="$CONFIG_DIR/runners"

    if [[ ! -d "$src_dir" ]]; then
        log_debug init "仓库内没有 config/runners，跳过运行器配置同步"
        return 0
    fi
    if [[ "$(realpath -m -- "$dst_dir")" == "$(realpath -m -- "$src_dir")" ]]; then
        log_debug init "配置目录与仓库 config 相同，无需同步运行器配置"
        return 0
    fi

    mkdir -p -- "$dst_dir" || die 1 init "无法创建运行器配置目录: '$dst_dir'"

    local file base
    for file in "$src_dir"/*.conf; do
        [[ -f "$file" ]] || continue
        base="${file##*/}"
        if [[ -f "$dst_dir/$base" ]]; then
            log_debug init "运行器配置已存在: $dst_dir/$base"
            continue
        fi
        cp -- "$file" "$dst_dir/$base" || die 1 init "复制运行器配置失败: '$file' -> '$dst_dir/$base'"
        printf '  [创建] 运行器配置: %s\n' "$base"
    done
}

init_setup_all() {
    printf '\n%s\n' "$(style_quote bold "[Hyps] 初始化配置")"
    init_setup_dirs
    init_setup_global
    init_setup_runners
}

# 用法: init_setup_game <游戏名> [force]
init_setup_game() {
    local slug="$1"
    local force="${2:-0}"
    local src dst backup

    game_name_valid "$slug" || die 1 init "无效的游戏名 '$slug'"
    src="$(init_example_path "$slug")" || die 1 init "未知游戏 '$slug'：找不到 $slug.example.conf"
    dst="$CONFIG_DIR/games/$slug.conf"

    if [[ -f "$dst" && "$force" -ne 1 ]]; then
        printf '  [跳过] %s.conf 已存在（覆盖请加 --force）\n' "$slug"
        _init_print_game_next_steps "$slug"
        return 0
    fi

    if [[ -f "$dst" ]]; then
        backup="$dst.bak.$(date +%Y%m%d%H%M%S)"
        while [[ -e "$backup" ]]; do
            backup="${backup}_"
        done
        cp -p -- "$dst" "$backup" || die 1 init "备份失败: '$dst' -> '$backup'"
        printf '  [备份] %s\n' "$backup"
    fi

    cp -- "$src" "$dst" || die 1 init "复制失败: '$src' -> '$dst'"
    printf '  [创建] %s.conf（来自 %s）\n' "$slug" "$(_init_short_path "$src")"
    _init_print_game_next_steps "$slug"
}

_init_runner_names() {
    local dir="$CONFIG_DIR/runners"
    local joined=""
    local file base name
    for file in "$dir"/*.conf; do
        [[ -f "$file" ]] || continue
        base="${file##*/}"
        name="${base%.conf}"
        if [[ -z "$joined" ]]; then
            joined="$name"
        else
            joined+=", $name"
        fi
    done
    printf '%s\n' "${joined:-无}"
}

_init_print_game_next_steps() {
    local slug="$1"
    local launcher

    printf '\n  还需要编辑 %s：\n' "$CONFIG_DIR/games/$slug.conf"
    printf '    game.exe    = 游戏可执行文件的绝对路径\n'
    printf '    runner.name = 运行器，可选: %s\n' "$(_init_runner_names)"

    if launcher="$(init_find_launcher_script "$slug")"; then
        printf '  配置完成后运行: %s\n' "$(_init_short_path "$launcher")"
    else
        printf '  配置完成后运行: ./scripts/_Hyps run %s\n' "$slug"
    fi
    printf '  查看状态: ./scripts/_Hyps game list\n'
}
