#!/hint/bash

[[ -n "${__BOOTSTRAP_SH_LOADED:-}" ]] && return 0

[ "$UID" -ne 0 ] || { echo "你个小天才是怎么想到用 root 运行的（" >&2; return 1; }

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || return 1
PROJECT_ROOT="${SCRIPT_DIR%/*}"
PROJECT_ROOT="${PROJECT_ROOT:-/}"
#shellcheck disable=SC2034
SCRIPTS_DIR="${PROJECT_ROOT%/}/scripts"

cd -- "$PROJECT_ROOT" || return 1
__BOOTSTRAP_SH_LOADED=1
