#!/hint/bash

#shellcheck source=../libs.sh
source "$SCRIPT_DIR/libs.sh"

#shellcheck source=../config/environment.sh
source "$SCRIPT_DIR/config/environment.sh"
#shellcheck source=../launch/plan.sh
source "$SCRIPT_DIR/launch/plan.sh"

wrapper_default_systemd_unit() {
    [[ -n "${CONFIG_GAME_NAME:-}" ]] || return 3
    local -n result="$1"
    local escaped
    escaped="$(systemd-escape -- "hyps-$CONFIG_GAME_NAME")" || return 1
    #shellcheck disable=SC2034 # 通过 nameref 写回调用方
    result="app-hyps-$escaped"
}

config_declare mangohud.enabled bool --default false
config_declare mangohud.exe string --default mangohud --when mangohud.enabled
config_declare gamescope.enabled bool --default false
config_declare gamescope.exe string --default gamescope --when gamescope.enabled
config_declare gamescope.args args --default '[]' --when gamescope.enabled
config_declare obs_vkcapture.wrapper.enabled bool --default false
config_declare obs_vkcapture.wrapper.exe string --default obs-gamecapture --when obs_vkcapture.wrapper.enabled
config_declare taskset.enabled bool --default false
config_declare taskset.exe string --default taskset --when taskset.enabled
config_declare taskset.args args --when taskset.enabled
config_declare taskset.cpus array --when taskset.enabled
config_declare taskset.mask string --when taskset.enabled
config_declare gamemode.wrapper.enabled bool --default false
config_declare gamemode.wrapper.exe string --default gamemoderun --when gamemode.wrapper.enabled
config_declare gamemode.ld_preload.enabled bool --default false
config_declare gamemode.ld_preload.libs array --default '[libgamemode.so, libgamemodeauto.so]' \
    --when gamemode.ld_preload.enabled
config_declare inhibit.enabled bool --default false
config_declare inhibit.exe string --default systemd-inhibit --when inhibit.enabled
config_declare inhibit.what string --default idle:sleep --when inhibit.enabled
config_declare inhibit.why string --default '"Hyps Game ${game.name}"' --when inhibit.enabled
config_declare inhibit.args args --default '[]' --when inhibit.enabled
config_declare systemd_run.enabled bool --default false
config_declare systemd_run.exe string --default systemd-run --when systemd_run.enabled
config_declare systemd_run.unit string --default-fn wrapper_default_systemd_unit --when systemd_run.enabled
config_declare systemd_run.args args --default '[]' --when systemd_run.enabled

