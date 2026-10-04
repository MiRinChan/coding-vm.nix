#!/usr/bin/env bash
set -euo pipefail

# SSH connection defaults for the development VM.
host="coding-vm"
port="${VM_SSH_PORT:-2223}"
user="${VM_USER:-alice}"

if [ "${VM_REQUIRE_TAILSCALE_EXIT:-1}" = "1" ]; then
	tailscale status --json | python3 -c '
import json, sys
status = json.load(sys.stdin)
exit_node = status.get("ExitNodeStatus") or {}
if status.get("BackendState") != "Running" or not exit_node.get("Online"):
    sys.exit("Select an online Tailscale exit node before starting the VM.")
'
	for destination in "${VM_DNS4:-1.1.1.1}" "${VM_DNS6:-2606:4700:4700::1111}"; do
		if ! ip route get "$destination" | grep -qw "${VM_NETWORK_INTERFACE:-tailscale0}"; then
			echo "The route to $destination must use ${VM_NETWORK_INTERFACE:-tailscale0}." >&2
			exit 1
		fi
	done
fi

project_root="${CODING_VM_PROJECT_ROOT:-$PWD}"

shopt -s nullglob
vm_runners=("$VM_RUNNER_DIR"/run-*-vm)
shopt -u nullglob

if [ "${#vm_runners[@]}" -eq 0 ]; then
	echo "Cannot find VM runner under $VM_RUNNER_DIR" >&2
	echo "Available files:" >&2
	ls -la "$VM_RUNNER_DIR" >&2 || true
	exit 1
fi

vm_runner="${vm_runners[0]}"

key="${VM_SSH_KEY:-$HOME/.ssh/coding-vm_ed25519}"
ssh_config="$HOME/.ssh/config"

# User-facing path for the VM filesystem.
# Important: the real FUSE mount is kept outside the flake source tree,
# and ./virtualMachine is only a symlink to it. Otherwise `nix develop`
# tries to snapshot the FUSE mount and can fail with Input/output error.
export VM_FS_MOUNT_DIR="${VM_FS_MOUNT_DIR:-$project_root/virtualMachine}"
export VM_FS_REMOTE="${VM_FS_REMOTE:-/home/$user}"

runtime_base="${XDG_RUNTIME_DIR:-/tmp}"
uid="$(id -u)"
export VM_FS_REAL_MOUNT_DIR="${VM_FS_REAL_MOUNT_DIR:-$runtime_base/coding-vm-$uid/virtualMachine}"

# NixOS supplies the privileged FUSE helper outside the store.
fuse_unmount="$(command -v fusermount3)"
if [ -x /run/wrappers/bin/fusermount3 ]; then
	fuse_unmount=/run/wrappers/bin/fusermount3
fi

# Keep VM runtime state away from the mounted filesystem.
export VM_STATE_DIR="${VM_STATE_DIR:-$project_root/.vm-state}"
VM_STATE_DIR="$(realpath -m "$VM_STATE_DIR")"
export NIX_DISK_IMAGE="$VM_STATE_DIR/nixos.qcow2"

# First boot can be slow while the image and host keys are initialized.
ssh_timeout="${VM_SSH_TIMEOUT:-900}"

shared="$VM_STATE_DIR/shared"
export SHARED_DIR="$shared"

# Keep SSH host-key state local to this project and reset it each run.
known_hosts="$VM_STATE_DIR/known_hosts"

mkdir -p "$HOME/.ssh" "$shared" "$VM_STATE_DIR"

# Hold the launch lock until QEMU exits.
exec 9>"$VM_STATE_DIR/launch.lock"
if ! flock -n 9; then
	echo "A VM launcher already holds $VM_STATE_DIR/launch.lock." >&2
	exit 1
fi
bash "$VM_DISK_PREPARER"

# Keep roots outside the flake source and retain previous VM generations.
gc_roots="$VM_STATE_DIR/gcroots"
mkdir -p "$gc_roots"
nix-store --add-root "$gc_roots/$(basename "$VM_BUILD")" \
	--indirect --realise "$VM_BUILD" >/dev/null

# A user service cannot exceed the user manager's hard limit.
manager_pid="$(systemctl show "user@$uid.service" --property=MainPID --value)"
manager_limit="$(awk '/^Max open files/ {print $5}' "/proc/$manager_pid/limits")"
if [ "$manager_limit" != unlimited ] && [ "$manager_limit" -lt 2097152 ]; then
	echo "The user manager needs a hard NOFILE limit of 2097152." >&2
	echo "Run: sudo prlimit --pid $manager_pid --nofile=2097152:2097152" >&2
	exit 1
