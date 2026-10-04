#!/usr/bin/env bash
set -euo pipefail

# Check the running VM against the host's Tailscale exit for both protocols.
SSH_HOST="${SSH_HOST:-coding-vm}"
TIMEOUT="${TIMEOUT:-15}"

for destination in 1.1.1.1 2606:4700:4700::1111; do
	ip route get "$destination" | grep -qw tailscale0 || {
		echo "FAIL: host route to $destination does not use Tailscale" >&2
		exit 1
	}
done

ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_HOST" 'ip -j address' | python3 -c '
import ipaddress, json, sys
prefix = ipaddress.ip_network("fd00:2::/64")
for interface in json.load(sys.stdin):
    for info in interface.get("addr_info", []):
        if info["family"] != "inet6":
            continue
        address = ipaddress.ip_address(info["local"])
        if not (address.is_loopback or address.is_link_local or address in prefix):
            sys.exit("FAIL: guest has an unexpected IPv6 address")
print("OK: guest IPv6 addresses are private")
'

for family in 4 6; do
	if [ "$family" = 4 ]; then
		url=https://ipv4.icanhazip.com
	else
		url=https://ipv6.icanhazip.com
	fi
	host_ip="$(curl --noproxy '*' --interface tailscale0 -"$family" -fsS \
		--connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" "$url")"
	guest_ip="$(ssh -o BatchMode=yes "$SSH_HOST" \
		"curl --noproxy '*' -$family -fsS --connect-timeout $TIMEOUT --max-time $TIMEOUT $url")"
	[ "$guest_ip" = "$host_ip" ] || {
		echo "FAIL: guest IPv$family exit differs from the host Tailscale exit" >&2
		exit 1
	}
	echo "OK: IPv$family exit matches Tailscale: $guest_ip"
done

ssh -o BatchMode=yes "$SSH_HOST" 'set -e
v4="$(dig +time=5 +tries=1 +short @1.1.1.1 example.com A)"
v6="$(dig -6 +time=5 +tries=1 +short @2606:4700:4700::1111 example.com AAAA)"
test -n "$v4"
test -n "$v6"
printf "OK: IPv4 and IPv6 DNS replies received\n"'

echo "OK: dual-stack exit checks passed"
