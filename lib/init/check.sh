#!/hint/bash

[[ -n "${__INIT_CHECK_SH_LOADED:-}" ]] && return 0
__INIT_CHECK_SH_LOADED=1

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

# 初始化：基础环境检测
# 检查结果逐条记录，最后按分组输出报表
# 状态: ok 通过 / warn 可选能力缺失 / fail 必需项缺失 / info 仅提示

declare -a INIT_CHECK_GROUP=()
declare -a INIT_CHECK_STATUS=()
declare -a INIT_CHECK_NAME=()
declare -a INIT_CHECK_DETAIL=()

INIT_REQUIRED_TOTAL=0
INIT_REQUIRED_PASS=0
INIT_REQUIRED_FAIL=0
INIT_WARN_COUNT=0
INIT_CONFIG_WARN_COUNT=0

INIT_GROUPS=(system commands runner graphics features config)
declare -A INIT_GROUP_TITLE=(
    [system]="系统"
    [commands]="命令与工具链"
    [runner]="运行器"
    [graphics]="图形"
    [features]="可选功能"
    [config]="配置"
)

# 用法: _init_join <分隔符> <元素...>
_init_join() {
    local sep="$1"
    shift
    local first=1 item
    for item in "$@"; do
        if [[ "$first" -eq 1 ]]; then
            first=0
        else
            printf '%s' "$sep"
        fi
        printf '%s' "$item"
    done
}

init_check_reset() {
    INIT_CHECK_GROUP=()
    INIT_CHECK_STATUS=()
    INIT_CHECK_NAME=()
    INIT_CHECK_DETAIL=()

    INIT_REQUIRED_TOTAL=0
    INIT_REQUIRED_PASS=0
    INIT_REQUIRED_FAIL=0
    INIT_WARN_COUNT=0
    INIT_CONFIG_WARN_COUNT=0
}

# 用法: init_check_add <分组> <状态> <名称> <说明> [是否必需: 0|1]
init_check_add() {
    local group="$1"
    local status="$2"
    local name="$3"
    local detail="$4"
    local required="${5:-0}"

    INIT_CHECK_GROUP+=("$group")
    INIT_CHECK_STATUS+=("$status")
    INIT_CHECK_NAME+=("$name")
    INIT_CHECK_DETAIL+=("$detail")

    if [[ "$required" -eq 1 ]]; then
        INIT_REQUIRED_TOTAL=$(( INIT_REQUIRED_TOTAL + 1 ))
        case "$status" in
            ok)   INIT_REQUIRED_PASS=$(( INIT_REQUIRED_PASS + 1 )) ;;
            fail) INIT_REQUIRED_FAIL=$(( INIT_REQUIRED_FAIL + 1 )) ;;
        esac
    fi

    if [[ "$status" == "warn" ]]; then
        if [[ "$group" == "config" ]]; then
            INIT_CONFIG_WARN_COUNT=$(( INIT_CONFIG_WARN_COUNT + 1 ))
        else
            INIT_WARN_COUNT=$(( INIT_WARN_COUNT + 1 ))
        fi
    fi

    log_debug init "检查 [$group] $name: $status - $detail"
}

# 用法: init_check_command <分组> <缺失状态> <名称> <命令> <缺失说明> [是否必需]
init_check_command() {
    local group="$1"
    local miss_status="$2"
    local name="$3"
    local cmd="$4"
    local miss_detail="$5"
    local required="${6:-0}"

    local path
    if path="$(type -P -- "$cmd" 2>/dev/null)"; then
        init_check_add "$group" ok "$name" "$path" "$required"
    else
        init_check_add "$group" "$miss_status" "$name" "$miss_detail" "$required"
    fi
}

# 用法: init_check_cmd_group <分组> <缺失状态> <名称> <缺失说明> <是否必需> <命令...>
init_check_cmd_group() {
    local group="$1"
    local miss_status="$2"
    local name="$3"
    local miss_detail="$4"
    local required="$5"
    shift 5

    local cmd
    local -a missing=()
    for cmd in "$@"; do
        command_exists "$cmd" || missing+=("$cmd")
    done

    if [[ "${#missing[@]}" -eq 0 ]]; then
        init_check_add "$group" ok "$name" "全部可用" "$required"
    else
        init_check_add "$group" "$miss_status" "$name" "$miss_detail: ${missing[*]}" "$required"
    fi
}

