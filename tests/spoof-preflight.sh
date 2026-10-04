#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
sed '/^project_root=/,$d' scripts/run-vm.sh >"$work/preflight.sh"
cat >"$work/tailscale" <<'MOCK'
#!/usr/bin/env bash
printf 'unexpected Tailscale check\n' >&2
exit 1
MOCK
chmod +x "$work/tailscale"
PATH="$work:$PATH" VM_REQUIRE_TAILSCALE_EXIT=0 bash "$work/preflight.sh"
if PATH="$work:$PATH" VM_TAILSCALE_BIN="$work/tailscale" VM_REQUIRE_TAILSCALE_EXIT=1 bash "$work/preflight.sh" >/dev/null 2>&1; then
	echo "FAIL: spoof mode accepted an unavailable exit node" >&2
	exit 1
fi
echo "OK: spoof switch controls launcher Tailscale preflight"
