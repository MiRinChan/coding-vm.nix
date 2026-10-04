#!/usr/bin/env bash
set -euo pipefail

disk="${NIX_DISK_IMAGE:?NIX_DISK_IMAGE is required}"
size_mb="${VM_DISK_SIZE_MB:?VM_DISK_SIZE_MB is required}"
[[ "$size_mb" =~ ^[1-9][0-9]*$ ]] || exit 1
target_bytes=$((size_mb * 1024 * 1024))
preallocate="${VM_DISK_PREALLOCATE:-0}"
case "$preallocate" in
0) allocation=off ;;
1) allocation=falloc ;;
*)
	echo "VM_DISK_PREALLOCATE must be 0 or 1." >&2
	exit 1
	;;
esac

if [ ! -e "$disk" ]; then
	tmp_dir="$(mktemp -d "$(dirname "$disk")/.disk-create.XXXXXXXX")"
	trap 'rm -rf "$tmp_dir"' EXIT
	truncate -s "$target_bytes" "$tmp_dir/root.raw"
	mkfs.ext4 -q -L nixos "$tmp_dir/root.raw"
	qemu-img convert -f raw -O qcow2 -o "preallocation=$allocation" \
		"$tmp_dir/root.raw" "$tmp_dir/root.qcow2"
	mv -n "$tmp_dir/root.qcow2" "$disk"
fi

info="$(qemu-img info --output=json "$disk")"
current_bytes="$(python3 -c '
import json, sys
info = json.load(sys.stdin)
if info["format"] != "qcow2" or info.get("backing-filename"):
    sys.exit("The VM disk must be a standalone qcow2 image.")
print(info["virtual-size"])
' <<<"$info")"

if [ "$current_bytes" -lt "$target_bytes" ]; then
	qemu-img resize --preallocation="$allocation" "$disk" "$target_bytes"
	current_bytes="$target_bytes"
fi

if [ "$preallocate" = "1" ]; then
	# Reserve host blocks for holes left by earlier sparse image creation.
	# Guest discard stays disabled so the reservation survives guest TRIM.
	reserved_bytes="$(qemu-img measure -O qcow2 --output=json --size "$current_bytes" |
		python3 -c 'import json,sys; print(json.load(sys.stdin)["fully-allocated"])')"
	file_bytes="$(stat -c %s "$disk")"
	if [ "$file_bytes" -gt "$reserved_bytes" ]; then
		reserved_bytes="$file_bytes"
	fi
	fallocate -l "$reserved_bytes" "$disk"
	echo "VM disk: $disk, at least $size_mb MiB, host space preallocated."
else
	echo "VM disk: $disk, at least $size_mb MiB, preallocation disabled."
fi
