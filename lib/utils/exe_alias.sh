#!/hint/bash

[[ -n "${__UTILS_EXE_ALIAS_SH_LOADED:-}" ]] && return 0
__UTILS_EXE_ALIAS_SH_LOADED=1

#shellcheck source=../core/log.sh
source "$SCRIPT_DIR/core/log.sh"
#shellcheck source=../utils/string.sh
source "$SCRIPT_DIR/utils/string.sh"
#shellcheck source=../utils/cache.sh
source "$SCRIPT_DIR/utils/cache.sh"

# exe-alias: 统一的可执行文件别名目录，供需要给工具换名的 feature 共用
# 例如 DLL 注入器自定义进程名、替身父进程等
# 目录名取中性词，避免路径本身暴露用途；放在缓存 bin 下，便于与本体硬链接

EXE_ALIAS_DIRNAME="app"
declare -g EXE_ALIAS_RESET_DONE=0
declare -gA EXE_ALIAS_OWNERS=()   # 别名 -> 源文件，用于冲突检测

exe_alias_dir() {
    cache_bin_path "$EXE_ALIAS_DIRNAME"
}

# 校验别名: 允空(表示不使用别名)，否则必须是带 .exe 后缀的单段安全文件名
# 拒绝路径分隔符、开头点、结尾点和 Windows 保留设备名
exe_alias_name_is_valid() {
    local name="$1"
    [[ -z "$name" ]] && return 0
    [[ "${name,,}" == *.exe ]] || return 1
    [[ "$name" != */* && "$name" != *\\* ]] || return 1
    [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
    [[ "$name" != .* ]] || return 1
    [[ "$name" != *'.' ]] || return 1
    local stem="${name%%.*}"
    case "${stem^^}" in
        CON | PRN | AUX | NUL | COM[1-9] | LPT[1-9]) return 1 ;;
    esac
    return 0
}

# 首次使用时清空并重建共享目录，丢弃上次运行遗留的别名
exe_alias_reset() {
    local dir
    dir="$(exe_alias_dir)"
    [[ "$dir" == "$CACHE_DIR"/bin/* && "$(basename -- "$dir")" == "$EXE_ALIAS_DIRNAME" ]] ||
        die 1 exe-alias "别名目录超出缓存目录范围: $dir"

    rm -rf -- "$dir" || die 1 exe-alias "无法清理别名目录: $dir"
    mkdir -p -- "$dir" || die 1 exe-alias "无法创建别名目录: $dir"
    EXE_ALIAS_OWNERS=()
    EXE_ALIAS_RESET_DONE=1
}

# exe_alias_place <名字> <源文件> <输出变量名>
# 确保源文件以该名字出现在共享别名目录，把完整路径写入输出变量
# 用 nameref 回填而不是 echo，避免调用方用 $(...) 时进入子 shell 丢失本模块状态
# 同一次运行内首次调用会清空目录，之后追加；同名不同源视为冲突
exe_alias_place() {
    [[ $# -eq 3 ]] || die 1 exe-alias "exe_alias_place 用法为 <名字> <源文件> <输出变量名>"
    local name="$1" src="$2"
    local -n _alias_out="$3"
    [[ -n "$name" ]] || die 1 exe-alias "别名不能为空"
    exe_alias_name_is_valid "$name" || die 1 exe-alias "别名不合法: $name"
    [[ -f "$src" ]] || die 1 exe-alias "别名源文件不存在: $src"

    isy "$EXE_ALIAS_RESET_DONE" || exe_alias_reset

    local dir dst
    dir="$(exe_alias_dir)"
    dst="$dir/$name"

    if [[ -n "${EXE_ALIAS_OWNERS[$name]:-}" && "${EXE_ALIAS_OWNERS[$name]}" != "$src" ]]; then
        die 1 exe-alias "别名冲突: $name 已用于 ${EXE_ALIAS_OWNERS[$name]}"
    fi

    if [[ ! -e "$dst" ]]; then
        # 优先硬链接，跨文件系统或权限不足时回退复制
        ln -- "$src" "$dst" 2>/dev/null || cp -f -- "$src" "$dst" ||
            die 1 exe-alias "无法创建别名: $dst"
        chmod 755 -- "$dst" 2>/dev/null || true
    fi

    EXE_ALIAS_OWNERS["$name"]="$src"
    _alias_out="$dst"
}
