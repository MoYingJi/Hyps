#!/hint/bash

[[ -n "${__LIFECYCLE_SH_LOADED:-}" ]] && return 0
__LIFECYCLE_SH_LOADED=1

#shellcheck source=log.sh
source "${SCRIPT_DIR:-.}/log.sh"

# 特性:
#   - 注册钩子: register_hook <phase> <function_name> [priority] [deps_spec]
#   - 依赖声明:
#       depends_on:funcA,funcB  当前钩子依赖这些函数（它们先执行）
#       after:funcA,funcB       等价于 depends_on
#       before:funcA,funcB      当前钩子必须在这些函数之前执行
#     (可混合使用，例如 "depends_on:a before:b,c after:d")
#   - 拓扑排序，自动处理依赖顺序
#   - 循环依赖检测
#   - 丰富的日志输出
#
# 用法:
#   source lifecycle.sh
#   register_hook prepare my_prepare_func 50 "depends_on:other_func before:later_func"
#   run_hooks prepare
#
# 依赖:
#   - Bash 4+ (关联数组, mapfile)
#   - 外部命令: sort, awk

# 本文件大部分使用 LLM 生成

# 存储每个阶段的钩子条目，格式: " priority:function_name:depends_on_list "
# 多个条目以空格分隔，例如 " 10:funcA: 20:funcB:funcA "
declare -A HOOKS_BY_PHASE
declare -A HOOK_BEFORE

# 合法的阶段名称
readonly LIFECYCLE_PHASES=(
    "load_config"
    "prepare"
    "pre_start"
    "post_start"
    "cleanup"
)

# 内部：检查阶段名是否合法
_lifecycle_valid_phase() {
    local phase="$1"
    local p
    for p in "${LIFECYCLE_PHASES[@]}"; do
        [[ "$p" == "$phase" ]] && return 0
    done
    return 1
}

# 内部：验证优先级是否为整数
_lifecycle_valid_priority() {
    [[ "$1" =~ ^-?[0-9]+$ ]]
}

# 解析依赖描述字符串，统一为 "depends_on" 和 "before" 两部分
# 输入: deps_spec，例如 "depends_on:a,b before:c,d after:e"
# 输出: 通过全局变量 _LIFECYCLE_DEP_LIST 和 _LIFECYCLE_BEFORE_LIST 返回
_lifecycle_parse_deps() {
    local deps_spec="$1"
    _LIFECYCLE_DEP_LIST=""
    _LIFECYCLE_BEFORE_LIST=""

    # 分割多个声明（逗号分隔）
    local IFS=','
    local spec
    for spec in $deps_spec; do
        spec="${spec## }"   # 去除前导空格
        [[ -z "$spec" ]] && continue

        case "$spec" in
            depends_on:*)
                _LIFECYCLE_DEP_LIST+="${spec#depends_on:},"
                ;;
            after:*)
                _LIFECYCLE_DEP_LIST+="${spec#after:},"
                ;;
            before:*)
                _LIFECYCLE_BEFORE_LIST+="${spec#before:},"
                ;;
        esac
    done

    # 去掉尾随逗号
    _LIFECYCLE_DEP_LIST="${_LIFECYCLE_DEP_LIST%,}"
    _LIFECYCLE_BEFORE_LIST="${_LIFECYCLE_BEFORE_LIST%,}"
}

# 注册钩子
# 参数:
#   $1: phase       - 阶段名（必须合法）
#   $2: fn          - 函数名（建议已定义，但不强制，注册时不检查）
#   $3: priority    - 优先级（数字，越小越先执行，默认 50）
#   $4: deps_spec   - 依赖描述，支持 depends_on: / after: / before:，逗号分隔多个
# 返回: 0 成功，1 失败
register_hook() {
    local phase="$1"
    local fn="$2"
    local priority="${3:-50}"
    local deps_spec="${4:-}"

    # 校验阶段
    if ! _lifecycle_valid_phase "$phase"; then
        log_error lifecycle "未知阶段 '$phase'（合法阶段: ${LIFECYCLE_PHASES[*]}）"
        return 1
    fi

    # 校验优先级
    if ! _lifecycle_valid_priority "$priority"; then
        log_error lifecycle "优先级必须是整数，得到 '$priority'"
        return 1
    fi

    # 解析依赖描述
    _lifecycle_parse_deps "$deps_spec"
    local dep_list="$_LIFECYCLE_DEP_LIST"
    local before_list="$_LIFECYCLE_BEFORE_LIST"

    # 检查是否重复注册（完全相同的条目才跳过）
    local existing="${HOOKS_BY_PHASE[$phase]:-}"
    if [[ " $existing " == *" $priority:$fn:$dep_list "* ]]; then
        log_warn lifecycle "钩子 '$fn' 已以相同优先级和依赖注册在阶段 '$phase'，忽略重复注册"
        return 0
    fi

    # 存储钩子条目（仅记录依赖列表，不存储 before，before 单独存）
    HOOKS_BY_PHASE["$phase"]="${existing:+$existing }$priority:$fn:$dep_list"

    # 存储 before 信息（如果非空）
    if [[ -n "$before_list" ]]; then
        HOOK_BEFORE["$fn"]="$before_list"
        log_debug lifecycle "注册钩子 [$phase] $fn (优先级 $priority, 依赖: ${dep_list:-无}, before: $before_list)"
    else
        log_debug lifecycle "注册钩子 [$phase] $fn (优先级 $priority, 依赖: ${dep_list:-无})"
    fi

    return 0
}

