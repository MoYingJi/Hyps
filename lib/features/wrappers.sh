#!/hint/bash

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

#shellcheck source=../environment.sh
source "${SCRIPT_DIR:-.}/environment.sh"

RUNNER_WRAPPER=()

wrapper_load_config() {
    local gamescope_args=()
    config_has gamescope.args && config_read_array gamescope.args gamescope_args

    local inhibit_args=()
    config_has inhibit.args && config_read_array inhibit.args inhibit_args


    # 检测 Gamescope 搭配 MangoHud 使用的情况
    if isy "$(config_get gamescope.enabled)" && isy "$(config_get mangohud.enabled)"; then
        log_warn wrapper "Gamescope 搭配 MangoHud 使用，换用 '--mangoapp' 参数"
        gamescope_args+=("--mangoapp")
        config_set mangohud.enabled false
    fi

    # MangoHud
    if isy "$(config_get mangohud.enabled)"; then
        config_require_realpath_which_exe mangohud.exe "mangohud"
        RUNNER_WRAPPER=("$(config_get mangohud.exe)" "${RUNNER_WRAPPER[@]}")
    fi

    # OBS Game Capture (wrapper)
    if isy "$(config_get obs_vkcapture.wrapper.enabled)"; then
        log_warn wrapper "OBS Game Capture 不推荐使用 wrapper 模式。如果你知道你在做什么，请忽略此警告"
        log_warn wrapper "推荐禁用 'obs_vkcapture.wrapper.enabled' 并使用 'obs_vkcapture.env = true'"

        config_require_realpath_which_exe obs_vkcapture.wrapper.exe "obs-gamecapture"
        RUNNER_WRAPPER=("$(config_get obs_vkcapture.wrapper.exe)" "${RUNNER_WRAPPER[@]}")
    fi

    # Gamescope
    if isy "$(config_get gamescope.enabled)"; then
        config_require_realpath_which_exe gamescope.exe "gamescope"
        RUNNER_WRAPPER=("$(config_get gamescope.exe)" "${gamescope_args[@]}" -- "${RUNNER_WRAPPER[@]}")
    fi

    # Taskset
    if isy "$(config_get taskset.enabled)"; then
        config_require_realpath_which_exe taskset.exe "taskset"
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
            taskset_args+=("--mask" "$(config_get taskset.mask)")
        fi

        RUNNER_WRAPPER=("$(config_get taskset.exe)" "${taskset_args[@]}" "${RUNNER_WRAPPER[@]}")
    fi

    # GameMode (wrapper)
    if isy "$(config_get gamemode.wrapper.enabled)"; then
        config_require_realpath_which_exe gamemode.wrapper.exe "gamemoderun"
        RUNNER_WRAPPER=("$(config_get gamemode.wrapper.exe)" "${RUNNER_WRAPPER[@]}")
    fi

    # GameMode (LD_PRELOAD)
    if isy "$(config_get gamemode.ld_preload.enabled)"; then
        config_default gamemode.ld_preload.libs "[ libgamemode.so, libgamemodeauto.so ]" >/dev/null
        local gamemode_libs
        config_read_array gamemode.ld_preload.libs gamemode_libs
        for lib in "${gamemode_libs[@]}"; do
            env_add_ld_preload "$lib"
        done
    fi

    # systemd-inhibit
    if isy "$(config_get inhibit.enabled)"; then
        config_require_realpath_which_exe inhibit.exe "systemd-inhibit"
        inhibit_args+=("--what=$(config_get inhibit.what "idle:sleep")")
        inhibit_args+=("--why=$(config_get inhibit.why "Hyps Game $GAME_NAME")")
        RUNNER_WRAPPER=("$(config_get inhibit.exe)" "${inhibit_args[@]}" -- "${RUNNER_WRAPPER[@]}")
    fi

    # systemd-run
    if isy "$(config_get systemd_run.enabled)"; then
        config_require_realpath_which_exe systemd_run.exe "systemd-run"
        local systemd_run_args=() systemd_run_args_config=()
        config_has systemd_run.args && config_read_array systemd_run.args systemd_run_args_config

        config_default systemd_run.unit "app-hyps-$(systemd-escape -- "hyps-$GAME_NAME")" >/dev/null

        systemd_run_args+=("--user")
        systemd_run_args+=("--scope")
        systemd_run_args+=("--unit=$(config_get systemd_run.unit)-$$")
        systemd_run_args+=("--collect")

        systemd_run_args+=("${systemd_run_args_config[@]}")

        RUNNER_WRAPPER=("$(config_get systemd_run.exe)" "${systemd_run_args[@]}" -- "${RUNNER_WRAPPER[@]}")
    fi

    # 日志
    log_debug wrapper "游戏启动器包装器: $(quote_args "${RUNNER_WRAPPER[@]}")"
}

register_hook load_config wrapper_load_config
