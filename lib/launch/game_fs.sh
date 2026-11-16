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

# install 根来源: game.install_dir > game_install_dir > 旧 overlay_auto_lower
# 都没有时返回 2，由调用方决定是否允许 install 视图留空
# 用法: game_fs_resolve_install_dir <game_exe> <out_var>
game_fs_resolve_install_dir() {
    local game_exe="$1"
    local -n _out="$2"
    local configured=""
    local dir=""

    if config_has game.install_dir; then
        config_read game.install_dir configured
        [ -n "$configured" ] || {
            log_error game-fs "配置项 'game.install_dir' 不能为空"
            return 1
        }
        configured="$(realpath -m -- "$configured")"
        [ -d "$configured" ] || {
            log_error game-fs "game.install_dir 目录不存在: '$configured'"
            return 1
        }
        _out="$configured"
        return 0
    fi

    if [ "$(type -t game_install_dir)" = "function" ]; then
        dir="$(game_install_dir "$game_exe")" || {
            log_error game-fs "game_install_dir 执行失败: '$game_exe'"
            return 1
        }
    elif [ "$(type -t overlay_auto_lower)" = "function" ]; then
        log_warn game-fs "游戏仍在使用 overlay_auto_lower，请迁移到 game_install_dir"
        dir="$(overlay_auto_lower "$game_exe")" || {
            log_error game-fs "overlay_auto_lower 执行失败: '$game_exe'"
            return 1
        }
    else
        _out=""
        return 2
    fi

    [ -n "$dir" ] || {
        log_error game-fs "install 根为空: '$game_exe'"
        return 1
    }
    dir="$(realpath -m -- "$dir")"
    [ -d "$dir" ] || {
        log_error game-fs "install 根目录不存在: '$dir'"
        return 1
    }

    _out="$dir"
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

    GAME_FS[overlay_mount]="$mount"
    GAME_FS[overlay_upper]="$upper"
    GAME_FS[overlay_work]="$work"
    GAME_FS[runtime_dir]="$mount"
    GAME_FS[writable_dir]="$upper"
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
    GAME_FS=()
    GAME_FS[initialized]=1
    GAME_FS[phase]=init
    GAME_FS[game_name]="$GAME_NAME"

    local game_exe game_cwd
    config_read game.exe game_exe
    config_read game.cwd game_cwd
    game_exe="$(realpath -m -- "$game_exe")"
    game_cwd="$(realpath -m -- "$game_cwd")"

    local install_dir=""
    local install_rc=0
    game_fs_resolve_install_dir "$game_exe" install_dir
    install_rc=$?
    [ "$install_rc" -eq 0 ] || [ "$install_rc" -eq 2 ] || return 1

    GAME_FS[install_ok]=0
    [ "$install_rc" -eq 2 ] || GAME_FS[install_ok]=1
    GAME_FS[install_dir]="$install_dir"
    GAME_FS[game_exe_install]="$game_exe"
    GAME_FS[game_cwd_install]="$game_cwd"

    if [ "${GAME_FS[install_ok]}" = "1" ]; then
        case "$game_exe" in
            "$install_dir"/*) ;;
            *)
                log_error game-fs "游戏可执行文件不在 install 根内: '$game_exe' (install: '$install_dir')"
                return 1
                ;;
        esac
    fi

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

game_fs_write_paths() {
    local scope="$1" rel="$2"
    game_fs_assert_mutation "$scope" || return 1
    game_fs_paths "$scope" "$rel"
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
            printf '%s\n' "${GAME_FS[overlay_lower]}"
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
                printf '%s\n' "${GAME_FS[overlay_upper]}"
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
# 用法: _game_fs_join <root> <relpath>
_game_fs_join() {
    local root="$1"
    local rel="$2"

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

    case "$scope" in
        all)
            game_fs_paths all "$rel"
            return
            ;;
        *)
            root="$(game_fs_root "$scope")" || return 1
            ;;
    esac

    _game_fs_join "$root" "$rel"
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

# 用法: game_fs_display <scope> <relpath>
#shellcheck disable=SC2016 # 单引号里的 $VAR 是展示用字面占位符，不展开
game_fs_display() {
    _game_fs_require_init || return 1
    local scope="$1"
    local rel="$2"
    local label

    case "$scope" in
        install)
            _game_fs_require_install || return 1
            label='$GAME_DIR'
            ;;
        lower)
            _game_fs_require_install || return 1
            if [ "${GAME_FS[overlay_enabled]}" = "1" ]; then
                label='$OVERLAY_LOWER'
            else
                label='$GAME_DIR'
            fi
            ;;
        upper)
            _game_fs_require_install || return 1
            label='$OVERLAY_UPPER'
            ;;
        runtime)
            _game_fs_require_install || return 1
            if [ "${GAME_FS[overlay_enabled]}" = "1" ]; then
                label='$OVERLAY_MOUNT'
            else
                label='$GAME_DIR'
            fi
            ;;
        writable)
            _game_fs_require_install || return 1
            if [ "${GAME_FS[overlay_enabled]}" = "1" ]; then
                label='$OVERLAY_UPPER'
            else
                label='$GAME_DIR'
            fi
            ;;
        prefix) label='$PREFIX' ;;
        userprofile) label='$USERPROFILE' ;;
        cache) label='$CACHE_DIR' ;;
        data) label='$DATA_DIR' ;;
        state) label='$STATE_DIR' ;;
        temp) label='$TEMP_DIR' ;;
        *)
            log_error game-fs "未知的路径作用域: '$scope'"
            return 1
            ;;
    esac

    if [ -z "$rel" ]; then
        printf '%s\n' "$label"
    else
        printf '%s/%s\n' "$label" "$rel"
    fi
}

# 挂载点是否处于挂载状态
game_fs_overlay_mounted() {
    [ "${GAME_FS[overlay_enabled]:-0}" = "1" ] || return 1
    local mount="${GAME_FS[overlay_mount]:-}"
    [ -n "$mount" ] || return 1

    if command_exists mountpoint; then
        mountpoint -q -- "$mount" 2>/dev/null
    else
        findmnt -n -T "$mount" >/dev/null 2>&1
    fi
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
            cmd=(fuse-overlayfs -o "$(IFS=,; echo "${options[*]}")" "$mount")
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
    if ! "${cmd[@]}"; then
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

# 卸载 overlay，可重复调用
game_fs_unmount() {
    [ "${GAME_FS[initialized]:-0}" = "1" ] || return 0
    [ "${GAME_FS[overlay_enabled]:-0}" = "1" ] || return 0

    # 以实际挂载状态为准
    if ! game_fs_overlay_mounted; then
        GAME_FS[overlay_mounted]=0
        GAME_FS[overlay_mounted_by_us]=0
        return 0
    fi
    if [ "${GAME_FS[overlay_mounted_by_us]:-0}" != "1" ]; then
        log_error game-fs "检测到外部 overlay 挂载，拒绝自动卸载: '${GAME_FS[overlay_mount]}'"
        log_error game-fs "请手动卸载后再重新启动"
        return 1
    fi

    local mount="${GAME_FS[overlay_mount]}"
    local backend="${GAME_FS[overlay_backend]}"
    local ok=0

    case "$backend" in
        fuse)
            if command_exists fusermount3; then
                fusermount3 -uz "$mount" && ok=1
            elif command_exists fusermount; then
                fusermount -uz "$mount" && ok=1
            elif command_exists umount; then
                umount -l "$mount" && ok=1
            else
                log_error game-fs "没有可用的 overlay 卸载命令"
                return 1
            fi
            ;;
        kernel)
            if command_exists umount; then
                umount -l "$mount" && ok=1
            else
                log_error game-fs "没有 umount，无法卸载 overlay"
                return 1
            fi
            ;;
        *)
            log_error game-fs "未知的 overlay backend: '$backend'"
            return 1
            ;;
    esac

    if [ "$ok" -ne 1 ]; then
        log_error game-fs "卸载 overlay 失败: '$mount'"
        return 1
    fi

    GAME_FS[overlay_mounted]=0
    GAME_FS[overlay_mounted_by_us]=0
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
}
