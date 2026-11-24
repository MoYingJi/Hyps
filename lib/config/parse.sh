#!/hint/bash

#shellcheck source=../core/log.sh
source "$SCRIPT_DIR/core/log.sh"
#shellcheck source=state.sh
source "$SCRIPT_DIR/config/state.sh"
#shellcheck source=value.sh
source "$SCRIPT_DIR/config/value.sh"

# 本文件部分使用 LLM 生成

config_parse_file() {
    local file="$1"
    local target_map="${2:-CONFIG}"
    local source_map="${3:-}"
    local kind_map="${4:-${target_map}_KIND}"
    if [[ -z "$source_map" ]]; then
        case "$target_map" in
            CONFIG) source_map=CONFIG_SOURCE ;;
            TEMP_CONFIG) source_map=TEMP_CONFIG_SOURCE ;;
        esac
    fi

    [[ -f "$file" ]] || {
        log_debug config "配置文件不存在，跳过：$file"
        return 0
    }
    [[ "${!kind_map@a}" == *A* ]] ||
        die 1 config "配置值结构表 '$kind_map' 必须为关联数组"

    local line
    local line_no=0

    local pending_key=""
    local pending_value=""
    local pending_type=""
    local pending_line=0
    local stripped_line
    local current_section=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_no += 1))

        # 去除首尾空白
        line="${line#"${line%%[![:space:]]*}"}"   # 去除前导空白
        line="${line%"${line##*[![:space:]]}"}"   # 去除尾随空白

        # 跳过空行和注释
        [[ -z "$line" || "$line" == \#* ]] && continue

        # 解析节标题 [section] 或 [section.subsection]
        if [[ -z "$pending_key" && "$line" =~ ^\[([^\]]+)\]$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            # 去除节名称中的空白
            current_section="${current_section#"${current_section%%[![:space:]]*}"}"
            current_section="${current_section%"${current_section##*[![:space:]]}"}"
            continue
        fi

        # 解析 key=value
        if [[ -z "$pending_key" ]] && [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
            _strip_trailing_comment value
            # 如果有节前缀，添加到键名中
            [[ -z "$current_section" ]] || key="${current_section}.${key}"
            [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]] ||
                die 1 config "$file:$line_no 配置键 '$key' 无效"

            # 检查值是否为未闭合的数组开始
            if [[ "$value" == "["* ]] && [[ "$value" != *"]" ]]; then
                # 进入多行模式（方括号数组）
                pending_key="$key"
                pending_value="$value"
                pending_type="square"
                pending_line="$line_no"
            elif [[ "$value" == "("* ]] && [[ "$value" != *")" ]]; then
                # 进入多行模式（圆括号数组）
                pending_key="$key"
                pending_value="$value"
                pending_type="paren"
                pending_line="$line_no"
            else
                # 单行值，直接存储
                _config_store_value "$target_map" "$key" "$value" "$source_map" "$file:$line_no" "$kind_map"
            fi
        elif [[ -n "$pending_key" ]]; then
            # 多行模式：继续累积值
            stripped_line="$line"
            _strip_trailing_comment stripped_line

            if [[ "$pending_type" == "square" ]]; then
                if [[ "$pending_value" == "[" || "$pending_value" == *"," || "$stripped_line" == "]" ]]; then
                    pending_value+=" $stripped_line"
                else
                    pending_value+=", $stripped_line"
                fi
            else  # paren
                pending_value+=" $stripped_line"
            fi

            # 检查是否已闭合
            if [[ "$pending_type" == "square" && "$pending_value" == *"]" ]] || \
               [[ "$pending_type" == "paren" && "$pending_value" == *")" ]]; then
                # 闭合，存储
                _config_store_value "$target_map" "$pending_key" "$pending_value" "$source_map" "$file:$pending_line" "$kind_map"
                pending_key=""
                pending_value=""
                pending_type=""
            fi
        else
            die 1 config "$file:$line_no 配置格式错误：$line"
        fi
    done < "$file" || die 1 config "无法读取配置文件：$file"

    if [[ -n "$pending_key" ]]; then
        die 1 config "$file:$pending_line 数组 '$pending_key' 未闭合"
    fi
    return 0
}

_strip_trailing_comment() {
    local -n str_ref="$1"
    local str="$str_ref"

    # 无 # 则不可能有注释，直接返回
    [[ $str == *'#'* ]] || return 0

    # 只跳到引号、反斜杠与 # 处，其余字符不影响引号状态
    local rest="$str" plain c pos=0 comment_pos=-1
    local in_single=0 in_double=0

    while [[ -n $rest ]]; do
        plain="${rest%%[\'\"\\#]*}"
        pos=$((pos + ${#plain}))
        rest="${rest:${#plain}}"
        [[ -n $rest ]] || break

        c="${rest:0:1}"
        rest="${rest:1}"
        pos=$((pos + 1))

        # 双引号内的反斜杠转义下一个字符
        if (( in_double )) && [[ $c == "\\" ]]; then
            [[ -n $rest ]] || break
            rest="${rest:1}"
            pos=$((pos + 1))
        elif [[ $c == "'" ]] && (( ! in_double )); then
            in_single=$((1 - in_single))
        elif [[ $c == '"' ]] && (( ! in_single )); then
            in_double=$((1 - in_double))
        elif [[ $c == '#' ]] && (( ! in_single && ! in_double )); then
            comment_pos=$((pos - 1))
            break
        fi
    done

    if (( comment_pos != -1 )); then
        str="${str:0:comment_pos}"
        str="${str%"${str##*[![:space:]]}"}"
    fi
    str_ref="$str"
}

_config_store_value() {
    local -n map_ref="$1"
    local key="$2"
    local value="$3"
    local source_map="${4:-}"
    local origin="${5:-}"
    local kind
    local -n kinds_ref="$6"
    _config_value_parse "$value" value kind "$origin 配置项 '$key'"

    #shellcheck disable=SC2034
    map_ref["$key"]="$value"
    #shellcheck disable=SC2034
    kinds_ref["$key"]="$kind"
    if [[ -n "$source_map" ]]; then
        local -n origins_ref="$source_map"
        #shellcheck disable=SC2034
        origins_ref["$key"]="$origin"
    fi
}

config_parse_to_temp() {
    local file="$1"
    TEMP_CONFIG=()
    TEMP_CONFIG_SOURCE=()
    TEMP_CONFIG_KIND=()
    config_parse_file "$file" TEMP_CONFIG
}

#shellcheck disable=SC2034
config_merge_temp() {
    local key
    for key in "${!TEMP_CONFIG[@]}"; do
        CONFIG["$key"]="${TEMP_CONFIG[$key]}"
        CONFIG_SOURCE["$key"]="${TEMP_CONFIG_SOURCE[$key]:-运行时}"
        CONFIG_KIND["$key"]="${TEMP_CONFIG_KIND[$key]}"
    done
    log_debug config "已合并临时配置到主配置"
}