# 内部：构建依赖图并进行拓扑排序，执行钩子
# 参数: $1 = phase
# 返回: 0 成功，1 失败
_lifecycle_run_sorted_hooks() {
    local phase="$1"
    local raw="${HOOKS_BY_PHASE[$phase]:-}"

    [[ -z "$raw" ]] && return 0

    # 解析所有钩子条目
    local -A hook_priority
    local -A hook_deps
    local -a all_hooks

    local entry
    for entry in $raw; do
        IFS=':' read -r prio fn deps <<< "$entry"
        hook_priority["$fn"]="$prio"
        hook_deps["$fn"]="$deps"
        all_hooks+=("$fn")
    done

    # 构建依赖图
    local -A indegree
    local -A edges   # 后继列表，空格分隔

    local fn
    for fn in "${all_hooks[@]}"; do
        indegree["$fn"]=0
        edges["$fn"]=""
    done

    local has_error=0

    # 处理 depends_on / after（即 hook_deps）
    for fn in "${all_hooks[@]}"; do
        local deps="${hook_deps[$fn]}"
        [[ -z "$deps" ]] && continue

        local dep
        IFS=',' read -ra dep_arr <<< "$deps"
        for dep in "${dep_arr[@]}"; do
            dep="${dep## }"   # 去除前导空格
            [[ -z "$dep" ]] && continue

            if [[ -z "${hook_priority[$dep]:-}" ]]; then
                log_error lifecycle "钩子 '$fn' 依赖 '$dep'，但 '$dep' 未注册在阶段 '$phase'"
                has_error=1
                continue
            fi

            # 添加边 dep -> fn
            edges["$dep"]+=" $fn"
            indegree["$fn"]=$(( indegree["$fn"] + 1 ))
        done
    done

    # 处理 before 声明
    for fn in "${all_hooks[@]}"; do
        local before_list="${HOOK_BEFORE[$fn]:-}"
        [[ -z "$before_list" ]] && continue

        local target
        IFS=',' read -ra target_arr <<< "$before_list"
        for target in "${target_arr[@]}"; do
            target="${target## }"
            [[ -z "$target" ]] && continue

            if [[ -z "${hook_priority[$target]:-}" ]]; then
                log_error lifecycle "钩子 '$fn' 声明在 '$target' 之前，但 '$target' 未注册在阶段 '$phase'"
                has_error=1
                continue
            fi

            # fn before target => target 依赖于 fn => 添加边 fn -> target
            edges["$fn"]+=" $target"
            indegree["$target"]=$(( indegree["$target"] + 1 ))
        done
    done

    [[ $has_error -ne 0 ]] && return 1

    # 初始队列：入度为 0 的节点，按优先级排序
    local -a queue=()
    for fn in "${all_hooks[@]}"; do
        if [[ "${indegree[$fn]}" -eq 0 ]]; then
            queue+=("$fn")
        fi
    done

    # 排序队列（按优先级数值升序）
    mapfile -t queue < <(
        for fn in "${queue[@]}"; do
            echo "${hook_priority[$fn]} $fn"
        done | sort -n | awk '{print $2}'
    )

    # Kahn 算法拓扑排序
    local -a sorted=()
    while [[ ${#queue[@]} -gt 0 ]]; do
        local current="${queue[0]}"
        queue=("${queue[@]:1}")
        sorted+=("$current")

        # 处理当前节点的后继
        local succ
        for succ in ${edges["$current"]:-}; do
            indegree["$succ"]=$(( indegree["$succ"] - 1 ))
            if [[ "${indegree[$succ]}" -eq 0 ]]; then
                queue+=("$succ")
                # 重新排序队列（简单实现，性能可接受）
                mapfile -t queue < <(
                    for fn in "${queue[@]}"; do
                        echo "${hook_priority[$fn]} $fn"
                    done | sort -n | awk '{print $2}'
                )
            fi
        done
    done

    # 检查循环依赖
    if [[ ${#sorted[@]} -ne ${#all_hooks[@]} ]]; then
        log_error lifecycle "阶段 '$phase' 存在循环依赖，无法完成拓扑排序"
        return 1
    fi

    # 按顺序执行钩子
    for fn in "${sorted[@]}"; do
        log_debug lifecycle "执行钩子 [$phase] $fn"
        "$fn" || {
            log_error lifecycle "钩子 '$fn' 在阶段 '$phase' 执行失败"
            return 1
        }
    done

    return 0
}

# 运行指定阶段的所有钩子
# 参数: $1 = phase
# 返回: 0 成功，1 失败
run_hooks() {
    local phase="$1"

    if ! _lifecycle_valid_phase "$phase"; then
        log_error lifecycle "未知阶段 '$phase'"
        return 1
    fi

    if [[ -z "${HOOKS_BY_PHASE[$phase]:-}" ]]; then
        log_debug lifecycle "阶段 '$phase' 无钩子"
        return 0
    fi

    log_debug lifecycle "开始执行阶段 '$phase' 的钩子"
    _lifecycle_run_sorted_hooks "$phase"
    local ret=$?
    if [[ $ret -eq 0 ]]; then
        log_debug lifecycle "阶段 '$phase' 完成"
    else
        log_error lifecycle "阶段 '$phase' 执行失败"
    fi
    return $ret
}

# 清除所有已注册的钩子（用于重置状态，谨慎使用）
clear_hooks() {
    HOOKS_BY_PHASE=()
    HOOK_BEFORE=()
    log_debug lifecycle "已清除所有钩子"
}

# 检查指定阶段是否已注册某个函数
# 参数: $1=phase $2=fn
# 返回: 0 已注册，1 未注册
hook_registered() {
    local phase="$1"
    local fn="$2"
    local raw="${HOOKS_BY_PHASE[$phase]:-}"
    [[ " $raw " == *" $fn "* ]] && return 0
    return 1
}
