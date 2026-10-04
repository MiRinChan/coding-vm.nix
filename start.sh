#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$(realpath "$0")")"
mkdir -p .vm-state/gcroots

exec nix develop \
	--accept-flake-config \
	path:. \
	--profile .vm-state/gcroots/host-dev-shell \
	--command run-vm
