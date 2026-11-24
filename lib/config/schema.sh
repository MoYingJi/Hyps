#!/hint/bash

[[ -n "${__CONFIG_SCHEMA_SH_LOADED:-}" ]] && return 0
__CONFIG_SCHEMA_SH_LOADED=1

#shellcheck source=../core/log.sh
source "$SCRIPT_DIR/core/log.sh"

declare -gA CONFIG_SCHEMA=()
declare -ga CONFIG_SCHEMA_KEYS=()
declare -ga CONFIG_NAMESPACE_KEYS=()

# 声明只保存元数据，默认值函数和校验函数在读取时执行
config_declare() {
    _config_declare key "$@"
}

# 命名空间只约束实际出现的成员，不为任意成员创建默认值
config_declare_namespace() {
    _config_declare namespace "$@"
}

_config_declare() {
    [[ $# -ge 3 ]] || die 1 config "配置声明需要名称和类型"
    local kind="$1" key="$2" type="$3"
    shift 3
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]] || die 1 config "非法配置键 '$key'"
    case "$type" in
        string | 'string|array' | bool | uint | int | path | array | args | enum | size) ;;
        *) die 1 config "配置项 '$key' 使用了未知类型 '$type'" ;;
    esac

    local -A fields=([type]="$type")
    local field
    while (( $# )); do
        case "$1" in
            --default | --default-fn | --choices | --when | --validate | --description)
                [[ $# -ge 2 ]] || die 1 config "配置声明 '$key' 的 '$1' 缺少参数"
                field="${1#--}"
                if [[ "$kind" == namespace && ( "$field" == default || "$field" == default-fn ) ]]; then
                    die 1 config "开放命名空间 '$key' 不支持 '$1'"
                fi
                [[ -z "${fields[$field]+exists}" ]] || die 1 config "配置声明 '$key' 重复设置 '$1'"
                fields["$field"]="$2"
                shift 2
                ;;
            --required)
                [[ "$kind" != namespace ]] || die 1 config "开放命名空间 '$key' 不支持 '$1'"
                fields[required]=true
                shift
                ;;
            *) die 1 config "配置声明 '$key' 包含未知选项 '$1'" ;;
        esac
    done

    if [[ -n "${fields[default]+exists}" && -n "${fields[default-fn]+exists}" ]]; then
        die 1 config "配置声明 '$key' 不能同时提供默认值和默认值函数"
    fi
    if [[ "$type" == enum && -z "${fields[choices]:-}" ]]; then
        die 1 config "枚举配置 '$key' 缺少 --choices"
    fi

    [[ "$kind" != namespace ]] || key+=".*"
    if [[ -n "${CONFIG_SCHEMA[$key.type]+exists}" ]]; then
        for field in type default default-fn choices when validate description required; do
            [[ "${CONFIG_SCHEMA[$key.$field]+exists}" == "${fields[$field]+exists}" &&
               "${CONFIG_SCHEMA[$key.$field]:-}" == "${fields[$field]:-}" ]] ||
                die 1 config "配置项 '$key' 的声明冲突"
        done
        return 0
    fi

    if [[ "$kind" == namespace ]]; then
        CONFIG_NAMESPACE_KEYS+=("${key%.*}")
    else
        CONFIG_SCHEMA_KEYS+=("$key")
    fi
    for field in "${!fields[@]}"; do
        CONFIG_SCHEMA["$key.$field"]="${fields[$field]}"
    done
}

# 具体键优先，其次匹配最长的点分隔命名空间前缀
_config_schema_key() {
    local _cfg_lookup_key="$1" _cfg_lookup_prefix
    local -n _cfg_lookup_out="$2"
    _cfg_lookup_out="$_cfg_lookup_key"
    [[ -z "${CONFIG_SCHEMA[$_cfg_lookup_key.type]:-}" ]] || return 0
    _cfg_lookup_prefix="$_cfg_lookup_key"
    while [[ "$_cfg_lookup_prefix" == *.* ]]; do
        _cfg_lookup_prefix="${_cfg_lookup_prefix%.*}"
        if [[ -n "${CONFIG_SCHEMA[$_cfg_lookup_prefix.*.type]:-}" ]]; then
            _cfg_lookup_out="$_cfg_lookup_prefix.*"
            return 0
        fi
    done
}

config_is_declared() {
    local _cfg_declared_key
    _config_schema_key "$1" _cfg_declared_key
    [[ -n "${CONFIG_SCHEMA[$_cfg_declared_key.type]:-}" ]]
}
