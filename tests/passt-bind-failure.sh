#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Send test TCP frames to passt. The host network remains active.
passt_build="$(nix build --no-link --print-out-paths path:.#nixosConfigurations.coding-vm.config.virtualisation.host.pkgs.passt)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cc -Wall -Wextra -Werror -shared -fPIC tests/deny-bind.c -ldl -o "$work/deny-bind.so"
for family in 4 6; do
	python3 tests/bind-failure.py "$family" "$passt_build/bin/passt" "$work/deny-bind.so"
done
