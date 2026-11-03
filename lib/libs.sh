#!/hint/bash

[[ -n "${__LIBS_SH_LOADED:-}" ]] && return 0
__LIBS_SH_LOADED=1

#shellcheck source=core/console.sh
source "$SCRIPT_DIR/core/console.sh"
#shellcheck source=core/log.sh
source "$SCRIPT_DIR/core/log.sh"
#shellcheck source=utils.sh
source "$SCRIPT_DIR/utils.sh"
#shellcheck source=core/lifecycle.sh
source "$SCRIPT_DIR/core/lifecycle.sh"
#shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"
#shellcheck source=launch/plan.sh
source "$SCRIPT_DIR/launch/plan.sh"
#shellcheck source=launch/game_handler.sh
source "$SCRIPT_DIR/launch/game_handler.sh"
#shellcheck source=launch/mode_script.sh
source "$SCRIPT_DIR/launch/mode_script.sh"
#shellcheck source=launch/mode_direct.sh
source "$SCRIPT_DIR/launch/mode_direct.sh"
