#!/hint/bash

[[ -n "${__UTILS_SH_LOADED:-}" ]] && return 0
__UTILS_SH_LOADED=1

#shellcheck source=utils/string.sh
source "${SCRIPT_DIR:-.}/utils/string.sh"
#shellcheck source=utils/array.sh
source "${SCRIPT_DIR:-.}/utils/array.sh"
#shellcheck source=utils/command.sh
source "${SCRIPT_DIR:-.}/utils/command.sh"
#shellcheck source=utils/cache.sh
source "${SCRIPT_DIR:-.}/utils/cache.sh"
#shellcheck source=utils/fs.sh
source "${SCRIPT_DIR:-.}/utils/fs.sh"
#shellcheck source=utils/wine.sh
source "${SCRIPT_DIR:-.}/utils/wine.sh"
#shellcheck source=utils/misc.sh
source "${SCRIPT_DIR:-.}/utils/misc.sh"
