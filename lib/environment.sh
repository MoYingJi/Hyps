#!/hint/bash

[[ -n "${__ENVIRONMENT_SH_LOADED:-}" ]] && return 0
__ENVIRONMENT_SH_LOADED=1

#shellcheck source=config/schema.sh
source "$SCRIPT_DIR/config/schema.sh"
#shellcheck source=config/access.sh
source "$SCRIPT_DIR/config/access.sh"
#shellcheck source=utils/array.sh
source "$SCRIPT_DIR/utils/array.sh"
#shellcheck source=utils/string.sh
source "$SCRIPT_DIR/utils/string.sh"
#shellcheck source=core/log.sh
source "$SCRIPT_DIR/core/log.sh"

declare -gA ENV_BINDINGS=()
declare -ga ENV_BINDING_KEYS=()
declare -gA ENV_RESERVED=()
declare -ga ENV_PROVIDERS=() ENV_FINALIZERS=()
declare -gA ENV_INPUT=() ENV_OUTPUT=() ENV_SOURCE=() ENV_PRIORITY=() ENV_CHECK=()
declare -gA _ENV_CANDIDATES=() _ENV_TOP_RANK=() _ENV_TOP_IDS=() _ENV_TARGETS=()
_ENV_CANDIDATE_COUNT=0
_ENV_INPUT_READY=false
_ENV_OUTPUT_READY=false

env_encode_string() {
    local -n _env_string_out="$2"
    _env_string_out="$1"
}

env_encode_bool01() {
    local -n _env_bool_out="$2"
    case "$1" in
        true) _env_bool_out=1 ;;
        false) _env_bool_out=0 ;;
        *) die 1 environment "bool01 编码需要已规范化的布尔值：'$1'" ;;
    esac
}

env_encode_bytes() {
    local -n _env_bytes_out="$2"
    _env_bytes_out="$(size_string_to_bytes_uint "$1")" ||
        die 1 environment "无法将 '$1' 编码为字节数"
}

_env_encode_join() {
    local -a _env_join_values=()
    local -n _env_join_out="$2"
    parse_array "$1" _env_join_values ||
        die 1 environment "配置项 '$4' 需要数组才能使用分隔符编码"
    local IFS="$3"
    _env_join_out="${_env_join_values[*]}"
}

env_encode_comma() { _env_encode_join "$1" "$2" , "$3"; }
env_encode_colon() { _env_encode_join "$1" "$2" : "$3"; }
env_encode_semicolon() { _env_encode_join "$1" "$2" ';' "$3"; }

# 外部变量允许直接使用已编码字符串，数组输入仍须完整解析
_env_encode_list() {
    if is_array "$1"; then
        _env_encode_join "$@"
    else
        env_encode_string "$1" "$2"
    fi
}

env_encode_comma_list() { _env_encode_list "$1" "$2" , "$3"; }
env_encode_colon_list() { _env_encode_list "$1" "$2" : "$3"; }
env_encode_semicolon_list() { _env_encode_list "$1" "$2" ';' "$3"; }

