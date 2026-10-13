#!/hint/bash

[[ -n "${__UTILS_PROCESS_SH_LOADED:-}" ]] && return 0
__UTILS_PROCESS_SH_LOADED=1

# 按进程名查找当前用户的进程，每行输出一个 PID；无匹配时返回 1
# 用法: find_pid_by_name [-n] <name>，-n 只输出最新的一个（同 pgrep -n）
find_pid_by_name() {
    local newest=0 name pid
    local comm_max=15
    local -a pids=()

    if [[ "$1" == "-n" ]]; then
        newest=1
        shift
    fi
    name="$1"

    if [[ "${#name}" -le "$comm_max" ]]; then
        if [[ "$newest" -eq 1 ]]; then
            pgrep -n -u "$USER" -x "$name"
        else
            pgrep -u "$USER" -x "$name"
        fi
        return
    fi

    # 内核只保存前 15 个字符，pgrep -x 对更长的名称会直接失败，因此按截断名查找后再校验完整名称
    while read -r pid; do
        _process_cmdline_has_exe "$pid" "$name" && pids+=("$pid")
    done < <(pgrep -u "$USER" -x "${name:0:comm_max}")

    [[ "${#pids[@]}" -gt 0 ]] || return 1

    if [[ "$newest" -eq 1 ]]; then
        for pid in "${pids[@]}"; do
            printf '%s %s\n' "$(_process_starttime "$pid")" "$pid"
        done | sort -n | tail -n 1 | cut -d' ' -f2
    else
        printf '%s\n' "${pids[@]}"
    fi
}

# cmdline 中名称需作为路径末段或独立参数出现，避免前缀相同的其他进程被误匹配
_process_cmdline_has_exe() {
    local pid="$1" name="$2"
    local cmd escaped re

    [[ -r "/proc/$pid/cmdline" ]] || return 1
    cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline")"
    escaped="${name//./\\.}"
    re="(^|[/\\\\\" ])${escaped}([\" ]|\$)"
    [[ "$cmd" =~ $re ]]
}

# 读取进程启动时间（/proc/<pid>/stat 第 22 个字段），用于 -n 选择最新进程
_process_starttime() {
    local stat
    local -a fields

    IFS= read -r stat < "/proc/$1/stat" 2>/dev/null || { echo 0; return; }
    # comm 可能含空格和括号，去掉 "pid (comm) " 前缀后字段才能对齐
    stat="${stat##*) }"
    read -ra fields <<< "$stat"
    echo "${fields[19]:-0}"
}
