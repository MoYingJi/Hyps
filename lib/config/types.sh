#!/hint/bash

[[ -n "${__CONFIG_TYPES_SH_LOADED:-}" ]] && return 0
__CONFIG_TYPES_SH_LOADED=1

#shellcheck source=schema.sh
source "$SCRIPT_DIR/config/schema.sh"
#shellcheck source=../core/log.sh
source "$SCRIPT_DIR/core/log.sh"
#shellcheck source=../utils/string.sh
source "$SCRIPT_DIR/utils/string.sh"
#shellcheck source=../utils/array.sh
source "$SCRIPT_DIR/utils/array.sh"

_config_normalize() {
    local _cfg_type_key="$1" _cfg_type_origin="$3"
    local -n _cfg_type_value="$2"
    local _cfg_type_schema _cfg_type
    _config_schema_key "$_cfg_type_key" _cfg_type_schema
    _cfg_type="${CONFIG_SCHEMA[$_cfg_type_schema.type]:-string}"
    local _cfg_type_valid=true _cfg_type_choice
    local -a _cfg_type_array=() _cfg_type_choices=()
    case "$_cfg_type" in
        string) ;;
        bool)
            if isy "$_cfg_type_value"; then
                _cfg_type_value=true
            elif isn "$_cfg_type_value"; then
                _cfg_type_value=false
            else
                _cfg_type_valid=false
            fi
            ;;
        uint | int)
            if [[ "$_cfg_type_value" =~ ^[0-9]+$ ||
                  ( "$_cfg_type" == int && "$_cfg_type_value" =~ ^-[0-9]+$ ) ]]; then
                local _cfg_type_sign=""
                if [[ "$_cfg_type_value" == -* ]]; then
                    _cfg_type_sign=-
                    _cfg_type_value="${_cfg_type_value#-}"
                fi
                while [[ "$_cfg_type_value" == 0* && ${#_cfg_type_value} -gt 1 ]]; do
                    _cfg_type_value="${_cfg_type_value#0}"
                done
                [[ "$_cfg_type_value" != 0 ]] || _cfg_type_sign=""
                _cfg_type_value="$_cfg_type_sign$_cfg_type_value"
            else
                _cfg_type_valid=false
            fi
            ;;
        path)
            if [[ -n "$_cfg_type_value" ]]; then
                # 相对路径固定以项目根目录为基准，不受命令当前目录影响
                [[ "$_cfg_type_value" == /* ]] ||
                    _cfg_type_value="$PROJECT_ROOT/$_cfg_type_value"
                _cfg_type_value="$(realpath -m -- "$_cfg_type_value")" ||
                    die 1 config "无法解析配置项 '$_cfg_type_key' 的路径"
            fi
            ;;
        array)
            parse_array "$_cfg_type_value" _cfg_type_array || _cfg_type_valid=false
            ;;
        args)
            parse_args "$_cfg_type_value" _cfg_type_array || _cfg_type_valid=false
            ;;
        enum)
            _cfg_type_valid=false
            IFS=',' read -ra _cfg_type_choices <<< "${CONFIG_SCHEMA[$_cfg_type_schema.choices]}"
            for _cfg_type_choice in "${_cfg_type_choices[@]}"; do
                [[ "$_cfg_type_value" == "$_cfg_type_choice" ]] && _cfg_type_valid=true
            done
            ;;
        size)
            size_string_to_bytes_uint "$_cfg_type_value" >/dev/null || _cfg_type_valid=false
            ;;
    esac
    [[ "$_cfg_type_valid" == true ]] ||
        die 1 config "配置项 '$_cfg_type_key' 的值 '$_cfg_type_value' 不符合类型 '$_cfg_type' ($_cfg_type_origin)"
}