wrapper_load_config() {
    local gamescope_args=()
    if config_is_true gamescope.enabled; then
        config_read_array gamescope.args gamescope_args
    fi

    # 检测 Gamescope 搭配 MangoHud 使用的情况
    if config_is_true gamescope.enabled && config_is_true mangohud.enabled; then
        log_warn wrapper "Gamescope 搭配 MangoHud 使用，换用 '--mangoapp' 参数"
        gamescope_args+=("--mangoapp")
        config_set mangohud.enabled false
    fi

    # MangoHud
    if config_is_true mangohud.enabled; then
        config_require mangohud.exe executable
        local mangohud_exe
        config_read mangohud.exe mangohud_exe
        launch_plan_runner_wrapper_prepend "$mangohud_exe"
    fi

    # OBS Game Capture (wrapper)
    if config_is_true obs_vkcapture.wrapper.enabled; then
        log_warn wrapper "OBS Game Capture 不推荐使用 wrapper 模式。如果你知道你在做什么，请忽略此警告"
        log_warn wrapper "推荐禁用 'obs_vkcapture.wrapper.enabled' 并使用 'obs_vkcapture.env = true'"

        config_require obs_vkcapture.wrapper.exe executable
        local obs_exe
        config_read obs_vkcapture.wrapper.exe obs_exe
        launch_plan_runner_wrapper_prepend "$obs_exe"
    fi

    # Gamescope
    if config_is_true gamescope.enabled; then
        config_require gamescope.exe executable
        local gamescope_exe
        config_read gamescope.exe gamescope_exe
        launch_plan_runner_wrapper_prepend "$gamescope_exe" "${gamescope_args[@]}" --
    fi

    # Taskset
    if config_is_true taskset.enabled; then
        config_require taskset.exe executable
        local taskset_args=()

        local taskset_config_count=0
        config_has taskset.args && ((taskset_config_count++))
        config_has taskset.cpus && ((taskset_config_count++))
        config_has taskset.mask && ((taskset_config_count++))
        [[ $taskset_config_count -gt 1 ]] && die 1 wrapper "taskset.args、taskset.cpus、taskset.mask 不能同时设置"
        [[ $taskset_config_count -eq 0 ]] && die 1 wrapper "taskset.enabled 为 true 时，必须设置 taskset.args、taskset.cpus、taskset.mask 任选其一"

        if config_has taskset.args; then
            config_read_array taskset.args taskset_args
        fi

        if config_has taskset.cpus; then
            local cpus=()
            config_read_array taskset.cpus cpus
            taskset_args+=("--cpu-list" "$(IFS=,; echo "${cpus[*]}")")
        fi

        if config_has taskset.mask; then
            local taskset_mask
            config_read taskset.mask taskset_mask
            taskset_args+=("--mask" "$taskset_mask")
        fi

        local taskset_exe
        config_read taskset.exe taskset_exe
        launch_plan_runner_wrapper_prepend "$taskset_exe" "${taskset_args[@]}"
    fi

    # GameMode (wrapper)
    if config_is_true gamemode.wrapper.enabled; then
        config_require gamemode.wrapper.exe executable
        local gamemode_exe
        config_read gamemode.wrapper.exe gamemode_exe
        launch_plan_runner_wrapper_prepend "$gamemode_exe"
    fi

    # GameMode (LD_PRELOAD)
    if config_is_true gamemode.ld_preload.enabled; then
        local gamemode_libs
        config_read_array gamemode.ld_preload.libs gamemode_libs
        for lib in "${gamemode_libs[@]}"; do
            launch_plan_ld_preload_append "$lib"
        done
    fi

    # systemd-inhibit
    if config_is_true inhibit.enabled; then
        config_require inhibit.exe executable
        local inhibit_args=()
        config_read_array inhibit.args inhibit_args
        local inhibit_what inhibit_why inhibit_exe
        config_read inhibit.what inhibit_what
        config_read inhibit.why inhibit_why
        config_read inhibit.exe inhibit_exe
        inhibit_args+=("--what=$inhibit_what")
        inhibit_args+=("--why=$inhibit_why")
        launch_plan_runner_wrapper_prepend "$inhibit_exe" "${inhibit_args[@]}" --
    fi

    # systemd-run
    if config_is_true systemd_run.enabled; then
        config_require systemd_run.exe executable
        local systemd_run_args=() systemd_run_args_config=()
        config_read_array systemd_run.args systemd_run_args_config

        local systemd_run_unit systemd_run_exe
        config_read systemd_run.unit systemd_run_unit

        systemd_run_args+=("--user")
        systemd_run_args+=("--scope")
        systemd_run_args+=("--unit=$systemd_run_unit-$$")
        systemd_run_args+=("--collect")

        systemd_run_args+=("${systemd_run_args_config[@]}")

        config_read systemd_run.exe systemd_run_exe
        launch_plan_runner_wrapper_prepend "$systemd_run_exe" "${systemd_run_args[@]}" --
    fi

    # 日志
    local -a runner_wrapper=()
    launch_plan_runner_wrapper_get runner_wrapper
    log_debug wrapper "游戏启动器包装器: $(quote_args "${runner_wrapper[@]}")"
}

register_hook load_config wrapper_load_config