init_check_system() {
    if [[ "$UID" -ne 0 ]]; then
        init_check_add system ok "运行用户" "$USER" 1
    else
        init_check_add system fail "运行用户" "请以普通用户运行，不要使用 root" 1
    fi

    local kernel arch
    kernel="$(uname -s)"
    arch="$(uname -m)"
    if [[ "$kernel" == "Linux" ]]; then
        init_check_add system ok "内核" "$kernel" 1
    else
        init_check_add system fail "内核" "仅支持 Linux，当前为 '$kernel'" 1
    fi
    if [[ "$arch" == "x86_64" ]]; then
        init_check_add system ok "架构" "$arch" 1
    else
        init_check_add system fail "架构" "仅支持 x86_64，当前为 '$arch'，Proton 游戏无法运行" 1
    fi

    local bash_version="${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}.${BASH_VERSINFO[2]}"
    if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) )); then
        init_check_add system ok "Bash" "$bash_version (>= 4.3)" 1
    else
        init_check_add system fail "Bash" "$bash_version 过低，脚本需要 >= 4.3" 1
    fi

    if [[ -r /etc/os-release ]]; then
        init_check_add system info "发行版" "$( . /etc/os-release; printf '%s' "${PRETTY_NAME:-${NAME:-unknown}}" )"
    fi

    local session="${XDG_SESSION_TYPE:-unknown}"
    local desktop="${XDG_CURRENT_DESKTOP:-}"
    if [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]; then
        init_check_add system ok "图形会话" "$session${desktop:+ / $desktop}"
    else
        init_check_add system warn "图形会话" "未检测到 DISPLAY / WAYLAND_DISPLAY（无头环境？）"
    fi
}

init_check_commands() {
    init_check_cmd_group commands fail "coreutils" "缺少命令" 1 \
        realpath readlink stat mktemp date cmp sort head tail tr cut find xargs
    init_check_cmd_group commands fail "文本工具" "缺少命令" 1 grep sed awk
    init_check_cmd_group commands fail "进程工具" "缺少命令" 1 pkill pgrep
    init_check_cmd_group commands fail "校验工具" "缺少命令" 1 sha256sum md5sum
    init_check_cmd_group commands warn "column" "未安装（util-linux）：_Hyps 的表格类命令需要" 0 column

    if command_exists sudo; then
        init_check_add commands ok "提权工具" "sudo ($(type -P sudo))"
    elif command_exists pkexec; then
        init_check_add commands ok "提权工具" "pkexec（无终端时不可用）"
    else
        init_check_add commands warn "提权工具" "未安装 sudo / pkexec：帧率解锁、RAPL、hosts 等功能不可用"
    fi

    init_check_command commands warn "gcc" gcc "未安装：fpsunlock / xwin-watch / 替身父进程无法编译"
    init_check_cmd_group commands warn "setcap/getcap" "未安装：fpsunlock 需要 cap_sys_ptrace" 0 setcap getcap
    init_check_command commands warn "mingw-w64" x86_64-w64-mingw32-gcc "未安装：终末地替身父进程模式不可用"
    init_check_command commands warn "python3" python3 "未安装：星铁注册表解帧、原神 D3D12 补丁需要"
    init_check_command commands info "uv" uv "未安装：原神 D3D12 unitypy 补丁将回退 bytes 实现"
}

