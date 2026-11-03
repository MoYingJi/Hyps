#!/hint/bash

#shellcheck source=../core/log.sh
source "$SCRIPT_DIR/core/log.sh"
#shellcheck source=../utils.sh
source "$SCRIPT_DIR/utils.sh"

# 本文件部分使用 LLM 生成

config_parse_file() {
    local file="$1"
    local target_map="${2:-CONFIG}"

    [[ -f "$file" ]] || {
        log_debug config "配置文件不存在，跳过：$file"
        return 0
    }

    local line
    local line_no=0

    local pending_key=""
    local pending_value=""
    local pending_type=""
    local stripped_line
    local current_section=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_no++))

        # 去除首尾空白
        line="${line#"${line%%[![:space:]]*}"}"   # 去除前导空白
        line="${line%"${line##*[![:space:]]}"}"   # 去除尾随空白

        # 跳过空行和注释
        [[ -z "$line" || "$line" == \#* ]] && continue

        # 解析节标题 [section] 或 [section.subsection]
        if [[ "$line" =~ ^\[([^\]]+)\]$ ]]; then
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

            # 检查值是否为未闭合的数组开始
            if [[ "$value" == "["* ]] && [[ "$value" != *"]" ]]; then
                # 进入多行模式（方括号数组）
                pending_key="$key"
                pending_value="$value"
                pending_type="square"
            elif [[ "$value" == "("* ]] && [[ "$value" != *")" ]]; then
                # 进入多行模式（圆括号数组）
                pending_key="$key"
                pending_value="$value"
                pending_type="paren"
            else
                # 单行值，直接存储
                _strip_trailing_comment value
                # 如果有节前缀，添加到键名中
                if [[ -n "$current_section" ]]; then
                    key="${current_section}.${key}"
                fi
                _config_store_value "$target_map" "$key" "$value"
            fi
        elif [[ -n "$pending_key" ]]; then
            # 多行模式：继续累积值
            # 跳过注释行？一般来说数组内不应有注释，但可跳过纯注释行
            if [[ "$line" == \#* ]]; then
                continue
            fi

            stripped_line="$line"
            _strip_trailing_comment stripped_line

            if [[ "$pending_type" == "square" ]]; then
                if [[ "$pending_value" == *"," ]]; then
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
                local final_key="$pending_key"
                # 如果有节前缀，添加到键名中
                if [[ -n "$current_section" ]]; then
                    final_key="${current_section}.${pending_key}"
                fi
                _config_store_value "$target_map" "$final_key" "$pending_value"
                pending_key=""
                pending_value=""
                pending_type=""
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

    if [[ "$value" =~ ^\".*\"$ || "$value" =~ ^\'.*\'$ ]]; then
        value="${value:1:-1}"
    fi

    #shellcheck disable=SC2034
    map_ref["$key"]="$value"
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
