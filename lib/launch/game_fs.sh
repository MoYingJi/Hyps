#!/hint/bash

[[ -n "${__LAUNCH_GAME_FS_SH_LOADED:-}" ]] && return 0
__LAUNCH_GAME_FS_SH_LOADED=1

# 游戏文件系统视图
# 作用域和生命周期见 docs/DEVELOPMENT.md

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

declare -gA GAME_FS=()

_game_fs_require_init() {
    [ "${GAME_FS[initialized]:-0}" = "1" ] || {
        log_error game-fs "GAME_FS 尚未初始化"
        return 1
    }
}

_game_fs_require_install() {
    [ "${GAME_FS[install_ok]:-0}" = "1" ] || {
        log_error game-fs "install 视图不可用：缺少 game.install_dir 或 game_install_dir"
        return 1
    }
}

# 解析 exe / install / cwd
# 至少需要 game.exe 或 game.install_dir
# 结果写入 GAME_FS，并写回 CONFIG[game.exe] / CONFIG[game.cwd]
game_fs_resolve_paths() {
    local config_exe config_install config_cwd
    local exe="" install=""
    local round="" cwd=""

    config_read game.exe config_exe
    config_read game.install_dir config_install
    config_read game.cwd config_cwd

    if [ -n "$config_exe" ]; then
        exe="$(realpath -m -- "$config_exe")"
        [ -f "$exe" ] || {
            log_error game-fs "game.exe 不存在: '$exe'"
            return 1
        }
    fi
    if [ -n "$config_install" ]; then
        install="$(realpath -m -- "$config_install")"
        [ -d "$install" ] || {
            log_error game-fs "game.install_dir 不存在: '$install'"
            return 1
        }
    fi

    if [ -z "$exe" ] && [ -z "$install" ]; then
        log_error game-fs "至少需要 game.exe 或 game.install_dir"
        return 1
    fi

    if [ -n "$exe" ] && [ -z "$install" ]; then
        if [ "$(type -t game_install_dir)" = "function" ]; then
            install="$(game_install_dir "$exe")" || {
                log_error game-fs "game_install_dir 执行失败: '$exe'"
                return 1
            }
            [ -n "$install" ] || {
                log_error game-fs "game_install_dir 返回空路径: '$exe'"
                return 1
            }
        elif [ "$(type -t overlay_auto_lower)" = "function" ]; then
            log_warn game-fs "游戏仍在使用 overlay_auto_lower，请迁移到 game_install_dir"
            install="$(overlay_auto_lower "$exe")" || {
                log_error game-fs "overlay_auto_lower 执行失败: '$exe'"
                return 1
            }
            [ -n "$install" ] || {
                log_error game-fs "overlay_auto_lower 返回空路径: '$exe'"
                return 1
            }
        fi
        if [ -n "$install" ]; then
            install="$(realpath -m -- "$install")"
            [ -d "$install" ] || {
                log_error game-fs "install 根目录不存在: '$install'"
                return 1
            }
            case "$exe" in
                "$install"/*) ;;
                *)
                    log_error game-fs "game.exe 不在 install 根内: '$exe' (install: '$install')"
                    return 1
                    ;;
            esac
        fi
    elif [ -z "$exe" ] && [ -n "$install" ]; then
        if [ "$(type -t game_executable)" != "function" ]; then
            log_error game-fs "只填 game.install_dir 时需要 game_executable"
            return 1
        fi
        exe="$(game_executable "$install")" || {
            log_error game-fs "game_executable 执行失败: '$install'"
            return 1
        }
        case "$exe" in
            *$'\n'*)
                log_error game-fs "game_executable 只能返回一个主 exe"
                return 1
                ;;
            /*) ;;
            *)
                log_error game-fs "game_executable 必须返回绝对路径: '$exe'"
                return 1
                ;;
        esac
        [ -n "$exe" ] || {
            log_error game-fs "game_executable 返回空路径"
            return 1
        }
        exe="$(realpath -m -- "$exe")"
        [ -f "$exe" ] || {
            log_error game-fs "game_executable 返回的 exe 不存在: '$exe'"
            return 1
        }
        case "$exe" in
            "$install"/*) ;;
            *)
                log_error game-fs "game_executable 返回的 exe 不在 install 根内: '$exe'"
                return 1
                ;;
        esac
        if [ "$(type -t game_install_dir)" = "function" ]; then
            round="$(game_install_dir "$exe")" || {
                log_error game-fs "game_install_dir 执行失败: '$exe'"
                return 1
            }
            round="$(realpath -m -- "$round")"
            [ "$round" = "$install" ] || {
                log_error game-fs "game_install_dir 与 game_executable 不一致: '$round' != '$install'"
                return 1
            }
        fi
    else
        case "$exe" in
            "$install"/*) ;;
            *)
                log_error game-fs "game.exe 不在 install 根内: '$exe' (install: '$install')"
                return 1
                ;;
        esac
        if [ "$(type -t game_install_dir)" = "function" ]; then
            round="$(game_install_dir "$exe")" || round=""
            if [ -n "$round" ]; then
                round="$(realpath -m -- "$round")"
                [ "$round" = "$install" ] || log_warn game-fs "game_install_dir 与 game.install_dir 不一致，使用 game.install_dir: '$round' != '$install'"
            fi
        fi
    fi

    GAME_FS[game_exe_install]="$exe"
    GAME_FS[install_dir]="$install"
    GAME_FS[install_ok]=0
    [ -n "$install" ] && GAME_FS[install_ok]=1

    if [ -n "$config_cwd" ]; then
        cwd="$(realpath -m -- "$config_cwd")"
        [ -d "$cwd" ] || {
            log_error game-fs "game.cwd 不是目录: '$cwd'"
            return 1
        }
    elif [ "${GAME_FS[install_ok]}" = "1" ]; then
        cwd="$install"
        log_debug game-fs "game.cwd 未配置，使用 install 根: '$cwd'"
    else
        path_dirname "$exe" cwd
        log_debug game-fs "game.cwd 未配置，install 未知，使用 exe 目录: '$cwd'"
    fi
    GAME_FS[game_cwd_install]="$cwd"

    config_set game.exe "$exe"
    config_set game.cwd "$cwd"
}

# 将 install 在 lower 中的偏移拼到 overlay 视图根上
_game_fs_view_root() {
    local root="$1"
    local rel="$2"
    if [ -z "$rel" ] || [ "$rel" = "." ]; then
        printf '%s\n' "$root"
    else
        printf '%s\n' "$root/$rel"
    fi
}

# 解析 overlay 路径，不创建目录不挂载
game_fs_init_overlay() {
    local install_dir="$1"

    [ -n "$install_dir" ] || {
        log_error game-fs "overlay 需要 install 根"
        return 1
    }

    local backend
    config_read overlay.backend backend "fuse"
    case "$backend" in
        fuse | kernel) ;;
        *)
            log_error game-fs "'overlay.backend' 只能是 fuse 或 kernel: '$backend'"
            return 1
            ;;
    esac
    GAME_FS[overlay_backend]="$backend"

    local lower
    if config_has overlay.lower; then
        config_read overlay.lower lower
        [ -n "$lower" ] || {
            log_error game-fs "配置项 'overlay.lower' 不能为空"
            return 1
        }
        lower="$(realpath -m -- "$lower")"
    else
        # 默认 lower 为游戏安装目录
        lower="$install_dir"
    fi
    if [ ! -d "$lower" ]; then
        log_error game-fs "overlay lower 目录不存在: '$lower'"
        return 1
    fi
    GAME_FS[overlay_lower]="$lower"

    local overlay_dir
    config_read overlay.dir overlay_dir "$DATA_DIR/overlays"
    [ -n "$overlay_dir" ] || overlay_dir="$DATA_DIR/overlays"
    overlay_dir="$(realpath -m -- "$overlay_dir")/$GAME_NAME"

    local mount upper work
    if config_has overlay.mount; then
        config_read overlay.mount mount
    fi
    [ -n "${mount:-}" ] || mount="$overlay_dir/mount"
    if config_has overlay.upper; then
        config_read overlay.upper upper
    fi
    [ -n "${upper:-}" ] || upper="$overlay_dir/upper"
    if config_has overlay.work; then
        config_read overlay.work work
    fi
    [ -n "${work:-}" ] || work="$overlay_dir/work"

    mount="$(realpath -m -- "$mount")"
    upper="$(realpath -m -- "$upper")"
    work="$(realpath -m -- "$work")"

    local path
    for path in "$lower" "$mount" "$upper" "$work"; do
        [ -n "$path" ] || {
            log_error game-fs "overlay 路径不能为空"
            return 1
        }
        [ "$path" != "/" ] || {
            log_error game-fs "overlay 路径不能是 /"
            return 1
        }
    done

    if [ "$upper" = "$lower" ] || [ "$work" = "$lower" ] || [ "$mount" = "$lower" ]; then
        log_error game-fs "overlay 的 mount/upper/work 不能与 lower 相同: '$lower'"
        return 1
    fi
    if [ "$mount" = "$upper" ] || [ "$mount" = "$work" ] || [ "$upper" = "$work" ]; then
        log_error game-fs "overlay 的 mount/upper/work 必须互不相同"
        return 1
    fi

        if [[ "$mount/" == "$upper"/* || "$mount/" == "$work"/* ]] \
        || [[ "$upper/" == "$mount"/* || "$work/" == "$mount"/* ]] \
        || [[ "$upper/" == "$work"/* || "$work/" == "$upper"/* ]]; then
        log_error game-fs "overlay 的 mount/upper/work 不能互相嵌套: '$mount' / '$upper' / '$work'"
        return 1
    fi

    # upper/work 位于 lower 内会导致 overlay 递归
    if [[ "$upper/" == "$lower"/* ]]; then
        log_error game-fs "overlay upper 不能位于 lower 内: '$upper'"
        return 1
    fi
    if [[ "$work/" == "$lower"/* ]]; then
        log_error game-fs "overlay work 不能位于 lower 内: '$work'"
        return 1
    fi
        if [[ "$lower/" == "$upper"/* || "$lower/" == "$work"/* || "$lower/" == "$mount"/* ]]; then
        log_error game-fs "overlay lower 不能位于 upper/work/mount 内: '$lower'"
        return 1
    fi

    local install_rel
    install_rel="$(realpath -m --relative-to="$lower" -- "$install_dir")" || {
        log_error game-fs "无法计算 install 相对于 lower 的偏移: '$install_dir' (lower: '$lower')"
        return 1
    }
    case "$install_rel" in
        /* | ../* | ..)
            log_error game-fs "install 根不在 overlay lower 内: '$install_dir' (lower: '$lower')"
            return 1
            ;;
    esac
    GAME_FS[install_rel_lower]="$install_rel"
    GAME_FS[overlay_mount]="$mount"
    GAME_FS[overlay_upper]="$upper"
    GAME_FS[overlay_work]="$work"
    # 按 upper 标识会话，修改 mount/work 配置也不能绕过旧后端的占用
    local upper_key
    upper_key="$(printf '%s' "$upper" | sha256sum)" || return 1
    GAME_FS[overlay_session_file]="$STATE_DIR/overlay/${upper_key%% *}.session"
    GAME_FS[lower_view]="$(_game_fs_view_root "$lower" "$install_rel")"
    GAME_FS[upper_view]="$(_game_fs_view_root "$upper" "$install_rel")"
    GAME_FS[runtime_dir]="$(_game_fs_view_root "$mount" "$install_rel")"
    GAME_FS[writable_dir]="$(_game_fs_view_root "$upper" "$install_rel")"
}

# 派生 runtime exe/cwd
game_fs_init_runtime_exe() {
    local game_exe="$1"
    local game_cwd="$2"

    if [ "${GAME_FS[overlay_enabled]}" != "1" ]; then
        GAME_FS[game_exe_runtime]="$game_exe"
        GAME_FS[game_cwd_runtime]="$game_cwd"
        return 0
    fi

    local lower="${GAME_FS[overlay_lower]}"
    local mount="${GAME_FS[overlay_mount]}"
    local rel

    rel="$(realpath -m --relative-to="$lower" -- "$game_exe")" || {
        log_error game-fs "无法计算游戏 exe 相对于 lower 的路径: '$game_exe'"
        return 1
    }
    case "$rel" in
        /* | ../* | ..)
            log_error game-fs "游戏 exe 不在 overlay lower 内: '$game_exe' (lower: '$lower')"
            return 1
            ;;
    esac
    GAME_FS[game_exe_runtime]="$mount/$rel"

    case "$game_cwd/" in
        "$lower"/*)
            rel="$(realpath -m --relative-to="$lower" -- "$game_cwd")" || {
                log_error game-fs "无法计算游戏工作目录相对于 lower 的路径: '$game_cwd'"
                return 1
            }
            case "$rel" in
                /* | ../* | ..)
                    log_error game-fs "游戏工作目录不在 overlay lower 内: '$game_cwd' (lower: '$lower')"
                    return 1
                    ;;
            esac
            if [ "$rel" = "." ]; then
                GAME_FS[game_cwd_runtime]="$mount"
            else
                GAME_FS[game_cwd_runtime]="$mount/$rel"
            fi
            ;;
        *)
            # cwd 不在 lower 内时不映射
            GAME_FS[game_cwd_runtime]="$game_cwd"
            ;;
    esac
}

# 初始化 GAME_FS，不写文件不挂载
game_fs_init() {
    # 重新初始化也不能遗忘仍在使用 upper 的后端
    if [ "${GAME_FS[overlay_mounted_by_us]:-0}" = 1 ] \
        || [ "${GAME_FS[overlay_unmount_deferred]:-0}" = 1 ]; then
        game_fs_require_offline || return 1
    fi
    GAME_FS=()
    GAME_FS[initialized]=1
    GAME_FS[phase]=init
    GAME_FS[game_name]="$GAME_NAME"

    game_fs_resolve_paths || return 1

    local game_exe="${GAME_FS[game_exe_install]}"
    local game_cwd="${GAME_FS[game_cwd_install]}"
    local install_dir="${GAME_FS[install_dir]}"

    local prefix
    config_read game.prefix prefix
    GAME_FS[prefix]="$(realpath -m -- "$prefix")"
    GAME_FS[drive_c]=""
    GAME_FS[userprofile]=""
    GAME_FS[userprofile_ok]=0
    GAME_FS[overlay_mounted]=0
    GAME_FS[overlay_mounted_by_us]=0
    GAME_FS[overlay_backend]=""

    local overlay_enabled=0
    config_is_true overlay.enabled && overlay_enabled=1
    GAME_FS[overlay_enabled]="$overlay_enabled"

    if [ "$overlay_enabled" -eq 1 ]; then
        [ "${GAME_FS[install_ok]}" = "1" ] || {
            log_error game-fs "overlay 需要 install 根：设置 game.install_dir 或实现 game_install_dir"
            return 1
        }
        game_fs_init_overlay "$install_dir" || return 1
    else
        GAME_FS[overlay_lower]="$install_dir"
        GAME_FS[overlay_mount]=""
        GAME_FS[overlay_upper]=""
        GAME_FS[overlay_work]=""
        GAME_FS[install_rel_lower]="."
        GAME_FS[lower_view]="$install_dir"
        GAME_FS[upper_view]="$install_dir"
        GAME_FS[runtime_dir]="$install_dir"
        GAME_FS[writable_dir]="$install_dir"
    fi

    game_fs_init_runtime_exe "$game_exe" "$game_cwd" || return 1

    # 记录外部挂载
    if [ "$overlay_enabled" -eq 1 ] && game_fs_overlay_mounted; then
        GAME_FS[overlay_mounted]=1
    fi

    log_debug game-fs "install_ok=${GAME_FS[install_ok]} install_dir=${GAME_FS[install_dir]}"
    log_debug game-fs "runtime_dir=${GAME_FS[runtime_dir]}"
    log_debug game-fs "writable_dir=${GAME_FS[writable_dir]}"
    if [ "$overlay_enabled" -eq 1 ]; then
        log_debug game-fs "overlay backend=${GAME_FS[overlay_backend]} lower=${GAME_FS[overlay_lower]} mount=${GAME_FS[overlay_mount]} upper=${GAME_FS[overlay_upper]} work=${GAME_FS[overlay_work]}"
        if [ "${GAME_FS[overlay_mounted]}" = "1" ]; then
            log_warn game-fs "检测到 overlay 挂载点已处于挂载状态: '${GAME_FS[overlay_mount]}'"
        fi
    fi

    return 0
}

game_fs_set_phase() {
    _game_fs_require_init || return 1
    case "$1" in
        init|offline|prepare_offline|prepare|pre_start|post_start|cleanup|cleanup_offline) ;;
        *)
            log_error game-fs "未知阶段: '$1'"
            return 1
            ;;
    esac
    GAME_FS[phase]="$1"
}

game_fs_assert_mutation() {
    _game_fs_require_init || return 1
    local scope="$1"

    case "$scope" in
        install|lower|runtime|writable|upper|all|prefix|userprofile|cache|data|state|temp) ;;
        *)
            log_error game-fs "未知路径作用域: '$scope'"
            return 1
            ;;
    esac

    if [ "${GAME_FS[phase]}" = "init" ]; then
        log_error game-fs "load_config 阶段不能写路径"
        return 1
    fi

    case "$scope" in
        install|lower|runtime|writable|upper|all)
            _game_fs_require_install || return 1
            ;;
    esac

    [ "${GAME_FS[overlay_enabled]}" = "1" ] || return 0

    case "$scope" in
        prefix|userprofile|cache|data|state|temp) return 0 ;;
    esac

    case "${GAME_FS[phase]}" in
        prepare_offline|cleanup_offline|offline)
            [ "$scope" != "runtime" ] || {
                log_error game-fs "offline 阶段没有 runtime 视图"
                return 1
            }
            ;;
        prepare|pre_start|post_start|cleanup)
            case "$scope" in
                install|lower|upper|writable|all)
                    log_error game-fs "runtime 阶段不能直接写 $scope"
                    return 1
                    ;;
            esac
            ;;
        *)
            log_error game-fs "当前阶段不允许写路径: '${GAME_FS[phase]}'"
            return 1
            ;;
    esac
}

game_fs_write_path() {
    local scope="$1" rel="$2"
    game_fs_assert_mutation "$scope" || return 1
    game_fs_path "$scope" "$rel"
}

# 延迟解析 prefix 用户目录
# 用法: game_fs_resolve_user_dirs [module]
game_fs_resolve_user_dirs() {
    _game_fs_require_init || return 1
    [ "${GAME_FS[userprofile_ok]}" = "1" ] && return 0

    local module="${1:-game-fs}"
    local prefix="${GAME_FS[prefix]}"
    local drive_c userprofile
    if ! wine_resolve_user_dirs "$module" "$prefix" drive_c userprofile; then
        return 1
    fi

    GAME_FS[drive_c]="$drive_c"
    GAME_FS[userprofile]="$userprofile"
    GAME_FS[userprofile_ok]=1
}

# 用法: game_fs_root <scope>
game_fs_root() {
    _game_fs_require_init || return 1
    local scope="$1"

    case "$scope" in
        install)
            _game_fs_require_install || return 1
            printf '%s\n' "${GAME_FS[install_dir]}"
            ;;
        lower)
            _game_fs_require_install || return 1
            printf '%s\n' "${GAME_FS[lower_view]}"
            ;;
        runtime)
            _game_fs_require_install || return 1
            printf '%s\n' "${GAME_FS[runtime_dir]}"
            ;;
        writable)
            _game_fs_require_install || return 1
            printf '%s\n' "${GAME_FS[writable_dir]}"
            ;;
        upper)
            _game_fs_require_install || return 1
            if [ "${GAME_FS[overlay_enabled]}" = "1" ]; then
                printf '%s\n' "${GAME_FS[upper_view]}"
            else
                printf '%s\n' "${GAME_FS[install_dir]}"
            fi
            ;;
        prefix) printf '%s\n' "${GAME_FS[prefix]}" ;;
        userprofile)
            game_fs_resolve_user_dirs || return 1
            printf '%s\n' "${GAME_FS[userprofile]}"
            ;;
        cache) printf '%s\n' "$CACHE_DIR" ;;
        data) printf '%s\n' "$DATA_DIR" ;;
        state) printf '%s\n' "$STATE_DIR" ;;
        temp) printf '%s\n' "$TEMP_DIR" ;;
        *)
            log_error game-fs "未知的路径作用域: '$scope'"
            return 1
            ;;
    esac
}

# 拼接根与相对路径，校验越界
# 用法: _game_fs_join <root> <relpath> [allow_symlink_escape]
# allow_symlink_escape=1 用于 userprofile/cache 等前缀目录，允许中间级符号链接
_game_fs_join() {
    local root="$1"
    local rel="$2"
    local allow_symlink_escape="${3:-0}"
    local path

    [ -n "$root" ] || {
        log_error game-fs "路径根为空"
        return 1
    }
    [ "$root" != "/" ] || {
        log_error game-fs "路径根不能是 /"
        return 1
    }
    [ -n "$rel" ] || {
        log_error game-fs "相对路径不能为空"
        return 1
    }
    case "$rel" in
        /*)
            log_error game-fs "不允许绝对路径: '$rel'"
            return 1
            ;;
        *$'\n'* | *$'\t'*)
            log_error game-fs "路径包含非法字符: '$rel'"
            return 1
            ;;
    esac

    if [ "$allow_symlink_escape" = "1" ]; then
        # 前缀目录中的符号链接是正常结构；只做词法规范化，不跟随链接
        path="$(realpath -m -s -- "$root/$rel")" || {
            log_error game-fs "无法解析路径: '$root/$rel'"
            return 1
        }
        if [ "$path" = "$root" ] || [[ "$path" != "$root"/* ]]; then
            log_error game-fs "路径越界: '$rel' (根: '$root')"
            return 1
        fi
        printf '%s\n' "$path"
        return 0
    fi

    local dir base parent
    path_dirname "$rel" dir
    base="${rel##*/}"
    case "$base" in
        "" | "." | "..")
            log_error game-fs "相对路径结尾无效: '$rel'"
            return 1
            ;;
    esac

    # 只解析父目录，保留最后一级符号链接本身
    # 末级链接指向根外时仍可删除/修复，中间级链接越界仍会被拒绝
    parent="$(realpath -m -- "$root/$dir")" || {
        log_error game-fs "无法解析父目录: '$root/$dir'"
        return 1
    }
    if [ "$parent" != "$root" ] && [[ "$parent" != "$root"/* ]]; then
        log_error game-fs "路径越界: '$rel' (根: '$root')"
        return 1
    fi

    printf '%s\n' "$parent/$base"
}

# 用法: game_fs_path <scope> <relpath>
# scope=all 请用 game_fs_paths
game_fs_path() {
    _game_fs_require_init || return 1
    local scope="$1"
    local rel="$2"
    local root

    local allow_symlink_escape=0
    case "$scope" in
        all)
            game_fs_paths all "$rel"
            return
            ;;
        prefix | userprofile | cache | data | state | temp)
            allow_symlink_escape=1
            root="$(game_fs_root "$scope")" || return 1
            ;;
        *)
            root="$(game_fs_root "$scope")" || return 1
            ;;
    esac

    _game_fs_join "$root" "$rel" "$allow_symlink_escape"
}

# 用法: game_fs_paths <scope> <relpath>
# 每行 <view>\t<path>
# all: offline 输出 install，运行时输出 lower/upper
game_fs_paths() {
    _game_fs_require_init || return 1
    local scope="$1"
    local rel="$2"

    if [ "$scope" != "all" ]; then
        local path
        path="$(game_fs_path "$scope" "$rel")" || return 1
        printf '%s\t%s\n' "$scope" "$path"
        return 0
    fi

    if [ "${GAME_FS[overlay_enabled]}" != "1" ]; then
        local install
        install="$(game_fs_path install "$rel")" || return 1
        printf 'install\t%s\n' "$install"
        return 0
    fi

    local lower upper
    lower="$(game_fs_path lower "$rel")" || return 1
    upper="$(game_fs_path upper "$rel")" || return 1
    printf 'lower\t%s\n' "$lower"
    [ "$upper" = "$lower" ] || printf 'upper\t%s\n' "$upper"
}

# 挂载点是否处于挂载状态
game_fs_overlay_mounted() {
    [ "${GAME_FS[overlay_enabled]:-0}" = "1" ] || return 1
    local mount="${GAME_FS[overlay_mount]:-}"
    [ -n "$mount" ] || return 1

    if command_exists mountpoint; then
        mountpoint -q -- "$mount" 2>/dev/null
    else
        findmnt -n -M "$mount" >/dev/null 2>&1
    fi
}

# 旧会话记录只用于判断占用，不用于向旧进程发送信号
_game_fs_require_released() {
    if _game_fs_fuse_running; then
        log_error game-fs "本次 FUSE 服务尚未退出，不能离线操作或复用 upper"
        return 1
    fi
    local file="${GAME_FS[overlay_session_file]:-}"
    [ -n "$file" ] && [ -e "$file" ] || return 0

    local backend boot pid starttime current_boot
    if ! IFS=$'\t' read -r backend boot pid starttime < "$file" \
        || ! IFS= read -r current_boot < /proc/sys/kernel/random/boot_id; then
        log_error game-fs "无法读取 overlay 会话记录，拒绝离线操作: '$file'"
        return 1
    fi
    [ -n "$boot" ] && [[ "$pid" =~ ^[0-9]+$ && "$starttime" =~ ^[0-9]+$ ]] || {
        log_error game-fs "overlay 会话记录无效，拒绝离线操作: '$file'"
        return 1
    }
    case "$backend" in
        fuse|kernel) ;;
        *)
            log_error game-fs "overlay 会话记录包含未知后端: '$file'"
            return 1
            ;;
    esac
    [ "$boot" = "$current_boot" ] || return 0

    if [ "$backend" = fuse ]; then
        if ! process_is_running "$pid" "$starttime"; then
            return 0
        fi
        log_error game-fs "旧 FUSE 服务仍在使用 overlay upper (PID: $pid)"
    else
        log_error game-fs "旧 overlay 已懒卸载，无法确认后端已释放"
        log_error game-fs "确认旧挂载已释放后再移除会话记录，或重启系统: '$file'"
    fi
    return 1
}

_game_fs_record_session() {
    local pid="${1:-0}" starttime="${2:-0}"
    local file="${GAME_FS[overlay_session_file]}" boot tmp
    IFS= read -r boot < /proc/sys/kernel/random/boot_id || return 1
    mkdir -p -- "${file%/*}" || return 1
    tmp="$(mktemp "$file.XXXXXX")" || return 1
    if ! printf '%s\t%s\t%s\t%s\n' "${GAME_FS[overlay_backend]}" "$boot" "$pid" "$starttime" > "$tmp" \
        || ! mv -f -- "$tmp" "$file"; then
        rm -f -- "$tmp"
        return 1
    fi
}

_game_fs_fuse_running() {
    process_is_running "${GAME_FS[overlay_fuse_pid]:-}" "${GAME_FS[overlay_fuse_starttime]:-}"
}

# 只向本次直接启动的服务发信号，不能按进程名终止服务
_game_fs_stop_fuse() {
    local pid="${GAME_FS[overlay_fuse_pid]:-}" attempt
    [ -n "$pid" ] || {
        log_error game-fs "没有本次 FUSE 服务的 PID，无法确认后端已停止"
        return 1
    }
    if _game_fs_fuse_running; then
        kill -TERM "$pid" 2>/dev/null || {
            _game_fs_fuse_running && return 1
        }
        for ((attempt = 0; attempt < 50; attempt++)); do
            _game_fs_fuse_running || break
            sleep 0.1
        done
        if _game_fs_fuse_running; then
            log_error game-fs "FUSE 服务尚未退出，保留会话记录并跳过离线清理 (PID: $pid)"
            return 1
        fi
    fi
    wait "$pid" 2>/dev/null || true
}

_game_fs_umount() {
    local lazy="${1:-0}" mount="${GAME_FS[overlay_mount]}"
    if [ "${GAME_FS[overlay_backend]}" = fuse ]; then
        if command_exists fusermount3; then
            if [ "$lazy" -eq 1 ]; then fusermount3 -uz "$mount"; else fusermount3 -u "$mount"; fi
            return $?
        elif command_exists fusermount; then
            if [ "$lazy" -eq 1 ]; then fusermount -uz "$mount"; else fusermount -u "$mount"; fi
            return $?
        fi
    fi
    command_exists umount || {
        log_error game-fs "没有可用的 overlay 卸载命令"
        return 1
    }
    if [ "$lazy" -eq 1 ]; then umount -l "$mount"; else umount "$mount"; fi
}

# 启动前检查挂载和 backend
game_fs_require_launchable() {
    _game_fs_require_init || return 1
    [ "${GAME_FS[overlay_enabled]}" = "1" ] || return 0
    _game_fs_require_install || return 1

    if game_fs_overlay_mounted; then
        log_error game-fs "overlay 挂载点已处于挂载状态: '${GAME_FS[overlay_mount]}'"
        log_error game-fs "请先关闭游戏并手动卸载后重试"
        return 1
    fi
    _game_fs_require_released || return 1

    case "${GAME_FS[overlay_backend]}" in
        fuse)
            command_exists fuse-overlayfs || {
                log_error game-fs "未安装 fuse-overlayfs，无法使用 overlay.backend = fuse"
                return 1
            }
            ;;
        kernel)
            command_exists mount || {
                log_error game-fs "未找到 mount，无法使用 overlay.backend = kernel"
                return 1
            }
            ;;
        *)
            log_error game-fs "未知的 overlay backend: '${GAME_FS[overlay_backend]}'"
            return 1
            ;;
    esac
}

# 挂载 overlay，仅启动流程调用
game_fs_mount() {
    _game_fs_require_init || return 1
    [ "${GAME_FS[overlay_enabled]}" = "1" ] || return 0
    _game_fs_require_install || return 1
    _game_fs_require_released || return 1

    local mount="${GAME_FS[overlay_mount]}"
    local upper="${GAME_FS[overlay_upper]}"
    local work="${GAME_FS[overlay_work]}"
    local lower="${GAME_FS[overlay_lower]}"
    local backend="${GAME_FS[overlay_backend]}"

    if game_fs_overlay_mounted; then
        log_error game-fs "overlay 挂载点已处于挂载状态: '$mount'"
        log_error game-fs "请先关闭游戏并手动卸载后重试"
        return 1
    fi

    mkdir -p -- "$mount" "$upper" "$work" || {
        log_error game-fs "无法创建 overlay 目录: '$mount' / '$upper' / '$work'"
        return 1
    }

    local upper_dev work_dev
    upper_dev="$(stat -c %d -- "$upper" 2>/dev/null || true)"
    work_dev="$(stat -c %d -- "$work" 2>/dev/null || true)"
    if [ -n "$upper_dev" ] && [ -n "$work_dev" ] && [ "$upper_dev" != "$work_dev" ]; then
        log_warn game-fs "overlay upper 与 work 不在同一文件系统，kernel backend 可能无法挂载"
    fi

    local -a cmd=()
    local -a options=("lowerdir=$lower" "upperdir=$upper" "workdir=$work")
    case "$backend" in
        fuse)
            command_exists fuse-overlayfs || {
                log_error game-fs "未安装 fuse-overlayfs，无法使用 overlay.backend = fuse"
                return 1
            }
            cmd=(fuse-overlayfs -f -o "$(IFS=,; echo "${options[*]}")" "$mount")
            ;;
        kernel)
            command_exists mount || {
                log_error game-fs "未找到 mount，无法使用 overlay.backend = kernel"
                return 1
            }
            options+=("userxattr")
            cmd=(mount -t overlay overlay -o "$(IFS=,; echo "${options[*]}")" "$mount")
            ;;
        *)
            log_error game-fs "未知的 overlay backend: '$backend'"
            return 1
            ;;
    esac

    log_debug game-fs "挂载 overlay: $(quote_args "${cmd[@]}")"
    if [ "$backend" = fuse ]; then
        (
            trap - EXIT
            local service_pid="$BASHPID"
            # 先登记再访问 upper，启动器异常退出时也能识别遗留服务
            if ! _game_fs_record_session "$service_pid" "$(_process_starttime "$service_pid")"; then
                log_error game-fs "无法记录 FUSE 服务，取消挂载"
                exit 1
            fi
            exec "${cmd[@]}"
        ) &
        GAME_FS[overlay_fuse_pid]=$!
        GAME_FS[overlay_fuse_starttime]="$(_process_starttime "${GAME_FS[overlay_fuse_pid]}")"
        GAME_FS[overlay_mounted_by_us]=1
        # 前台服务异步启动，挂载就绪后才能运行 prepare
        local attempt
        for ((attempt = 0; attempt < 100; attempt++)); do
            _game_fs_fuse_running || break
            if game_fs_overlay_mounted; then
                GAME_FS[overlay_mounted]=1
                return 0
            fi
            sleep 0.1
        done
        log_error game-fs "FUSE 服务退出或挂载未就绪: '$mount'"
        _game_fs_stop_fuse
        return 1
    elif ! "${cmd[@]}"; then
        # 失败时按实际挂载状态清理
        if game_fs_overlay_mounted; then
            GAME_FS[overlay_mounted]=1
            GAME_FS[overlay_mounted_by_us]=1
        fi
        log_error game-fs "挂载 overlay 失败: '$mount'"
        return 1
    fi

    # 先登记所有权，再检查挂载点
    GAME_FS[overlay_mounted]=1
    GAME_FS[overlay_mounted_by_us]=1
    if ! game_fs_overlay_mounted; then
        log_error game-fs "overlay 挂载命令已执行，但挂载点未生效: '$mount'"
        return 1
    fi
}

# $1=1 要求后端释放（默认），$1=0 允许懒卸载
# 返回 0 表示可以离线清理，懒卸载返回 1
game_fs_unmount() {
    [ "${GAME_FS[initialized]:-0}" = "1" ] || return 0
    [ "${GAME_FS[overlay_enabled]:-0}" = "1" ] || return 0

    local require_offline="${1:-1}"
    local backend="${GAME_FS[overlay_backend]}"
    local mounted=0
    game_fs_overlay_mounted && mounted=1
    if [ "$mounted" -eq 1 ] && [ "${GAME_FS[overlay_mounted_by_us]:-0}" != "1" ]; then
        log_error game-fs "检测到外部 overlay 挂载，拒绝自动卸载: '${GAME_FS[overlay_mount]}'"
        log_error game-fs "请手动卸载后再重新启动"
        return 1
    fi

    if [ "$mounted" -eq 1 ] && ! _game_fs_umount; then
        if [ "$require_offline" -eq 1 ]; then
            if [ "$backend" != fuse ]; then
                log_error game-fs "overlay 卸载失败，保留挂载，跳过离线清理；请手动卸载"
                return 1
            fi
            # 撤销服务前先提交内核缓存中的写入
            if _game_fs_fuse_running && ! sync -f -- "${GAME_FS[overlay_mount]}"; then
                log_error game-fs "overlay 同步失败，保留 FUSE 服务并跳过离线清理"
                return 1
            fi
            log_warn game-fs "撤销本次 FUSE 服务；旧挂载的使用者后续访问可能失败"
            _game_fs_stop_fuse || return 1
            # 服务退出时可能已经自行卸载
            if game_fs_overlay_mounted; then
                _game_fs_umount 1 || return 1
            fi
        else
            # kernel 没有可追踪的服务，懒卸载后无法确认是否已释放
            if [ "$backend" = kernel ]; then
                _game_fs_record_session || return 1
            fi
            _game_fs_umount 1 || return 1
            GAME_FS[overlay_unmount_deferred]=1
            GAME_FS[overlay_mounted]=0
            log_warn game-fs "overlay 已懒卸载，后端释放前禁止离线操作和复用 upper"
            return 1
        fi
    elif [ "$backend" = fuse ] && [ -n "${GAME_FS[overlay_fuse_pid]:-}" ]; then
        # 普通卸载后仍需等待服务完成后端清理
        # 外部懒卸载后不要求离线时，保留服务和会话记录
        if [ "$mounted" -eq 0 ] && [ "$require_offline" -eq 0 ] && _game_fs_fuse_running; then
            GAME_FS[overlay_unmount_deferred]=1
            return 1
        fi
        _game_fs_stop_fuse || return 1
    fi

    # 挂载点消失不代表后端已释放
    _game_fs_require_released || return 1
    if [ "${GAME_FS[overlay_mounted_by_us]:-0}" = 1 ]; then
        local file="${GAME_FS[overlay_session_file]:-}"
        if [ -n "$file" ]; then
            rm -f -- "$file" || return 1
        fi
    elif [ "${GAME_FS[overlay_unmount_deferred]:-0}" = 1 ]; then
        return 1
    fi
    GAME_FS[overlay_unmount_deferred]=0
    GAME_FS[overlay_mounted]=0
    GAME_FS[overlay_mounted_by_us]=0
    GAME_FS[overlay_fuse_pid]=""
    GAME_FS[overlay_fuse_starttime]=""
    return 0
}

# 写入 LaunchPlan
game_fs_apply_launch_plan() {
    _game_fs_require_init || return 1
    launch_plan_set_game_exe "${GAME_FS[game_exe_runtime]}"
    launch_plan_set_cwd "${GAME_FS[game_cwd_runtime]}"
}

# 要求当前没有 overlay 挂载
game_fs_require_offline() {
    _game_fs_require_init || return 1
    if game_fs_overlay_mounted; then
        log_error game-fs "overlay 正在挂载: '${GAME_FS[overlay_mount]}'"
        log_error game-fs "请先关闭游戏并卸载 overlay 后再执行"
        return 1
    fi
    _game_fs_require_released
}