init_check_runner() {
    init_check_command runner fail "umu-run" umu-run "未安装：默认的 umu-* 运行器都需要 umu-launcher" 1

    local runner_dir=""
    if compgen -G "$CONFIG_DIR/runners/*.conf" > /dev/null; then
        runner_dir="$CONFIG_DIR/runners"
    elif compgen -G "$PROJECT_ROOT/config/runners/*.conf" > /dev/null; then
        runner_dir="$PROJECT_ROOT/config/runners"
    fi

    if [[ -n "$runner_dir" ]]; then
        local runner_file
        for runner_file in "$runner_dir"/*.conf; do
            [[ -f "$runner_file" ]] || continue
            init_check_runner_file "$runner_file"
        done
    else
        init_check_add runner warn "运行器配置" "未找到 runners/*.conf"
    fi

    local -a proton_names=()
    local path proton proton_name
    for path in "${_PROTON_PATHS[@]}"; do
        for proton in "$path"/*; do
            [[ -d "$proton" ]] || continue
            proton_name="$(get_proton_name "$proton" 2>/dev/null)" || continue
            [[ -n "$proton_name" ]] && proton_names+=("$proton_name")
        done
    done

    if [[ "${#proton_names[@]}" -gt 0 ]]; then
        init_check_add runner info "已检测 Proton" "${#proton_names[@]} 个: $(_init_join ', ' "${proton_names[@]}")"
    else
        init_check_add runner warn "已检测 Proton" "未在 steam/compatibilitytools.d 中找到 Proton"
    fi

    if [[ -n "${STEAM_EXTRA_COMPAT_TOOLS_PATHS:-}" ]]; then
        init_check_add runner info "额外 Proton 路径" "$STEAM_EXTRA_COMPAT_TOOLS_PATHS"
    fi
}

# 用法: init_check_runner_file <runners/*.conf>
# 与 lib/config.sh 一致：runner.exe 可以省略，此时由 runner.protonpath 推导为 <proton>/proton
init_check_runner_file() {
    local file="$1"
    local name="${file##*/}"
    name="${name%.conf}"

    config_parse_to_temp "$file"

    local exe="${TEMP_CONFIG[runner.exe]:-}"
    local proton="${TEMP_CONFIG[runner.protonpath]:-}"
    local proton_dir=""
    local -a problems=()

    if [[ -n "$proton" ]]; then
        if [[ -d "$proton" ]]; then
            proton_dir="$proton"
        elif ! proton_dir="$(find_proton_by_name "$proton" 2>/dev/null)"; then
            proton_dir=""
            problems+=("未找到 Proton '$proton'")
        fi
    fi

    if [[ -n "$exe" ]]; then
        if [[ "$exe" == */* ]]; then
            [[ -x "$exe" ]] || problems+=("runner.exe '$exe' 不可执行")
        elif ! command_exists "$exe"; then
            problems+=("runner.exe '$exe' 不在 PATH 中")
        fi
    elif [[ -z "$proton" ]]; then
        problems+=("缺少 runner.exe 和 runner.protonpath")
    fi

    # 省略 runner.exe 时，配置层会推导为 <proton>/proton，这里校验它确实可执行
    if [[ -z "$exe" && -n "$proton_dir" && ! -x "$proton_dir/proton" ]]; then
        problems+=("'$proton_dir' 中缺少可执行的 proton")
    fi

    if [[ "${#problems[@]}" -eq 0 ]]; then
        local detail
        if [[ -n "$exe" && -n "$proton" ]]; then
            detail="${exe} + ${proton}"
        elif [[ -n "$exe" ]]; then
            detail="$exe"
        else
            detail="$proton（直接使用 proton）"
        fi
        init_check_add runner ok "$name" "$detail"
    else
        init_check_add runner warn "$name" "$(_init_join '；' "${problems[@]}")"
    fi
}

init_check_graphics() {
    local -a vendors=()
    local -A seen=()
    local -A label_seen=()
    local -a gpu_names=()
    local vendor_file vendor label

    for vendor_file in /sys/class/drm/card*/device/vendor; do
        [[ -r "$vendor_file" ]] || continue
        vendor="$(< "$vendor_file")"
        [[ -n "${seen[$vendor]:-}" ]] && continue
        seen["$vendor"]=1
        vendors+=("$vendor")

        case "$vendor" in
            0x10de) label="NVIDIA" ;;
            0x1002) label="AMD" ;;
            0x8086) label="Intel" ;;
            0x1af4) label="VirtIO" ;;
            *)      label="未知($vendor)" ;;
        esac
        if [[ -z "${label_seen[$label]:-}" ]]; then
            label_seen["$label"]=1
            gpu_names+=("$label")
        fi
    done

    if [[ "${#gpu_names[@]}" -gt 0 ]]; then
        init_check_add graphics ok "GPU" "$(_init_join ', ' "${gpu_names[@]}")"
    else
        init_check_add graphics warn "GPU" "未检测到 DRM 显卡（虚拟机 / 无显卡？）"
    fi

    if [[ -n "${seen[0x10de]:-}" ]]; then
        local nvidia_version
        if nvidia_version="$(nvidia_version)"; then
            init_check_add graphics ok "NVIDIA 驱动" "$nvidia_version"
        else
            init_check_add graphics warn "NVIDIA 驱动" "检测到 NVIDIA GPU，但未找到驱动版本"
        fi
    fi

    local -a icds=()
    local icd
    for icd in /usr/share/vulkan/icd.d/*.json; do
        [[ -f "$icd" ]] && icds+=("${icd##*/}")
    done
    if [[ "${#icds[@]}" -gt 0 ]]; then
        init_check_add graphics ok "Vulkan ICD" "${#icds[@]} 个: $(_init_join ', ' "${icds[@]}")"
    else
        init_check_add graphics warn "Vulkan ICD" "未找到 /usr/share/vulkan/icd.d/*.json"
    fi

    init_check_command graphics info "vulkaninfo" vulkaninfo "未安装（可选，用于排查 Vulkan 问题）"
}

