#!/usr/bin/env bash
# Zero-cost host firewall helper for OneShotLink (T-70 / T-71).
#
# Uses only what the host already ships (nftables or ufw). No paid service,
# no managed firewall, no agent. DRY RUN BY DEFAULT: it prints the exact rules
# and never changes the host unless --apply is passed explicitly.
#
# Inbound policy: loopback + established, HTTP/HTTPS from anywhere, SSH only
# from ADMIN_CIDR, everything else dropped. Outbound: deny the fixed Redis
# backend subnet on 6379 so a host process cannot reach the datastore.
#
# Usage:
#   ADMIN_CIDR=203.0.113.7/32 script/host-firewall.sh            # dry run
#   sudo ADMIN_CIDR=203.0.113.7/32 script/host-firewall.sh --apply
#   REDIS_SUBNET=10.77.13.0/24 script/host-firewall.sh --verify
#
# Refuses to run without an explicit ADMIN_CIDR: never open SSH to the world.

set -euo pipefail

ADMIN_CIDR="${ADMIN_CIDR:-}"
REDIS_SUBNET="${REDIS_SUBNET:-10.77.13.0/24}"
APPLY=0
VERIFY=0

for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --verify) VERIFY=1 ;;
    --help|-h) sed -n '1,24p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if [[ -z "$ADMIN_CIDR" ]]; then
  echo "ADMIN_CIDR is required (e.g. ADMIN_CIDR=203.0.113.7/32)." >&2
  echo "Refusing to generate a rule that exposes SSH to every address." >&2
  exit 2
fi

# These values reach a root shell. Reject anything that is not an IP network
# before generating or applying rules; parsing here also stops regex/command
# metacharacters from reaching the ufw/nft invocations below.
valid_network() {
  python3 -c 'import ipaddress,sys; ipaddress.ip_network(sys.argv[1], strict=False)' "$1" >/dev/null 2>&1
}
for value_name in ADMIN_CIDR REDIS_SUBNET; do
  value="${!value_name}"
  if ! valid_network "$value"; then
    echo "$value_name must be a valid IP network (e.g. 203.0.113.7/32)." >&2
    exit 2
  fi
done

detect() {
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    echo ufw
  elif command -v nft >/dev/null 2>&1 && nft list tables 2>/dev/null | grep -q 'inet'; then
    echo nft
  else
    echo none
  fi
}

# FIREWALL overrides detection so rules can be previewed on a machine that
# does not run a firewall yet (e.g. a fresh host before provisioning).
FW="${FIREWALL:-$(detect)}"
echo "detected firewall: $FW"
echo "admin CIDR: $ADMIN_CIDR"
echo "redis subnet: $REDIS_SUBNET"

if [[ "$VERIFY" -eq 1 ]]; then
  echo "-- verification commands (run as the host owner) --"
  echo "ufw status numbered | grep -E '80|443|22|${REDIS_SUBNET}' || true"
  echo "nft list ruleset | grep -E '${REDIS_SUBNET}|dport 6379' || true"
  echo "curl -fsS https://<your-domain>/health   # must return 200 with a valid chain"
  echo "nc -z -w2 <redis-container-ip> 6379      # must fail from the host"
  exit 0
fi

apply_ufw() {
  printf '%s\n' \
    "ufw default deny incoming" \
    "ufw allow from $ADMIN_CIDR to any port 22 proto tcp" \
    "ufw allow 80/tcp" \
    "ufw allow 443/tcp" \
    "ufw deny out to $REDIS_SUBNET port 6379 proto tcp" \
    "ufw --force enable"
  if [[ "$APPLY" -eq 1 ]]; then
    [[ "$(id -u)" -eq 0 ]] || { echo "run with sudo to apply" >&2; exit 2; }
    # Generated rules are passed as single quoted arguments, never re-parsed.
    ufw default deny incoming
    ufw allow from "$ADMIN_CIDR" to any port 22 proto tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw deny out to "$REDIS_SUBNET" port 6379 proto tcp
    ufw --force enable
    echo "applied. 'ufw status numbered' to confirm."
  fi
}

apply_nft() {
  cat <<EOF
nft add table inet ots
nft add chain inet ots in '{ type filter hook input priority 0 ; policy drop ; }'
nft add rule inet ots in ct state established,related accept
nft add rule inet ots in iif lo accept
nft add rule inet ots in tcp dport 22 ip saddr $ADMIN_CIDR accept
nft add rule inet ots in tcp dport { 80, 443 } accept
nft add chain inet ots out '{ type filter hook output priority 0 ; policy accept ; }'
nft add rule inet ots out ip daddr $REDIS_SUBNET tcp dport 6379 drop
EOF
  if [[ "$APPLY" -eq 1 ]]; then
    [[ "$(id -u)" -eq 0 ]] || { echo "run with sudo to apply" >&2; exit 2; }
    nft add table inet ots
    nft add chain inet ots in '{ type filter hook input priority 0 ; policy drop ; }'
    nft add rule inet ots in ct state established,related accept
    nft add rule inet ots in iif lo accept
    nft add rule inet ots in tcp dport 22 ip saddr "$ADMIN_CIDR" accept
    nft add rule inet ots in tcp dport '{ 80, 443 }' accept
    nft add chain inet ots out '{ type filter hook output priority 0 ; policy accept ; }'
    nft add rule inet ots out ip daddr "$REDIS_SUBNET" tcp dport 6379 drop
    nft list ruleset > /etc/nftables.conf
    echo "applied and persisted to /etc/nftables.conf. Verify before logging out."
  fi
}

if [[ "$FW" == "ufw" ]]; then apply_ufw
elif [[ "$FW" == "nft" ]]; then apply_nft
else
  echo "No active ufw/nftables detected; nothing to do. Install one from the host package manager (free)." >&2
  exit 1
fi

if [[ "$APPLY" -eq 0 ]]; then
  echo "-- dry run only; re-run with --apply as root to change the host --"
fi