environment_valid_name() {
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

_environment_parse_binding() {
    local -n _env_binding_out="$1"
    shift
    [[ $# -ge 2 ]] || die 1 environment "环境绑定需要配置键和环境变量名"
    # 通过 nameref 填充调用方的关联数组
    #shellcheck disable=SC2154
    _env_binding_out=([key]="$1" [name]="$2" [encode]=string [when]="" [check]="" [policy]=inherit)
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]] ||
        die 1 environment "无效的环境绑定配置键 '$1'"
    environment_valid_name "$2" || die 1 environment "无效的环境变量名 '$2'"
    shift 2
    local _env_binding_option
    local -A _env_binding_seen=()
    while (( $# )); do
        case "$1" in
            --encode | --when | --check | --policy)
                [[ $# -ge 2 ]] || die 1 environment "环境绑定 '$1' 缺少参数"
                _env_binding_option="${1#--}"
                [[ -z "${_env_binding_seen[$_env_binding_option]:-}" ]] ||
                    die 1 environment "环境绑定重复设置 '$1'"
                _env_binding_seen["$_env_binding_option"]=1
                _env_binding_out["$_env_binding_option"]="$2"
                shift 2
                ;;
            *) die 1 environment "未知环境绑定选项 '$1'" ;;
        esac
    done
    case "${_env_binding_out[policy]}" in
        inherit | replace) ;;
        *) die 1 environment "未知环境覆盖策略 '${_env_binding_out[policy]}'" ;;
    esac
    case "${_env_binding_out[check]}" in
        "" | file | dir) ;;
        *) die 1 environment "未知环境路径检查 '${_env_binding_out[check]}'" ;;
    esac
    [[ "${_env_binding_out[encode]}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] ||
        die 1 environment "无效的环境编码器名称 '${_env_binding_out[encode]}'"
}

# 注册阶段只保存声明，允许相同绑定重复加载
env_bind() {
    local -A fields=()
    _environment_parse_binding fields "$@"
    local id="${fields[key]}:${fields[name]}" field
    if [[ -n "${ENV_BINDINGS[$id.key]+exists}" ]]; then
        for field in key name encode when check policy; do
            [[ "${ENV_BINDINGS[$id.$field]}" == "${fields[$field]}" ]] ||
                die 1 environment "环境绑定 '$id' 的声明冲突"
        done
        return 0
    fi
    ENV_BINDING_KEYS+=("$id")
    for field in "${!fields[@]}"; do
        ENV_BINDINGS["$id.$field"]="${fields[$field]}"
    done
}

# 声明同名 env 配置并绑定输出，配置类型不再从编码器反推
env_declare() {
    [[ $# -ge 2 ]] || die 1 environment "环境声明需要变量名和配置类型"
    local name="$1" type="$2"
    shift 2
    local -a schema_options=() binding_options=()
    while (( $# )); do
        case "$1" in
            --encode | --check | --policy)
                [[ $# -ge 2 ]] || die 1 environment "环境声明 '$1' 缺少参数"
                binding_options+=("$1" "$2")
                shift 2
                ;;
            --default | --default-fn | --choices | --when | --validate | --description)
                [[ $# -ge 2 ]] || die 1 environment "配置声明 '$1' 缺少参数"
                schema_options+=("$1" "$2")
                shift 2
                ;;
            --required) schema_options+=("$1"); shift ;;
            *) die 1 environment "未知环境声明选项 '$1'" ;;
        esac
    done
    environment_valid_name "$name" || die 1 environment "无效的环境变量名 '$name'"
    config_declare "env.$name" "$type" "${schema_options[@]}"
    env_bind "env.$name" "$name" "${binding_options[@]}"
}

# 被 Launch Plan 等组件管理的变量不参与普通环境导出
env_reserve() {
    environment_valid_name "$1" || die 1 environment "无效的环境变量名 '$1'"
    ENV_RESERVED["$1"]=1
}

environment_register_provider() {
    local fn
    for fn in "${ENV_PROVIDERS[@]}"; do
        [[ "$fn" != "$1" ]] || return 0
    done
    ENV_PROVIDERS+=("$1")
}

environment_register_finalizer() {
    local fn
    for fn in "${ENV_FINALIZERS[@]}"; do
        [[ "$fn" != "$1" ]] || return 0
    done
    ENV_FINALIZERS+=("$1")
}

# 在功能钩子运行前保存输入，后续解析不会把本次生成的值当成输入
environment_capture() {
    _ENV_OUTPUT_READY=false
    ENV_INPUT=()
    local _env_capture_name
    while IFS= read -r _env_capture_name; do
        environment_valid_name "$_env_capture_name" || continue
        [[ "${!_env_capture_name@a}" != *a* && "${!_env_capture_name@a}" != *A* ]] || continue
        ENV_INPUT["$_env_capture_name"]="${!_env_capture_name}"
    done < <(compgen -e)
    _ENV_INPUT_READY=true
}

_environment_candidate() {
    local name="$1" rank="$4" id="$_ENV_CANDIDATE_COUNT"
    ((_ENV_CANDIDATE_COUNT += 1))
    _ENV_CANDIDATES["$id.value"]="$2"
    _ENV_CANDIDATES["$id.source"]="$3"
    _ENV_CANDIDATES["$id.encode"]="$5"
    _ENV_CANDIDATES["$id.key"]="$6"
    _ENV_CANDIDATES["$id.check"]="$7"
    if [[ -z "${_ENV_TOP_RANK[$name]+exists}" || "$rank" -gt "${_ENV_TOP_RANK[$name]}" ]]; then
        _ENV_TOP_RANK["$name"]="$rank"
        _ENV_TOP_IDS["$name"]="$id"
    elif [[ "$rank" -eq "${_ENV_TOP_RANK[$name]}" ]]; then
        _ENV_TOP_IDS["$name"]+=" $id"
    fi
}

_environment_collect_binding() {
    local -n _env_collect_fields="$1"
    local _env_collect_key="${_env_collect_fields[key]}" _env_collect_name="${_env_collect_fields[name]}"
    local _env_collect_value _env_collect_source _env_collect_rc=0 _env_collect_rank=10
    [[ -z "${ENV_RESERVED[$_env_collect_name]:-}" ]] || return 0
    _ENV_TARGETS["$_env_collect_name"]=1
    if [[ -n "${_env_collect_fields[when]}" ]]; then
        local _env_collect_condition
        _config_schema_key "${_env_collect_fields[when]}" _env_collect_condition
        [[ "${CONFIG_SCHEMA[$_env_collect_condition.type]:-}" == bool ]] ||
            die 1 environment "环境绑定的条件 '${_env_collect_fields[when]}' 必须声明为 bool"
        config_is_true "${_env_collect_fields[when]}" || return 0
    fi
    _config_schema_active "$_env_collect_key" || return 0
    _config_resolve "$_env_collect_key" _env_collect_value _env_collect_source || _env_collect_rc=$?
    [[ "$_env_collect_rc" -ne 3 ]] || return 0
    [[ "$_env_collect_rc" -eq 0 ]] || return "$_env_collect_rc"
    if config_has "$_env_collect_key"; then
        _env_collect_rank=20
        [[ "$_env_collect_key" != env.* ]] || _env_collect_rank=30
    fi
    [[ "${_env_collect_fields[policy]}" != replace ]] || _env_collect_rank=50
    _environment_candidate "$_env_collect_name" "$_env_collect_value" \
        "$_env_collect_key ($_env_collect_source)" "$_env_collect_rank" \
        "${_env_collect_fields[encode]}" "$_env_collect_key" "${_env_collect_fields[check]}"
}

# 动态绑定由只读 provider 在解析时提供，不修改注册表
environment_offer() {
    #shellcheck disable=SC2034
    local -A offer_fields=()
    _environment_parse_binding offer_fields "$@"
    _environment_collect_binding offer_fields
}

# 先收集全部候选，再编码最终优先级的值，结果不受绑定注册顺序影响
environment_resolve() {
    [[ "$_ENV_INPUT_READY" == true ]] || environment_capture
    _ENV_OUTPUT_READY=false
    _ENV_CANDIDATES=() _ENV_TOP_RANK=() _ENV_TOP_IDS=() _ENV_TARGETS=()
    _ENV_CANDIDATE_COUNT=0
    local id field key name fn value source encoder check
    local -A binding_fields=() handled=() env_keys=()
    for id in "${ENV_BINDING_KEYS[@]}"; do
        for field in key name encode when check policy; do
            binding_fields["$field"]="${ENV_BINDINGS[$id.$field]}"
        done
        handled["${binding_fields[key]}"]=1
        _environment_collect_binding binding_fields || return 1
    done
    for key in "${CONFIG_SCHEMA_KEYS[@]}" "${!CONFIG[@]}"; do
        [[ "$key" != env.* ]] || env_keys["$key"]=1
    done
    for key in "${!env_keys[@]}"; do
        [[ -z "${handled[$key]:-}" ]] || continue
        environment_offer "$key" "${key#env.}" || return 1
    done
    for fn in "${ENV_PROVIDERS[@]}"; do
        declare -F "$fn" >/dev/null || die 1 environment "环境 provider '$fn' 不存在"
        "$fn" || return 1
    done
    for name in "${!_ENV_TARGETS[@]}"; do
        [[ -n "${ENV_INPUT[$name]+exists}" ]] || continue
        _environment_candidate "$name" "${ENV_INPUT[$name]}" "输入环境 $name" 40 string "" ""
    done

    local -A resolved_values=() resolved_sources=() resolved_checks=()
    local -a candidate_ids=()
    for name in "${!_ENV_TOP_IDS[@]}"; do
        read -ra candidate_ids <<< "${_ENV_TOP_IDS[$name]}"
        for id in "${candidate_ids[@]}"; do
            encoder="env_encode_${_ENV_CANDIDATES[$id.encode]}"
            declare -F "$encoder" >/dev/null || die 1 environment "环境编码器 '$encoder' 不存在"
            value=""
            "$encoder" "${_ENV_CANDIDATES[$id.value]}" value "${_ENV_CANDIDATES[$id.key]}" || return 1
            source="${_ENV_CANDIDATES[$id.source]}"
            check="${_ENV_CANDIDATES[$id.check]}"
            if [[ -n "${resolved_values[$name]+exists}" ]]; then
                [[ "${resolved_values[$name]}" == "$value" ]] ||
                    die 1 environment "环境变量 '$name' 的同级来源冲突：${resolved_sources[$name]} 与 $source"
                resolved_sources["$name"]+="、$source"
                # 同值候选的操作要求也要保留
                [[ -z "$check" ]] || resolved_checks["$name"]+=" $check"
            else
                resolved_values["$name"]="$value"
                resolved_sources["$name"]="$source"
                resolved_checks["$name"]="$check"
            fi
        done
    done
    ENV_OUTPUT=() ENV_SOURCE=() ENV_PRIORITY=() ENV_CHECK=()
    for name in "${!resolved_values[@]}"; do
        ENV_OUTPUT["$name"]="${resolved_values[$name]}"
        ENV_SOURCE["$name"]="${resolved_sources[$name]}"
        # 优先级供集成模块的一致性检查使用
        #shellcheck disable=SC2034
        ENV_PRIORITY["$name"]="${_ENV_TOP_RANK[$name]}"
        ENV_CHECK["$name"]="${resolved_checks[$name]}"
    done
    for fn in "${ENV_FINALIZERS[@]}"; do
        declare -F "$fn" >/dev/null || die 1 environment "环境 finalizer '$fn' 不存在"
        "$fn" || return 1
    done
    _ENV_OUTPUT_READY=true
}

environment_read() {
    local -n _env_read_out="$2"
    _env_read_out="${ENV_OUTPUT[$1]-}"
    [[ -n "${ENV_OUTPUT[$1]+exists}" ]]
}

environment_source() {
    local -n _env_source_out="$2"
    _env_source_out="${ENV_SOURCE[$1]-未设置}"
}

# 检查最终值的操作要求，解析和查询本身不会创建目录
environment_check() {
    [[ "$_ENV_OUTPUT_READY" == true ]] || die 1 environment "需要先成功解析环境才能应用"
    local name check
    local -a checks=()
    for name in "${!ENV_OUTPUT[@]}"; do
        read -ra checks <<< "${ENV_CHECK[$name]}"
        for check in "${checks[@]}"; do
            case "$check" in
                file) [[ -f "${ENV_OUTPUT[$name]}" ]] ||
                    die 1 environment "'$name' 指向的文件不存在：${ENV_OUTPUT[$name]} (${ENV_SOURCE[$name]})" ;;
                dir) [[ -d "${ENV_OUTPUT[$name]}" ]] ||
                    die 1 environment "'$name' 指向的目录不存在：${ENV_OUTPUT[$name]} (${ENV_SOURCE[$name]})" ;;
            esac
        done
    done
}

# 生成命令数组，调用方直接执行以保留异步进程的 PID
# 环境只交给该命令及其后代，不修改当前 shell
environment_command_get() {
    local -n _env_command_out="$1"
    shift
    _env_command_out=()
    [[ $# -gt 0 ]] || die 1 environment "环境命令缺少可执行程序"
    environment_check || return $?

    local _env_command_name
    local -a _env_command_values=()
    for _env_command_name in "${!ENV_OUTPUT[@]}"; do
        _env_command_values+=("$_env_command_name=${ENV_OUTPUT[$_env_command_name]}")
        log_debug environment "命令环境 $_env_command_name=${ENV_OUTPUT[$_env_command_name]} (${ENV_SOURCE[$_env_command_name]})"
    done
    _env_command_out=(env -- "${_env_command_values[@]}" "$@")
}