init_check_features() {
    if command_exists fuse-overlayfs && [[ -r /dev/fuse && -w /dev/fuse ]]; then
        init_check_add features ok "overlay" "fuse-overlayfs + /dev/fuse 可用"
    elif ! command_exists fuse-overlayfs; then
        init_check_add features warn "overlay" "未安装 fuse-overlayfs（启用 overlay.enabled 时需要）"
    else
        init_check_add features warn "overlay" "/dev/fuse 不可用（启用 overlay.enabled 时需要）"
    fi

    init_check_command features info "fusermount3" fusermount3 "未安装（overlay 卸载用，可回退 mount）"
    init_check_command features info "MangoHud" mangohud "未安装（mangohud.enabled 需要）"
    init_check_command features info "GameMode" gamemoderun "未安装（gamemode.*.enabled 需要）"
    init_check_command features info "Gamescope" gamescope "未安装（gamescope.enabled 需要）"
    init_check_command features info "OBS 捕获" obs-gamecapture "未安装（obs_vkcapture.wrapper.enabled 需要）"
    init_check_command features info "taskset" taskset "未安装（taskset.enabled 需要）"
    init_check_command features info "systemd-inhibit" systemd-inhibit "未安装（inhibit.enabled 需要）"
    init_check_command features info "xdg-user-dir" xdg-user-dir "未安装（截图目录链接需要）"

    local rapl="/sys/class/powercap/intel-rapl:0/energy_uj"
    if [[ -e "$rapl" ]]; then
        if [[ -r "$rapl" ]]; then
            init_check_add features ok "Intel RAPL" "energy_uj 可读"
        else
            init_check_add features warn "Intel RAPL" "energy_uj 不可读（prepare.intel_rapl_read 会用 sudo 提权）"
        fi
    else
        init_check_add features info "Intel RAPL" "未检测到 /sys/class/powercap/intel-rapl:0"
    fi

    if [[ -w /etc/hosts ]]; then
        init_check_add features ok "hosts 可写" "/etc/hosts"
    else
        init_check_add features info "hosts 可写" "当前不可写：hosts_disconnect 会用 sudo 临时提权"
    fi
}

init_check_config() {
    if [[ -d "$CONFIG_DIR" ]]; then
        if [[ -w "$CONFIG_DIR" ]]; then
            init_check_add config ok "配置目录" "$CONFIG_DIR" 1
        else
            init_check_add config fail "配置目录" "$CONFIG_DIR 不可写" 1
        fi
    else
        init_check_add config warn "配置目录" "$CONFIG_DIR 不存在（初始化时创建）"
    fi

    if [[ -f "$PROJECT_ROOT/config.conf" ]]; then
        init_check_add config info "config.conf" "$PROJECT_ROOT/config.conf"
    else
        init_check_add config warn "config.conf" "缺少 $PROJECT_ROOT/config.conf"
    fi

    if [[ -f "$CONFIG_DIR/games/_common.conf" ]]; then
        init_check_add config ok "_common.conf" "$CONFIG_DIR/games/_common.conf"
    else
        init_check_add config warn "_common.conf" "不存在（初始化时复制示例）"
    fi

    if [[ -d "$CONFIG_DIR/games" ]]; then
        init_check_add config ok "游戏配置目录" "$CONFIG_DIR/games"
    else
        init_check_add config warn "游戏配置目录" "$CONFIG_DIR/games 不存在（初始化时创建）"
    fi

    if [[ "$(realpath -m "$CONFIG_DIR/runners")" != "$(realpath -m "$PROJECT_ROOT/config/runners")" ]]; then
        local runner_missing_count=0 runner_file
        for runner_file in "$PROJECT_ROOT/config/runners"/*.conf; do
            [[ -f "$runner_file" ]] || continue
            [[ -f "$CONFIG_DIR/runners/${runner_file##*/}" ]] || runner_missing_count=$(( runner_missing_count + 1 ))
        done
        if [[ "$runner_missing_count" -gt 0 ]]; then
            init_check_add config warn "运行器配置" "自定义配置目录缺少 $runner_missing_count 个 runner 配置（初始化时复制）"
        else
            init_check_add config ok "运行器配置" "已同步"
        fi
    else
        init_check_add config ok "运行器配置" "使用仓库内 config/runners"
    fi

    local -a games=()
    local game_file game_name
    for game_file in "$CONFIG_DIR/games"/*.conf; do
        [[ -f "$game_file" ]] || continue
        game_name="${game_file##*/}"
        [[ "$game_name" == "_common.conf" ]] && continue
        games+=("${game_name%.conf}")
    done
    if [[ "${#games[@]}" -gt 0 ]]; then
        init_check_add config ok "已配置游戏" "${#games[@]} 个: $(_init_join ', ' "${games[@]}")"
    else
        init_check_add config warn "已配置游戏" "还没有游戏配置（初始化会引导创建）"
    fi

    local label dir
    for label in 缓存目录 数据目录 临时目录; do
        case "$label" in
            缓存目录) dir="$CACHE_DIR" ;;
            数据目录) dir="$DATA_DIR" ;;
            临时目录) dir="$TEMP_DIR" ;;
        esac
        if [[ ! -d "$dir" ]]; then
            init_check_add config info "$label" "$dir 不存在（首次启动自动创建）"
        elif [[ ! -w "$dir" ]]; then
            init_check_add config warn "$label" "$dir 不可写"
        else
            init_check_add config info "$label" "$dir"
        fi
    done
}