fi

: >"$known_hosts"

mkdir -p "$(dirname "$VM_FS_MOUNT_DIR")" "$(dirname "$VM_FS_REAL_MOUNT_DIR")"

# A previous sshfs session can leave a stale FUSE mount behind.
# When that happens, even `mkdir -p` may fail with Input/output error.
if ! mkdir -p "$VM_FS_REAL_MOUNT_DIR" 2>/tmp/coding-vm-mkdir.err; then
	echo "Real FUSE mount path looks stale, trying to detach it:" >&2
	echo "  $VM_FS_REAL_MOUNT_DIR" >&2

	"$fuse_unmount" -uz "$VM_FS_REAL_MOUNT_DIR" >/dev/null 2>&1 || true
	umount -l "$VM_FS_REAL_MOUNT_DIR" >/dev/null 2>&1 || true

	if ! mkdir -p "$VM_FS_REAL_MOUNT_DIR"; then
		echo "Could not recover stale FUSE mount automatically." >&2
		echo "Original mkdir error:" >&2
		cat /tmp/coding-vm-mkdir.err >&2 || true
		echo >&2
		echo "Run this manually, then try again:" >&2
		echo "  fusermount3 -uz $VM_FS_REAL_MOUNT_DIR 2>/dev/null || true" >&2
		echo "  sudo umount -l $VM_FS_REAL_MOUNT_DIR 2>/dev/null || true" >&2
		echo "  rm -rf $VM_FS_REAL_MOUNT_DIR" >&2
		exit 1
	fi
fi
rm -f /tmp/coding-vm-mkdir.err

if [ -L "$VM_FS_MOUNT_DIR" ]; then
	current_target="$(readlink "$VM_FS_MOUNT_DIR")"
	if [ "$current_target" != "$VM_FS_REAL_MOUNT_DIR" ]; then
		ln -sfn "$VM_FS_REAL_MOUNT_DIR" "$VM_FS_MOUNT_DIR"
	fi
