#!/usr/bin/env bash
set -euo pipefail
project_root="$(dirname "$(dirname "$(realpath "$0")")")"
state="${VM_STATE_DIR:-}"
if [ -z "$state" ]; then
	if [ -f "$project_root/.instance-state" ]; then
		state="$(cat "$project_root/.instance-state")"
		[[ "$state" = /* ]] || state="$project_root/$state"
	elif [ -d "$project_root/.vm-state" ]; then
		state="$project_root/.vm-state"
	else
		state="$HOME/.local/state/coding-vm"
	fi
fi
if [ -x "$state/runtime-python" ]; then
	python="$state/runtime-python"
elif command -v python3 >/dev/null 2>&1; then
	python="$(command -v python3)"
else
	exec nix develop --accept-flake-config "$project_root#tools" --command \
		python3 "$project_root/scripts/vm-runtime.py" --state-dir "$state" "$@"
fi
exec "$python" "$project_root/scripts/vm-runtime.py" --state-dir "$state" "$@"
