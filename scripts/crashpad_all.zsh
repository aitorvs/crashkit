#!/usr/bin/env zsh
set -euo pipefail

# Pass through to the two scripts with the same args
SCRIPT_DIR="${0:a:h}"
"${SCRIPT_DIR}/crashpad_gn.zsh" "$@"
"${SCRIPT_DIR}/crashpad_build.zsh" "$@"

