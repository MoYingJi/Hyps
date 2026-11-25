#!/usr/bin/bash

#shellcheck source=../modules.sh
source "$SCRIPT_DIR/modules.sh"
#shellcheck source=../config.sh
source "$SCRIPT_DIR/config.sh"
#shellcheck source=../config/schema.sh
source "$SCRIPT_DIR/config/schema.sh"
#shellcheck source=../config/access.sh
source "$SCRIPT_DIR/config/access.sh"
#shellcheck source=../core/console.sh
source "$SCRIPT_DIR/core/console.sh"
#shellcheck source=../core/log.sh
source "$SCRIPT_DIR/core/log.sh"

help_config() {
    cat <<'EOF'
查看配置声明、有效值及来源，或按声明检查配置

用法:
  config schema [游戏名] [--prefix 前缀]  查看声明，不读取用户配置
  config show   [游戏名] [--prefix 前缀]  查看有效值及来源
  config check  [游戏名] [--prefix 前缀]  检查当前启用的配置项

省略游戏名时只使用共用配置，不检查游戏和运行器是否已安装
EOF
}

_config_command_prepare() {
    local mode="$1" game="" impl
    shift
    CONFIG_COMMAND_PREFIX=""
    while (( $# )); do
        case "$1" in
            --prefix)
                [[ $# -ge 2 && -n "$2" ]] || die 2 config "--prefix 缺少配置前缀"
                CONFIG_COMMAND_PREFIX="$2"
                shift 2
                ;;
            -*) die 2 config "未知选项 '$1'" ;;
            *)
                [[ -z "$game" ]] || die 2 config "一次只能指定一个游戏名"
                game_name_valid "$1" || die 2 config "无效的游戏名 '$1'"
                game="$1"
                shift
                ;;
        esac
    done

    hyps_load_modules || return $?
    if [[ -n "$game" ]]; then
        #shellcheck disable=SC2034
        GAME_NAME="$game"
        impl="$SCRIPT_DIR/games/$game.sh"
        if [[ -f "$impl" ]]; then
            #shellcheck source=/dev/null
            source "$impl" || return $?
        fi
    fi

    if [[ "$mode" != schema ]]; then
        load_common_config || return $?
        if [[ -n "$game" ]]; then
            load_game_config "$game" || return $?
        fi
    fi
    return 0
}

command_config_schema() {
    _config_command_prepare schema "$@" || return $?
    local key namespace default_value
    local -a schema_keys=("${CONFIG_SCHEMA_KEYS[@]}")
    for namespace in "${CONFIG_NAMESPACE_KEYS[@]}"; do
        schema_keys+=("$namespace.*")
    done
    for key in "${schema_keys[@]}"; do
        [[ -z "$CONFIG_COMMAND_PREFIX" || "$key" == "$CONFIG_COMMAND_PREFIX" ||
           "$key" == "$CONFIG_COMMAND_PREFIX".* ||
           ( "$key" == *'.*' && "$CONFIG_COMMAND_PREFIX" == "${key%.*}".* ) ]] || continue
        default_value="${CONFIG_SCHEMA[$key.default]-未设置}"
        if [[ -n "${CONFIG_SCHEMA[$key.default-fn]:-}" ]]; then
            default_value="由 ${CONFIG_SCHEMA[$key.default-fn]} 计算"
        fi
        printf '%s [%s]\n' "$(style_quote bright_blue,bold "$key")" \
            "$(style_quote cyan "${CONFIG_SCHEMA[$key.type]}")"
        if [[ "$key" == *'.*' ]]; then
            printf '  %s\n' "$(style_quote bright_black '开放命名空间，仅检查实际出现的成员')"
        else
            printf '  %s %s\n' "$(style_quote bright_black '默认值:')" "$default_value"
        fi
        [[ -z "${CONFIG_SCHEMA[$key.choices]:-}" ]] ||
            printf '  %s %s\n' "$(style_quote bright_black '可选值:')" "${CONFIG_SCHEMA[$key.choices]}"
        [[ -z "${CONFIG_SCHEMA[$key.when]:-}" ]] ||
            printf '  %s %s\n' "$(style_quote bright_black '条件:')" "${CONFIG_SCHEMA[$key.when]}"
        [[ "${CONFIG_SCHEMA[$key.required]:-}" != true ]] ||
            printf '  %s\n' "$(style_quote yellow '必需: 是')"
        [[ -z "${CONFIG_SCHEMA[$key.description]:-}" ]] ||
            printf '  %s %s\n' "$(style_quote bright_black '说明:')" "${CONFIG_SCHEMA[$key.description]}"
    done
    return 0
}

command_config_show() {
    _config_command_prepare show "$@" || return $?
    local key value origin rc value_style
    local -A keys=()
    for key in "${!CONFIG[@]}" "${CONFIG_SCHEMA_KEYS[@]}"; do
        keys["$key"]=1
    done
    while IFS= read -r key; do
        [[ -z "$CONFIG_COMMAND_PREFIX" || "$key" == "$CONFIG_COMMAND_PREFIX" ||
           "$key" == "$CONFIG_COMMAND_PREFIX".* ]] || continue
        _config_schema_active "$key" || continue
        rc=0
        _config_resolve "$key" value origin || rc=$?
        [[ "$rc" -eq 0 || "$rc" -eq 3 ]] || return "$rc"
        value_style=green
        [[ "$rc" -ne 3 ]] || value_style=bright_black
        printf '%s = %s\t%s\n' "$(style_quote bright_blue "$key")" \
            "$(style_quote "$value_style" "$value")" "$(style_quote bright_black "# $origin")"
    done < <(printf '%s\n' "${!keys[@]}" | LC_ALL=C sort)
}

command_config_check() {
    _config_command_prepare check "$@" || return $?
    if [[ -n "$CONFIG_COMMAND_PREFIX" ]]; then
        config_validate "$CONFIG_COMMAND_PREFIX" || return $?
    else
        config_validate || return $?
    fi
    local key
    for key in "${!CONFIG[@]}"; do
        [[ -z "$CONFIG_COMMAND_PREFIX" || "$key" == "$CONFIG_COMMAND_PREFIX" ||
           "$key" == "$CONFIG_COMMAND_PREFIX".* ]] || continue
        config_is_declared "$key" && continue
        log_warn config "配置项 '$key' 尚未声明 (${CONFIG_SOURCE[$key]:-运行时})"
    done
    printf '%s\n' "$(style_quote green,bold '配置检查通过')"
}
