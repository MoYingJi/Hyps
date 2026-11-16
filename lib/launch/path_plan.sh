#!/hint/bash

[[ -n "${__LAUNCH_PATH_PLAN_SH_LOADED:-}" ]] && return 0
__LAUNCH_PATH_PLAN_SH_LOADED=1

# 游戏路径声明
# 游戏实现只登记角色和路径，解析与执行交给使用方

declare -ga PATH_PLAN_DECL_ROLE=()
declare -ga PATH_PLAN_DECL_SCOPE=()
declare -ga PATH_PLAN_DECL_REL=()
declare -ga PATH_PLAN_DECL_LABEL=()

declare -ga PATH_PLAN_NOTE_ROLE=()
declare -ga PATH_PLAN_NOTE_TEXT=()

_path_plan_valid_role() {
    case "$1" in
        userdata:screenshot | shader-cache) return 0 ;;
        *)
            log_error path-plan "未知的路径角色: '$1'"
            return 1
            ;;
    esac
}

path_plan_reset() {
    PATH_PLAN_DECL_ROLE=()
    PATH_PLAN_DECL_SCOPE=()
    PATH_PLAN_DECL_REL=()
    PATH_PLAN_DECL_LABEL=()
    PATH_PLAN_NOTE_ROLE=()
    PATH_PLAN_NOTE_TEXT=()
}

# 用法: path_plan_declare <role> <scope> <rel> [label]
path_plan_declare() {
    local role="$1"
    local scope="$2"
    local rel="$3"
    local label="${4:-}"

    _path_plan_valid_role "$role" || return 1
    [ -n "$scope" ] || {
        log_error path-plan "路径声明缺少 scope: '$role'"
        return 1
    }
    [ -n "$rel" ] || {
        log_error path-plan "路径声明缺少相对路径: '$role'"
        return 1
    }
    if [ -n "$label" ]; then
        case "$label" in
            . | ..)
                log_error path-plan "非法路径标签: '$label'"
                return 1
                ;;
        esac
        [[ "$label" =~ ^[A-Za-z0-9._-]+$ ]] || {
            log_error path-plan "路径标签只能包含字母、数字、点、下划线和连字符: '$label'"
            return 1
        }
    fi

    PATH_PLAN_DECL_ROLE+=("$role")
    PATH_PLAN_DECL_SCOPE+=("$scope")
    PATH_PLAN_DECL_REL+=("$rel")
    PATH_PLAN_DECL_LABEL+=("$label")
}

# 用法: path_plan_note <role> [text]
# 空 text 表示只声明该 role，没有路径也没有提示
path_plan_note() {
    local role="$1"
    local text="${2:-}"

    _path_plan_valid_role "$role" || return 1
    PATH_PLAN_NOTE_ROLE+=("$role")
    PATH_PLAN_NOTE_TEXT+=("$text")
}

# 收集 game_paths 的声明
# 返回: 0 已声明该 role / 3 没有声明该 role / 4 游戏未实现 game_paths
path_plan_collect() {
    local role="$1"
    local i
    local declared=0

    _path_plan_valid_role "$role" || return 1
    path_plan_reset

    [ "${GAME_FS[initialized]:-0}" = "1" ] || {
        log_error path-plan "GAME_FS 尚未初始化"
        return 1
    }

    if [ "$(type -t game_paths)" != "function" ]; then
        return 4
    fi
    game_paths || {
        log_error path-plan "game_paths 执行失败"
        return 1
    }

    for i in "${!PATH_PLAN_DECL_ROLE[@]}"; do
        [ "${PATH_PLAN_DECL_ROLE[$i]}" = "$role" ] && declared=1
    done
    for i in "${!PATH_PLAN_NOTE_ROLE[@]}"; do
        [ "${PATH_PLAN_NOTE_ROLE[$i]}" = "$role" ] && declared=1
    done

    [ "$declared" -eq 1 ] || return 3
    return 0
}

# 输出解析后的路径记录:
#   link   <scope> <path> <label>
#   delete <view>  <path> <scope>
# 需要先调用 path_plan_collect
path_plan_paths() {
    local role="$1"
    local i scope rel label view path
    local game_paths_output
    local -A seen=()

    _path_plan_valid_role "$role" || return 1

    for i in "${!PATH_PLAN_DECL_ROLE[@]}"; do
        [ "${PATH_PLAN_DECL_ROLE[$i]}" = "$role" ] || continue
        scope="${PATH_PLAN_DECL_SCOPE[$i]}"
        rel="${PATH_PLAN_DECL_REL[$i]}"
        label="${PATH_PLAN_DECL_LABEL[$i]}"

        case "$role" in
            userdata:screenshot)
                [ "$scope" != "all" ] || {
                    log_error path-plan "screenshot 不能使用 all scope"
                    return 1
                }
                if [ -z "$label" ]; then
                    label="$(game_meta_path_name)" || return 1
                fi
                path="$(game_fs_path "$scope" "$rel")" || return 1
                if [ -z "${seen["link|$scope|$path|$label"]:-}" ]; then
                    seen["link|$scope|$path|$label"]=1
                    printf 'link\t%s\t%s\t%s\n' "$scope" "$path" "$label"
                fi
                ;;
            shader-cache)
                game_paths_output="$(game_fs_paths "$scope" "$rel")" || return 1
                while IFS=$'\t' read -r view path; do
                    [ -n "$path" ] || continue
                    if [ -z "${seen["delete|$scope|$view|$path"]:-}" ]; then
                        seen["delete|$scope|$view|$path"]=1
                        printf 'delete\t%s\t%s\t%s\n' "$view" "$path" "$scope"
                    fi
                done <<<"$game_paths_output"
                ;;
        esac
    done
}

# 用法: path_plan_render <role>
path_plan_render() {
    local role="$1"
    local i text
    local has_actions=0
    local has_notes=0
    local kind a b c plan

    _path_plan_valid_role "$role" || return 1

    plan="$(path_plan_paths "$role")" || return 1
    while IFS=$'\t' read -r kind a b c; do
        [ -n "$kind" ] || continue
        has_actions=1
        case "$kind" in
            link)
                printf '截图: %s -> %s/%s\n' "$b" "${SCREENSHOTS:-<SCREENSHOTS>}" "$c"
                ;;
            delete)
                printf '[%s] %s\n' "$a" "$b"
                ;;
        esac
    done <<<"$plan"

    for i in "${!PATH_PLAN_NOTE_ROLE[@]}"; do
        [ "${PATH_PLAN_NOTE_ROLE[$i]}" = "$role" ] || continue
        text="${PATH_PLAN_NOTE_TEXT[$i]}"
        [ -n "$text" ] || continue
        if [ "$has_notes" -eq 0 ]; then
            printf '提示:\n'
            has_notes=1
        fi
        printf '%s\n' "$text"
    done

    if [ "$has_actions" -eq 0 ] && [ "$has_notes" -eq 0 ]; then
        printf '已声明，无路径\n'
    fi
}