elif [ -e "$VM_FS_MOUNT_DIR" ]; then
	if mountpoint -q "$VM_FS_MOUNT_DIR"; then
		echo "$VM_FS_MOUNT_DIR is a real mountpoint inside the flake tree." >&2
		echo "Unmount it first:" >&2
		echo "  fusermount3 -uz $VM_FS_MOUNT_DIR" >&2
		exit 1
	fi

	if [ -n "$(find "$VM_FS_MOUNT_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
		echo "$VM_FS_MOUNT_DIR exists but is not empty, so I will not replace it with a symlink." >&2
		echo "Move its contents elsewhere, or set VM_FS_MOUNT_DIR to another path." >&2
		exit 1
	fi

	rmdir "$VM_FS_MOUNT_DIR"
	ln -s "$VM_FS_REAL_MOUNT_DIR" "$VM_FS_MOUNT_DIR"
else
	ln -s "$VM_FS_REAL_MOUNT_DIR" "$VM_FS_MOUNT_DIR"
fi

if [ ! -f "$key" ]; then
	ssh-keygen -t ed25519 -N "" -f "$key" -C "coding-vm"
fi

cp "$key.pub" "$shared/authorized_keys"

chmod 700 "$HOME/.ssh"
touch "$ssh_config"
chmod 600 "$ssh_config"

# Replace managed and unmarked VM alias blocks before writing connection settings.
# Duplicate alias blocks can cause OpenSSH to use stale settings.
tmp_config="$(mktemp)"
awk '
            function is_host_line() { return $0 ~ /^[[:space:]]*Host[[:space:]]+/ }
            function is_match_line() { return $0 ~ /^[[:space:]]*Match[[:space:]]+/ }
            function is_managed_begin() { return $0 ~ /^[[:space:]]*# BEGIN coding-vm managed( block)?[[:space:]]*$/ }
            function is_managed_end() { return $0 ~ /^[[:space:]]*# END coding-vm managed( block)?[[:space:]]*$/ }
            function is_vm_host_line() {
              for (i = 2; i <= NF; i++) {
                if ($i == "coding-vm" || $i == "coding-vm-iso") {
                  return 1
                }
              }

              return 0
            }

            is_managed_begin() {
              managed = 1
              skip = 1
              next
            }

            managed {
              if (is_managed_end()) {
                managed = 0
                skip = 0
              }
              next
            }

            is_host_line() || is_match_line() {
              skip = 0
            }

            is_host_line() && is_vm_host_line() {
              skip = 1
              next
            }

            !skip {
              print
            }
          ' "$ssh_config" >"$tmp_config"
cat "$tmp_config" >"$ssh_config"
rm -f "$tmp_config"

cat >>"$ssh_config" <<EOF

# BEGIN coding-vm managed
Host $host
  HostName 127.0.0.1
  Port $port
  User $user
  IdentityFile $key
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
  UserKnownHostsFile $known_hosts
# END coding-vm managed
EOF

if [ "${OPEN_VSCODE:-1}" = "1" ]; then
	if ! command -v code >/dev/null 2>&1; then
		echo "Cannot find host VS Code 'code' command."
		echo "In host VS Code, run: Shell Command: Install 'code' command in PATH"
		exit 1
	fi

	# Install/refresh Remote-SSH extension on the host VS Code if possible.
	if ! code --list-extensions | grep -qx ms-vscode-remote.remote-ssh; then
		code --install-extension ms-vscode-remote.remote-ssh >/dev/null 2>&1 || true
	fi
fi

log_dir="$VM_STATE_DIR/logs"
mkdir -p "$log_dir"
vm_log="$log_dir/qemu.log"
: >"$vm_log"

safe_tail() {
	local lines="$1"
	tail -n "$lines" "$vm_log" | LC_ALL=C cat -v
}

if [ "${VM_REQUIRE_TAILSCALE_EXIT:-1}" = "1" ]; then
	echo "VM IPv4 and IPv6 sockets bind to ${VM_NETWORK_INTERFACE:-tailscale0}."
else
	echo "VM uses host-routed QEMU user networking."
fi

echo "Starting VM. QEMU log: $vm_log"

vm_scope_unit="coding-vm-qemu-${BASHPID}"
systemd-run --user --unit="$vm_scope_unit" --service-type=exec \
	--property=LimitNOFILE=2097152 --wait --pipe --collect --quiet \
	--working-directory="$VM_STATE_DIR" \
	--setenv="NIX_DISK_IMAGE=$NIX_DISK_IMAGE" --setenv="SHARED_DIR=$SHARED_DIR" \
	--setenv="QEMU_OPTS=${QEMU_OPTS:-}" \
	--setenv="VM_SSH_PORT=$port" \
	--setenv="QEMU_KERNEL_PARAMS=${QEMU_KERNEL_PARAMS:-}" \
	"$vm_runner" </dev/null >"$vm_log" 2>&1 &
vm_pid="$!"
network_guard_pid=""

stop_vm() {
	systemctl --user stop "$vm_scope_unit.service" >/dev/null 2>&1 || true
	kill "$vm_pid" >/dev/null 2>&1 || true
}

network_guard() {
	while sleep 2; do
		if ! tailscale status --json | python3 -c '
import json, sys

status = json.load(sys.stdin)
exit_node = status.get("ExitNodeStatus") or {}

if status.get("BackendState") != "Running":
    raise SystemExit(1)

if not exit_node.get("Online"):
    raise SystemExit(1)
'; then
			echo "Tailscale exit node is unavailable. Stopping VM." >&2
			systemctl --user stop "$vm_scope_unit.service" >/dev/null 2>&1 || true
			return
		fi

		if ! ip route get "${VM_DNS4:-1.1.1.1}" | grep -qw "dev ${VM_NETWORK_INTERFACE:-tailscale0}"; then
			echo "IPv4 no longer routes through ${VM_NETWORK_INTERFACE:-tailscale0}. Stopping VM." >&2
			systemctl --user stop "$vm_scope_unit.service" >/dev/null 2>&1 || true
			return
		fi

		if ! ip -6 route get "${VM_DNS6:-2606:4700:4700::1111}" | grep -qw "dev ${VM_NETWORK_INTERFACE:-tailscale0}"; then
			echo "IPv6 no longer routes through ${VM_NETWORK_INTERFACE:-tailscale0}. Stopping VM." >&2
			systemctl --user stop "$vm_scope_unit.service" >/dev/null 2>&1 || true
			return
		fi
	done
}

cleanup() {
	if [ -n "${network_guard_pid:-}" ]; then
		kill "$network_guard_pid" >/dev/null 2>&1 || true
	fi

	if mountpoint -q "$VM_FS_REAL_MOUNT_DIR"; then
		"$fuse_unmount" -u "$VM_FS_REAL_MOUNT_DIR" >/dev/null 2>&1 || true
	fi

	stop_vm
}
trap cleanup EXIT INT TERM
if [ "${VM_REQUIRE_TAILSCALE_EXIT:-1}" = "1" ]; then
	network_guard &
	network_guard_pid="$!"
fi

ssh_probe=(
	-o BatchMode=yes
	-o ConnectTimeout=1
	-o NumberOfPasswordPrompts=0
	-o IdentitiesOnly=yes
	-o StrictHostKeyChecking=accept-new
	-o UserKnownHostsFile="$known_hosts"
	-p "$port"
	-i "$key"
	"$user@127.0.0.1"
)

echo "Waiting for VM SSH on 127.0.0.1:$port ..."
attempts=0
while [ "$attempts" -lt "$ssh_timeout" ]; do
	attempts=$((attempts + 1))

	if ssh "${ssh_probe[@]}" true >/dev/null 2>&1; then
		echo "VM SSH is ready after $attempts seconds."
		break
	fi

	if ! kill -0 "$vm_pid" >/dev/null 2>&1; then
		echo "VM process exited before SSH became ready." >&2
		echo "Last QEMU log lines:" >&2
		safe_tail 80 >&2 || true
		exit 1
	fi

	if [ $((attempts % 30)) -eq 0 ]; then
		echo "Still waiting for VM SSH... $attempts seconds elapsed. Last QEMU log line:"
		safe_tail 1 || true
	fi

	if [ $((attempts % 60)) -eq 0 ]; then
		echo "SSH probe reason:"
		ssh "${ssh_probe[@]}" true 2>&1 | LC_ALL=C cat -v | sed -n '1,8p' || true
	fi

	sleep 1
done

if ! ssh "${ssh_probe[@]}" true >/dev/null 2>&1; then
	echo "Timed out waiting for VM SSH after $ssh_timeout seconds." >&2
	echo "Try this debug command in another terminal:" >&2
	echo "  ssh -vvv -p $port -i $key -o UserKnownHostsFile=$known_hosts $user@127.0.0.1 true" >&2
	echo "Last QEMU log lines:" >&2
	safe_tail 120 >&2 || true
	exit 1
fi

# Check store registrations before opening clients.
echo "Checking the guest Nix database after boot..."
ssh "${ssh_probe[@]}" 'sudo -n nix-store --verify'

if [ "${RESET_VSCODE_SERVER:-0}" = "1" ]; then
	echo "Resetting VS Code server directories inside the VM..."
	ssh "${ssh_probe[@]}" 'rm -rf ~/.vscode-server ~/.vscode-server-insiders ~/.vscode-remote'
fi

if [ "${OPEN_KITTY_SSH:-1}" = "1" ] && command -v kitty >/dev/null 2>&1; then
	echo "Opening kitty SSH session..."
	if [ -n "${KITTY_WINDOW_ID:-}" ]; then
		kitty @ launch --type=tab --tab-title "coding-vm" ssh "$host" 9>&- >/dev/null 2>&1 ||
			kitty --detach --title "coding-vm" ssh "$host" 9>&- >/dev/null 2>&1 ||
			true
	else
		kitty --detach --title "coding-vm" ssh "$host" 9>&- >/dev/null 2>&1 || true
	fi
fi

if [ "${MOUNT_SSHFS:-1}" = "1" ]; then
	if ! mountpoint -q "$VM_FS_REAL_MOUNT_DIR"; then
		echo "Mounting VM filesystem on host: $VM_FS_REAL_MOUNT_DIR"
		sshfs "$user@127.0.0.1:$VM_FS_REMOTE" "$VM_FS_REAL_MOUNT_DIR" \
			-o reconnect \
			-o ServerAliveInterval=15 \
			-o ServerAliveCountMax=3 \
			-o IdentityFile="$key" \
			-o port="$port" \
			-o StrictHostKeyChecking=accept-new \
			-o UserKnownHostsFile="$known_hosts"
	fi
fi
if [ "${OPEN_VSCODE:-1}" = "1" ]; then

	echo "Opening host VS Code and connecting to $host:$VM_FS_REMOTE ..."
	code --folder-uri "vscode-remote://ssh-remote+$host$VM_FS_REMOTE" 9>&- >/dev/null 2>&1 &
fi

echo "VM filesystem: $VM_FS_MOUNT_DIR"
echo "Press Ctrl-C to stop the VM."

wait "$vm_pid"
