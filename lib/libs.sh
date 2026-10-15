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
