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
    local stripped_line value_closed
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
            # 如果有节前缀，添加到键名中
            [[ -z "$current_section" ]] || key="${current_section}.${key}"
            [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]] ||
                die 1 config "$file:$line_no 配置键 '$key' 无效"

            case "$value" in
                '['*) pending_type=square ;;
                '('*) pending_type=paren ;;
                *) pending_type=scalar ;;
            esac
            _config_scan_value_line value value_closed "$pending_type" "$file:$line_no 配置项 '$key'" || return $?

            if [[ "$pending_type" != scalar && "$value_closed" != true ]]; then
                pending_key="$key"
                pending_value="$value"
                pending_line="$line_no"
            else
                _config_store_value "$target_map" "$key" "$value" "$source_map" "$file:$line_no" "$kind_map" || return $?
            fi
        elif [[ -n "$pending_key" ]]; then
            stripped_line="$line"
            _config_scan_value_line stripped_line value_closed "$pending_type" "$file:$line_no 配置项 '$pending_key'" || return $?

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
            if [[ "$value_closed" == true ]]; then
                # 闭合，存储
                _config_store_value "$target_map" "$pending_key" "$pending_value" "$source_map" "$file:$pending_line" "$kind_map" || return $?
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

# 用相同的引号规则识别行尾注释和数组结束符
_config_scan_value_line() {
    local -n _cfg_line="$1" _cfg_line_closed="$2"
    local _cfg_line_type="$3" _cfg_line_origin="$4"
    local _cfg_line_rest="$_cfg_line" _cfg_line_ignored
    _cfg_line_closed=false

    if [[ "$_cfg_line_type" == scalar ]]; then
        if [[ "$_cfg_line_rest" == '"'* || "$_cfg_line_rest" == "'"* ]]; then
            read_quoted_string "$_cfg_line_rest" _cfg_line_ignored _cfg_line_rest "$_cfg_line_origin" || return $?
        else
            _cfg_line="${_cfg_line%%#*}"
            return 0
        fi
    fi

    while [[ -n "$_cfg_line_rest" ]]; do
        case "$_cfg_line_rest" in
            '#'*)
                _cfg_line="${_cfg_line:0:${#_cfg_line}-${#_cfg_line_rest}}"
                break
                ;;
            '"'* | "'"*)
                read_quoted_string "$_cfg_line_rest" _cfg_line_ignored _cfg_line_rest "$_cfg_line_origin" || return $?
                continue
                ;;
            ']'* | ')'*)
                _cfg_line_closed=true
                ;;
        esac
        _cfg_line_rest="${_cfg_line_rest:1}"
    done

    _cfg_line="${_cfg_line%"${_cfg_line##*[![:space:]]}"}"
}

_config_store_value() {
    local -n map_ref="$1"
    local key="$2"
    local value="$3"
    local source_map="${4:-}"
    local origin="${5:-}"
    #shellcheck disable=SC2034 # 此处校验文件语法并保留原字面量
    local parsed_value kind
    local -n kinds_ref="$6"
    [[ "$key" != game.name ]] || die 1 config "$origin 'game.name' 是只读的模板引用"
    _config_value_parse "$value" parsed_value kind "$origin 配置项 '$key'" _config_validate_reference || return $?

    #shellcheck disable=SC2034
    map_ref["$key"]="$value"
    #shellcheck disable=SC2034
    kinds_ref["$key"]=literal
    if [[ -n "$source_map" ]]; then
        local -n origins_ref="$source_map"
        #shellcheck disable=SC2034
        origins_ref["$key"]="$origin"
    fi
}

#shellcheck disable=SC2034 # 解析结果由调用方通过临时表读取
config_parse_to_temp() {
    local file="$1"
    TEMP_CONFIG=()
    TEMP_CONFIG_SOURCE=()
    TEMP_CONFIG_KIND=()
    config_parse_file "$file" TEMP_CONFIG
}

#shellcheck disable=SC2034
config_merge() {
    local -n values="$1" origins="$2" kinds="$3"
    local key
    for key in "${!values[@]}"; do
        CONFIG["$key"]="${values[$key]}"
        CONFIG_SOURCE["$key"]="${origins[$key]}"
        CONFIG_KIND["$key"]="${kinds[$key]}"
    done
}
