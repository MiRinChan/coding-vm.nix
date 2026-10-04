#!/usr/bin/env bash
set -euo pipefail
exec "$(dirname "$(realpath "$0")")/scripts/control.sh" stop "$@"