init_check_all() {
    init_check_reset
    init_check_system
    init_check_commands
    init_check_runner
    init_check_graphics
    init_check_features
    init_check_config
}

# 必需项全部通过时返回 0
init_check_ok() {
    [[ "$INIT_REQUIRED_FAIL" -eq 0 ]]
}

_init_check_icon() {
    case "$1" in
        ok)   style_quote green "[✓]" ;;
        warn) style_quote yellow "[!]" ;;
        fail) style_quote red "[✗]" ;;
        *)    style_quote bright_black "[i]" ;;
    esac
}

# 按显示宽度右填充（中日韩字符占两列）
_init_pad_right() {
    local text="$1"
    local target="$2"
    local width
    width="$(printf '%s' "$text" | wc -L 2>/dev/null | tr -d '[:space:]')"
    [[ "$width" =~ ^[0-9]+$ ]] || width="${#text}"
    printf '%s' "$text"
    if [[ "$width" -lt "$target" ]]; then
        printf '%*s' "$(( target - width ))" ''
    fi
}

init_check_report() {
    local group i

    printf '%s\n' "$(style_quote bold "[Hyps] 环境检测")"

    for group in "${INIT_GROUPS[@]}"; do
        local has_entry=0
        for i in "${!INIT_CHECK_GROUP[@]}"; do
            if [[ "${INIT_CHECK_GROUP[$i]}" == "$group" ]]; then
                has_entry=1
                break
            fi
        done
        [[ "$has_entry" -eq 1 ]] || continue

        printf '\n%s\n' "$(style_quote bold "${INIT_GROUP_TITLE[$group]}")"
        for i in "${!INIT_CHECK_GROUP[@]}"; do
            [[ "${INIT_CHECK_GROUP[$i]}" == "$group" ]] || continue
            printf '  %s %s  %s\n' \
                "$(_init_check_icon "${INIT_CHECK_STATUS[$i]}")" \
                "$(_init_pad_right "${INIT_CHECK_NAME[$i]}" 28)" \
                "${INIT_CHECK_DETAIL[$i]}"
        done
    done

    printf '\n'
    if [[ "$INIT_REQUIRED_FAIL" -eq 0 ]]; then
        printf '%s %s/%s %s\n' \
            "$(style_quote bold "必需项:")" \
            "$(style_quote green "$INIT_REQUIRED_PASS")" \
            "$INIT_REQUIRED_TOTAL" "通过"
    else
        printf '%s %s/%s %s（%s 项缺失）\n' \
            "$(style_quote bold "必需项:")" \
            "$(style_quote red "$INIT_REQUIRED_PASS")" \
            "$INIT_REQUIRED_TOTAL" "通过" \
            "$INIT_REQUIRED_FAIL"
    fi

    if [[ "$INIT_WARN_COUNT" -gt 0 ]]; then
        printf '%s %s 项（见上行 [!] 标记，安装对应依赖后可用）\n' \
            "$(style_quote bold "可选能力缺失:")" "$INIT_WARN_COUNT"
    fi
    if [[ "$INIT_CONFIG_WARN_COUNT" -gt 0 ]]; then
        printf '%s %s 项（运行 ./init.sh 初始化会补齐）\n' \
            "$(style_quote bold "配置待创建:")" "$INIT_CONFIG_WARN_COUNT"
    fi
}
