#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

check_allocation() {
	qemu-img info --output=json "$NIX_DISK_IMAGE" | python3 -c '
import json, os, sys
info = json.load(sys.stdin)
assert info["virtual-size"] == int(sys.argv[1]) * 1024 * 1024, info
allocated = os.stat(os.environ["NIX_DISK_IMAGE"]).st_blocks * 512
if sys.argv[2] == "1":
    assert allocated >= info["virtual-size"], (allocated, info)
else:
    assert allocated < info["virtual-size"], (allocated, info)
' "$1" "$2"
}

for mode in 0 1; do
	if [ "$mode" = 0 ]; then
		unset VM_DISK_PREALLOCATE
	else
		export VM_DISK_PREALLOCATE=1
	fi
	export NIX_DISK_IMAGE="$test_dir/root-$mode.qcow2" VM_DISK_SIZE_MB=64
	bash scripts/prepare-vm-disk.sh
	check_allocation 64 "$mode"
	qemu-img convert -f qcow2 -O raw "$NIX_DISK_IMAGE" "$test_dir/original-$mode.raw"
	e2fsck -fn "$test_dir/original-$mode.raw"

	export VM_DISK_SIZE_MB=128
	bash scripts/prepare-vm-disk.sh
	check_allocation 128 "$mode"
	qemu-img compare -f raw -F qcow2 "$test_dir/original-$mode.raw" "$NIX_DISK_IMAGE"
	qemu-img check "$NIX_DISK_IMAGE"

	# Repeated preparation and a smaller configuration must preserve the disk.
	bash scripts/prepare-vm-disk.sh
	export VM_DISK_SIZE_MB=64
	bash scripts/prepare-vm-disk.sh
	check_allocation 128 "$mode"
	qemu-img compare -f raw -F qcow2 "$test_dir/original-$mode.raw" "$NIX_DISK_IMAGE"
done

# Enable reservation for an existing sparse image without changing its contents.
export NIX_DISK_IMAGE="$test_dir/root-0.qcow2" VM_DISK_PREALLOCATE=1
bash scripts/prepare-vm-disk.sh
check_allocation 128 1
qemu-img compare -f raw -F qcow2 "$test_dir/original-0.raw" "$NIX_DISK_IMAGE"

# Disabling preallocation must preserve existing reserved blocks.
export VM_DISK_PREALLOCATE=0
bash scripts/prepare-vm-disk.sh
check_allocation 128 1
qemu-img compare -f raw -F qcow2 "$test_dir/original-0.raw" "$NIX_DISK_IMAGE"

export NIX_DISK_IMAGE="$test_dir/invalid.qcow2" VM_DISK_PREALLOCATE=invalid
if bash scripts/prepare-vm-disk.sh >/dev/null 2>&1; then
	echo "FAIL: invalid preallocation mode was accepted" >&2
	exit 1
fi
[ ! -e "$NIX_DISK_IMAGE" ]
echo "OK: sparse default, optional preallocation, growth, contents, mode changes, and no shrink"
