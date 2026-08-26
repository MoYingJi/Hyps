#!/hint/bash

[[ -n "${__CONFIG_SH_LOADED:-}" ]] && return 0
__CONFIG_SH_LOADED=1

#shellcheck source=log.sh
source "${SCRIPT_DIR:-.}/log.sh"
#shellcheck source=utils.sh
source "${SCRIPT_DIR:-.}/utils.sh"

load_common_config() {
    config_parse_file "$PROJECT_ROOT/config.conf"

    config_read_realpath_prefer_env path.config CONFIG_DIR "${XDG_CONFIG_HOME:-$HOME/.config}/hypsc"

    config_parse_file "$CONFIG_DIR/config.conf"

    config_read_realpath_prefer_env path.cache CACHE_DIR "${XDG_CACHE_HOME:-$HOME/.cache}/hypsc"
    config_read_realpath_prefer_env path.data DATA_DIR "${XDG_DATA_HOME:-$HOME/.local/share}/hypsc"
    config_read_realpath_prefer_env path.temp TEMP_DIR "/tmp/hypsc"

    config_parse_file "$CONFIG_DIR/games/_common.conf"
}

# 本文件部分使用 LLM 生成

declare -A TEMP_CONFIG
declare -A CONFIG

config_parse_file() {
    local file="$1"
    local -n target_map="${2:-CONFIG}"

    [[ -f "$file" ]] || {
        log_debug config "配置文件不存在，跳过：$file"
        return 0
    }

    local line
    local line_no=0

    local pending_key=""
    local pending_value=""
    local stripped_line

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_no++))

        # 去除首尾空白
        line="${line#"${line%%[![:space:]]*}"}"   # 去除前导空白
        line="${line%"${line##*[![:space:]]}"}"   # 去除尾随空白

        # 跳过空行和注释
        [[ -z "$line" || "$line" == \#* ]] && continue

        # 解析 key=value
        if [[ -z "$pending_key" ]] && [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"

            # 检查值是否为未闭合的数组开始
            if [[ "$value" == "["* ]] && [[ "$value" != *"]" ]]; then
                # 进入多行模式
                pending_key="$key"
                pending_value="$value"
            else
                # 单行值，直接存储
                value="$(_strip_trailing_comment "$value")"
                _config_store_value target_map "$key" "$value"
            fi
        elif [[ -n "$pending_key" ]]; then
            # 多行模式：继续累积值
            # 跳过注释行？一般来说数组内不应有注释，但可跳过纯注释行
            if [[ "$line" == \#* ]]; then
                continue
            fi

            stripped_line="$(_strip_trailing_comment "$line")"

            if [[ "$pending_value" == *"," ]]; then
                pending_value+=" $stripped_line"
            else
                pending_value+=", $stripped_line"
            fi

            # 检查是否已闭合
            if [[ "$pending_value" == *"]" ]]; then
                # 闭合，存储
                _config_store_value target_map "$pending_key" "$pending_value"
                pending_key=""
                pending_value=""
            fi
        else
            log_warn "配置文件 $file 第 $line_no 行格式错误，忽略：$line"
        fi
    done < "$file"

    # 文件结束仍处于多行模式，发出警告
    if [[ -n "$pending_key" ]]; then
        log_warn "配置文件 $file 中数组 '$pending_key' 未闭合，忽略"
    fi
}

_strip_trailing_comment() {
    local str="$1"
    local in_single=0
    local in_double=0
    local escape=0
    local i
    local char
    local comment_pos=-1

    for ((i=0; i<${#str}; i++)); do
        char="${str:i:1}"

        # 处理转义字符（仅对双引号内有效）
        if [[ $escape -eq 1 ]]; then
            escape=0
            continue
        fi

        if [[ $char == "\\" ]] && [[ $in_double -eq 1 ]]; then
            escape=1
            continue
        fi

        # 切换引号状态
        if [[ $char == "'" ]] && [[ $in_double -eq 0 ]]; then
            in_single=$((1 - in_single))
            continue
        fi
        if [[ $char == '"' ]] && [[ $in_single -eq 0 ]]; then
            in_double=$((1 - in_double))
            continue
        fi

        # 在引号外遇到 # 即标记注释位置
        if [[ $in_single -eq 0 && $in_double -eq 0 && $char == '#' ]]; then
            comment_pos=$i
            break
        fi
    done

    if [[ $comment_pos -ne -1 ]]; then
        # 截取注释前部分，并去除尾随空白
        str="${str:0:comment_pos}"
        str="${str%"${str##*[![:space:]]}"}"
    fi
    echo "$str"
}

#shellcheck disable=SC2034
_config_store_value() {
    local -n map_ref="$1"
    local key="$2"
    local value="$3"

    if [[ "$value" =~ ^\".*\"$ || "$value" =~ ^\'.*\'$ ]]; then
        value="${value:1:-1}"
    fi

    map_ref["$key"]="$value"
}

#shellcheck disable=SC2178
config_get() {
    local key="$1"
    local default="${2:-}"
    local -n target_map="${3:-CONFIG}"

    if [[ -n "${target_map[$key]+exists}" ]]; then
        echo "${target_map[$key]}"
    else
        echo "$default"
    fi
}

#shellcheck disable=SC2178
config_default() {
    local key="$1"
    local default="${2:-}"
    local -n target_map="${3:-CONFIG}"

    if [[ -n "${target_map[$key]+exists}" ]]; then
        echo "${target_map[$key]}"
    else
        echo "$default"
        log_debug config "设置配置 [${3:-CONFIG}] $key = $default"
        target_map["$key"]="$default"
    fi
}

#shellcheck disable=SC2178
config_set() {
    local key="$1"
    local value="$2"
    local -n target_map="${3:-CONFIG}"
    log_debug config "设置配置 [${3:-CONFIG}] $key = $value"
    target_map["$key"]="$value"
}

#shellcheck disable=SC2178
config_has() {
    local key="$1"
    local -n target_map="${2:-CONFIG}"
    [[ -n "${target_map[$key]+exists}" ]]
}

# 获取 $1 的绝对路径，并将其存储回配置中
config_realpath() {
    local key="$1"
    local default="${2:-}"
    local target_map_name="${3:-CONFIG}"

    local value
    value="$(config_get "$key" "$default" "$target_map_name")"
    [ -n "$value" ] && value="$(realpath -m "$value")"
    config_set "$key" "$value" "$target_map_name"
}

# 获取 $1 的绝对路径，如果不是文件则报错，并将其存储回配置中
config_require_realpath_file() {
    local key="$1"
    local default="${2:-}"
    local target_map_name="${3:-CONFIG}"

    local value
    value="$(config_get "$key" "$default" "$target_map_name")"
    [[ -n "$value" ]] || die 1 config "配置项 '$key' 未设置"
    value="$(realpath -m "$value")"
    [[ -e "$value" ]] || die 1 config "配置项 '$key' 指向的文件不存在：'$value'"
    [[ -f "$value" ]] || die 1 config "配置项 '$key' 指向的路径不是文件：'$value'"
    config_set "$key" "$value" "$target_map_name"
}

# 获取 $1 的绝对路径，如果不是目录则报错，并将其存储回配置中
config_require_realpath_dir() {
    local key="$1"
    local default="${2:-}"
    local target_map_name="${3:-CONFIG}"

    local value
    value="$(config_get "$key" "$default" "$target_map_name")"
    [[ -n "$value" ]] || die 1 config "配置项 '$key' 未设置"
    value="$(realpath -m "$value")"
    [[ -e "$value" ]] || die 1 config "配置项 '$key' 指向的目录不存在：'$value'"
    [[ -d "$value" ]] || die 1 config "配置项 '$key' 指向的路径不是目录：'$value'"
    config_set "$key" "$value" "$target_map_name"
}

# 获取 $1 的绝对路径，如果不是目录且无法创建则报错，并将其存储回配置中
config_require_realpath_mkdir() {
    local key="$1"
    local default="${2:-}"
    local target_map_name="${3:-CONFIG}"

    local value
    value="$(config_get "$key" "$default" "$target_map_name")"
    [[ -n "$value" ]] || die 1 config "配置项 '$key' 未设置"
    value="$(realpath -m "$value")"
    [[ -e "$value" ]] && [[ ! -d "$value" ]] && die 1 config "配置项 '$key' 指向的路径不是目录：'$value'"
    [[ -d "$value" ]] || mkdir -p "$value" || die 1 config "配置项 '$key' 指向的目录不存在，且创建失败：'$value'"
    config_set "$key" "$value" "$target_map_name"
}

# 获取 $1 的绝对路径，如果不是可执行文件则报错，并将其存储回配置中
config_require_realpath_exe() {
    local key="$1"
    local default="${2:-}"
    local target_map_name="${3:-CONFIG}"

    local value
    value="$(config_get "$key" "$default" "$target_map_name")"
    [[ -n "$value" ]] || die 1 config "配置项 '$key' 未设置"
    value="$(which "$value" 2>/dev/null || echo "$value")"
    [[ -f "$value" ]] || die 1 config "配置项 '$key' 指向的文件不存在：'$value'"
    [[ -x "$value" ]] || die 1 config "配置项 '$key' 指向的文件不可执行：'$value'"
    config_set "$key" "$value" "$target_map_name"
}


config_read_realpath_prefer_env() {
    local key="$1"
    local -n var="$2"
    local default="${3:-}"
    local target_map_name="${4:-CONFIG}"

    [[ -z "$var" ]] && var="$(config_get "$key" "$default" "$target_map_name")"
    var="$(realpath -m "$var")"
    config_set "$key" "$var" "$target_map_name"
}


#shellcheck disable=SC2034
config_read_array() {
    local key="$1"
    local var_array_name="$2"
    local -n var_array="$var_array_name"
    local default="${3:-}"
    local target_map_name="${4:-CONFIG}"

    [[ "${#var_array[@]}" -eq 0 ]] || return 0

    local array_str
    array_str="$(config_get "$key" "$default" "$target_map_name")"
    parse_json_array "$array_str" "$var_array_name"
}



#shellcheck disable=SC2178
config_print_all() {
    local -n target_map="${1:-CONFIG}"

    for key in "${!target_map[@]}"; do
        echo "$key: ${target_map[$key]}"
    done
}

config_parse_to_temp() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    TEMP_CONFIG=()
    config_parse_file "$file" TEMP_CONFIG
}

#shellcheck disable=SC2034
config_merge_temp() {
    local key
    for key in "${!TEMP_CONFIG[@]}"; do
        CONFIG["$key"]="${TEMP_CONFIG[$key]}"
    done
    log_debug config "已合并临时配置到主配置"
}
