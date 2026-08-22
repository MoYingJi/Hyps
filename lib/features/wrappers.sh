#!/hint/bash

#shellcheck source=../libs.sh
source "${SCRIPT_DIR:-.}/libs.sh"

#shellcheck source=../environment.sh
source "${SCRIPT_DIR:-.}/environment.sh"

RUNNER_WRAPPER=()

wrapper_load_config() {
    local gamescope_args=()
    config_read_array gamescope.args gamescope_args

    local inhibit_args=()
    config_read_array inhibit.args inhibit_args


    # 检测 Gamescope 搭配 MangoHud 使用的情况
    if isy "$(config_get gamescope.enabled)" && isy "$(config_get mangohud.enabled)"; then
        log_warn wrapper "Gamescope 搭配 MangoHud 使用，换用 '--mangoapp' 参数"
        gamescope_args+=("--mangoapp")
        config_set mangohud.enabled false
    fi

    # MangoHud
    if isy "$(config_get mangohud.enabled)"; then
        config_require_realpath_exe mangohud.exe "mangohud"
        RUNNER_WRAPPER=("$(config_get mangohud.exe)" "${RUNNER_WRAPPER[@]}")
    fi

    # Gamescope
    if isy "$(config_get gamescope.enabled)"; then
        config_require_realpath_exe gamescope.exe "gamescope"
        RUNNER_WRAPPER=("$(config_get gamescope.exe)" "${gamescope_args[@]}" -- "${RUNNER_WRAPPER[@]}")
    fi

    # Taskset
    if isy "$(config_get taskset.enabled)"; then
        config_require_realpath_exe taskset.exe "taskset"
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
        config_require_realpath_exe gamemode.wrapper.exe "gamemoderun"
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
        config_require_realpath_exe inhibit.exe "systemd-inhibit"
        inhibit_args+=("--what=$(config_get inhibit.what "idle:sleep")")
        inhibit_args+=("--why=$(config_get inhibit.why "Hyps Game $GAME_NAME")")
        RUNNER_WRAPPER=("$(config_get inhibit.exe)" "${inhibit_args[@]}" -- "${RUNNER_WRAPPER[@]}")
    fi

    # 日志
    log_debug wrapper "游戏启动器包装器: $(quote_args "${RUNNER_WRAPPER[@]}")"
}

register_hook load_config wrapper_load_config
