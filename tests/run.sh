#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

ok() {
	printf 'OK: %s\n' "$*"
}

extract_ssh_cleanup_awk() {
	awk '
    BEGIN { sq = sprintf("%c", 39) }
    $0 ~ "^[[:space:]]*awk " sq "[[:space:]]*$" {
      capture = 1
      next
    }
    capture && $0 ~ "^[[:space:]]*" sq "[[:space:]]*\"\\$ssh_config\"[[:space:]]*>[[:space:]]*\"\\$tmp_config\"[[:space:]]*$" {
      exit
    }
    capture {
      sub(/^          /, "")
      print
    }
  ' scripts/run-vm.sh
}

test_ssh_cleanup_removes_all_vm_blocks() {
	local program
	local input
	local output

	program="$(extract_ssh_cleanup_awk)"
	[ -n "$program" ] || fail "could not extract SSH cleanup AWK from scripts/run-vm.sh"

	input="$(mktemp)"
	output="$(mktemp)"
	trap 'rm -f "$input" "$output"' RETURN

	cat >"$input" <<'EOF'
Host keep-before
  HostName before.example

# BEGIN coding-vm managed block
Host coding-vm
  HostName 127.0.0.1
  Port 2222
# END coding-vm managed block

# BEGIN coding-vm managed
Host coding-vm
  HostName 127.0.0.1
  Port 2222
# END coding-vm managed

Host coding-vm
  HostName 127.0.0.1
  Port 2222

Host coding-vm-iso coding-vm
  HostName 127.0.0.1
  Port 2222

Host maybe-localhost
  Port 2222

Host us-proxy-vm
  Port 2222

Host keep-after
  HostName after.example
EOF

	awk "$program" "$input" >"$output"

	! grep -Eq 'coding-vm|BEGIN coding-vm|END coding-vm' "$output" ||
		fail "SSH cleanup left generated VM config behind"
	grep -q '^Host keep-before$' "$output" || fail "SSH cleanup removed preceding user config"
	grep -q '^Host keep-after$' "$output" || fail "SSH cleanup removed following user config"

	grep -q "^Host maybe-localhost$" "$output" || fail "removed original VM alias"
	grep -q "^Host us-proxy-vm$" "$output" || fail "removed original VM alias"
	ok "SSH cleanup removes generated and legacy VM blocks"
}

test_exit_node_networking() {
	local ipv6_enabled tailscale_enabled qemu_networking
	ipv6_enabled="$(nix eval --json path:.#nixosConfigurations.coding-vm.config.networking.enableIPv6)"
	tailscale_enabled="$(nix eval --json path:.#nixosConfigurations.coding-vm.config.services.tailscale.enable)"
	qemu_networking="$(nix eval --json path:.#nixosConfigurations.coding-vm.config.virtualisation.qemu.networkingOptions)"

	[ "$ipv6_enabled" = true ] || fail "IPv6 must be enabled"
	[ "$tailscale_enabled" = false ] || fail "only the host runs Tailscale"
	for option in 'netdev passt,id=host0' 'outbound-if4=tailscale0' 'outbound-if6=tailscale0' '--address=fd00:2::15' '--dns=1.1.1.1' '--no-map-gw'; do
		grep -Fq -- "$option" <<<"$qemu_networking" || fail "missing network option: $option"
	done
	! grep -Fq 'disable_ipv6' hosts/coding-vm.nix || fail "IPv6 sysctl override remains"
	ok "IPv4 and IPv6 use passt sockets bound to Tailscale"
}

test_ssh_cleanup_removes_all_vm_blocks
test_exit_node_networking
bash tests/disk-preallocation.sh

[ "$(nix eval --impure --json --file tests/spoof-settings.nix)" = true ] || fail "spoof switch configuration"
ok "spoof switch selects region and network settings"
bash tests/spoof-preflight.sh
