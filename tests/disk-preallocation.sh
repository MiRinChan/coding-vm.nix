#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
export NIX_DISK_IMAGE="$test_dir/root.qcow2" VM_DISK_SIZE_MB=64
bash scripts/prepare-vm-disk.sh
qemu-img convert -f qcow2 -O raw "$NIX_DISK_IMAGE" "$test_dir/original.raw"
e2fsck -fn "$test_dir/original.raw"

export VM_DISK_SIZE_MB=128
bash scripts/prepare-vm-disk.sh
qemu-img compare -f raw -F qcow2 "$test_dir/original.raw" "$NIX_DISK_IMAGE"
qemu-img check "$NIX_DISK_IMAGE"

# Repeated preparation and a smaller configuration must preserve the disk.
bash scripts/prepare-vm-disk.sh
export VM_DISK_SIZE_MB=64
bash scripts/prepare-vm-disk.sh
qemu-img info --output=json "$NIX_DISK_IMAGE" | python3 -c '
import json, os, sys
info = json.load(sys.stdin)
assert info["virtual-size"] == 128 * 1024 * 1024, info
stat = os.stat(os.environ["NIX_DISK_IMAGE"])
assert stat.st_blocks * 512 >= info["virtual-size"], stat
'
qemu-img compare -f raw -F qcow2 "$test_dir/original.raw" "$NIX_DISK_IMAGE"
echo "OK: disk creation, growth, contents, host preallocation, and no shrink"
