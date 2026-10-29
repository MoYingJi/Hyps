#!/hint/bash

# ToolSpec: 描述一个 C 工具的编译输入 (源文件, 后端, 宏, 链接库)
# 运行时与 development/gen-compile-db.sh 共用; 本文件不依赖日志与配置, 可被单独 source

[[ -n "${__UTILS_TOOLSPEC_SH_LOADED:-}" ]] && return 0
__UTILS_TOOLSPEC_SH_LOADED=1

# toolspec_load <工具目录>
# 清空上一次的 TOOLSPEC_* 后读取 <工具目录>/toolspec.sh
toolspec_load() {
    local dir="$1"
    local -a vars=()
    mapfile -t vars < <(compgen -v TOOLSPEC_)
    unset "${vars[@]}"

    TOOLSPEC_DIR="$dir"
    TOOLSPEC_NAME="$(basename "$dir")"
    # shellcheck disable=SC2034 # 默认值, spec 可覆盖
    TOOLSPEC_TOOLCHAIN=host
    TOOLSPEC_CFLAGS=()
    TOOLSPEC_INCLUDES=()
    TOOLSPEC_SOURCES=()
    TOOLSPEC_DEPS=()
    TOOLSPEC_BACKENDS=()

    # shellcheck source=/dev/null
    source "$dir/toolspec.sh"
}

toolspec_backend_pkg() {
    local -n _pkg="TOOLSPEC_BACKEND_${1}_PKG"
    echo "${_pkg:-}"
}

# 后端未声明 PKG 时视为总是可用
toolspec_backend_available() {
    local pkg
    pkg="$(toolspec_backend_pkg "$1")"
    [[ -z "$pkg" ]] || pkg-config --exists "$pkg"
}

_toolspec_is_backend() {
    local b
    for b in "${TOOLSPEC_BACKENDS[@]}"; do
        [[ "$b" == "$1" ]] && return 0
    done
    return 1
}

# _toolspec_add_backend <后端> <sources 数组名> <defines 数组名> <libs 数组名>
_toolspec_add_backend() {
    local backend="$1"
    local -n _out_sources="$2" _out_defines="$3" _out_libs="$4"
    local -n _bsources="TOOLSPEC_BACKEND_${backend}_SOURCES"
    local -n _bdefines="TOOLSPEC_BACKEND_${backend}_DEFINES"
    local -n _blibs="TOOLSPEC_BACKEND_${backend}_LIBS"
    local f

    for f in "${_bsources[@]}"; do
        _out_sources+=("$TOOLSPEC_DIR/$f")
    done
    _out_defines+=("${_bdefines[@]}")
    _out_libs+=("${_blibs[@]}")
}

# toolspec_resolve <cc> <用户 CFLAGS 数组名> [backend...]
# 结果: TOOLSPEC_RESULT_CC / _CFLAGS / _SOURCES / _LIBS / _INPUTS
toolspec_resolve() {
    local cc="$1"
    local -n _user_cflags="$2"
    shift 2

    local -a sources=() defines=() libs=() deps=()
    local f d b

    for f in "${TOOLSPEC_SOURCES[@]}"; do
        sources+=("$TOOLSPEC_DIR/$f")
    done
    for f in "${TOOLSPEC_DEPS[@]}"; do
        deps+=("$TOOLSPEC_DIR/$f")
    done

    for b in "$@"; do
        if ! _toolspec_is_backend "$b"; then
            echo "[$TOOLSPEC_NAME] 未知后端: '$b'" >&2
            return 1
        fi
        _toolspec_add_backend "$b" sources defines libs
    done

    TOOLSPEC_RESULT_CC="$cc"
    TOOLSPEC_RESULT_CFLAGS=("${_user_cflags[@]}" -std=gnu23 "${TOOLSPEC_CFLAGS[@]}")
    for d in "${TOOLSPEC_INCLUDES[@]}"; do
        if [[ "$d" == . ]]; then
            TOOLSPEC_RESULT_CFLAGS+=("-I$TOOLSPEC_DIR")
        else
            TOOLSPEC_RESULT_CFLAGS+=("-I$TOOLSPEC_DIR/$d")
        fi
    done
    for d in "${defines[@]}"; do
        TOOLSPEC_RESULT_CFLAGS+=("-D$d")
    done
    TOOLSPEC_RESULT_SOURCES=("${sources[@]}")
    TOOLSPEC_RESULT_LIBS=("${libs[@]}")
    TOOLSPEC_RESULT_INPUTS=("${sources[@]}" "${deps[@]}")
}

# 输出解析结果涉及的全部输入文件内容与 argv, 用作缓存校验和
toolspec_fingerprint() {
    local f
    for f in "${TOOLSPEC_RESULT_INPUTS[@]}"; do
        printf '### %s\n' "$f"
        cat -- "$f"
    done
    printf '### argv\n'
    printf '%s\n' "$TOOLSPEC_RESULT_CC" "${TOOLSPEC_RESULT_CFLAGS[@]}" \
        "${TOOLSPEC_RESULT_SOURCES[@]}" "${TOOLSPEC_RESULT_LIBS[@]}"
}
