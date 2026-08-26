#!/hint/bash

[[ -n "${__UTILS_WINE_SH_LOADED:-}" ]] && return 0
__UTILS_WINE_SH_LOADED=1

#shellcheck source=../log.sh
source "${SCRIPT_DIR:-.}/log.sh"

ensure_no_wineserver() {
    local prefix="$1"
    local action="$2" # kill | error
    local why="$3"

    local pid
    local current_prefix

    for pid in $(pgrep wineserver); do
        current_prefix="$(cat "/proc/$pid/environ" 2>/dev/null | tr '\0' '\n' | grep '^WINEPREFIX=' | cut -d= -f2)"
        [[ "$current_prefix" -ef "$prefix" ]] || [[ "$current_prefix" -ef "$prefix/pfx" ]] || continue

        case "$action" in
            kill)
                log_info utils "检测到 wineserver 正在运行，尝试杀死它 (PID: $pid)"
                log_info utils "    原因: $why"
                log_debug utils "    WINEPREFIX: $current_prefix"
                log_debug utils "    wineserver: $(readlink -f "/proc/$pid/exe")"
                WINEPREFIX="$prefix" "/proc/$pid/exe" --kill
                ;;
            error)
                log_error utils "检测到 wineserver 正在运行 (PID: $pid)，请先关闭它再继续"
                log_error utils "    原因: $why"
                die 1
                ;;
            *)
                log_error utils "ensure_no_wineserver 未知的 action '$action'"
                die
                ;;
        esac
    done
}

find_wineprefix() {
    local prefix="$1"

    if [ -f "$prefix/user.reg" ] && [ -d "$prefix/drive_c" ]; then
        echo "$prefix"
    elif [ -f "$prefix/pfx/user.reg" ] && [ -d "$prefix/pfx/drive_c" ]; then
        echo "$prefix/pfx"
    else
        echo "$prefix"
    fi
}

_load_proton_paths() {
    local -n proton_paths="$1"
    local extra_proton_paths=()
    IFS=':' read -ra extra_proton_paths <<< "$STEAM_EXTRA_COMPAT_TOOLS_PATHS"
    local all_proton_paths=(
        "$HOME/.local/share/Steam/compatibilitytools.d"
        "${extra_proton_paths[@]}"
        "/usr/local/share/steam/compatibilitytools.d"
        "/usr/share/steam/compatibilitytools.d"
    )
    for path in "${all_proton_paths[@]}"; do
        if [ -d "$path" ]; then
            proton_paths+=("$path")
        fi
    done
}
_PROTON_PATHS=()
_load_proton_paths _PROTON_PATHS

get_proton_name() {
    local proton_path="$1"

    if [ ! -f "$proton_path/compatibilitytool.vdf" ] || [ ! -r "$proton_path/compatibilitytool.vdf" ]; then
        return 1
    fi

    sed -n '/"compat_tools"/,/}/p' "$proton_path/compatibilitytool.vdf" \
        | grep -E '^\s*"[^"]+"' \
        | tail -n +2 \
        | head -1 \
        | sed 's/^\s*"\(.*\)".*$/\1/'
}

find_proton_by_name_in_dir() {
    local proton_name="$1"
    local compatibility_tools_dir="$2"

    for dir in "$compatibility_tools_dir"/*; do
        if [ -d "$dir" ]; then
            local name
            name="$(get_proton_name "$dir")"
            if [ "$name" = "$proton_name" ]; then
                echo "$dir"
                return 0
            fi
        fi
    done

    return 1
}

find_proton_by_name() {
    local proton_name="$1"

    for path in "${_PROTON_PATHS[@]}"; do
        find_proton_by_name_in_dir "$proton_name" "$path" && return 0
    done

    return 1
}
