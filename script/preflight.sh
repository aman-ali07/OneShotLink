#!/usr/bin/env bash
# frozen_string_literal: true
#
# Go-live preflight for the host/infrastructure gates that the repository
# cannot close on its own: TLS termination (T-70) and Redis network isolation
# (T-71). Run this on the host, against the real public hostname, immediately
# before you call a deployment production-ready.
#
# Exits 0 only when every required check passes. Any failure exits non-zero.
#
# Usage:
#   HOST=https://secrets.example.com script/preflight.sh
#   HOST=https://secrets.example.com script/preflight.sh --cacert /path/ca.pem
#   HOST=https://secrets.example.com script/preflight.sh --skip-redis
#
# Environment:
#   HOST                     Public base URL, including scheme (required).
#   HTTP_URL                 Plain-HTTP URL for the redirect check. Defaults to
#                            HOST with the scheme swapped to http.
#   REDIS_NETWORK            Docker network to inspect. Default onetime-secret_backend.
#   REDIS_PORT               Redis port. Default 6379.
#   PREFLIGHT_ALLOW_SIGNUP   Set to 1 to create a throwaway account in order to
#                            inspect the session cookie flags. Otherwise that
#                            check is SKIPPED, not failed.
#
# Requires curl. Uses docker for the Redis checks when present.

set -uo pipefail

HOST="${HOST:-}"
HTTP_URL="${HTTP_URL:-}"
REDIS_NETWORK="${REDIS_NETWORK:-onetime-secret_backend}"
REDIS_PORT="${REDIS_PORT:-6379}"
PREFLIGHT_ALLOW_SIGNUP="${PREFLIGHT_ALLOW_SIGNUP:-0}"
CACERT=""
SKIP_REDIS=0
RESOLVE=()

failures=0
skips=0

pass() { printf '  \033[32m[PASS]\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m[FAIL]\033[0m %s\n' "$1"; failures=$((failures + 1)); }
warn() { printf '  \033[33m[WARN]\033[0m %s\n' "$1"; }
skip() { printf '  \033[90m[SKIP]\033[0m %s\n' "$1"; skips=$((skips + 1)); }
head_() { printf '\n== %s ==\n' "$1"; }

usage() {
  cat <<'EOF'
Go-live preflight for the host/infrastructure gates the repository cannot
close on its own: TLS termination (T-70) and Redis network isolation (T-71).
Exits 0 only when every required check passes.

Usage:
  HOST=https://secrets.example.com script/preflight.sh
  HOST=https://secrets.example.com script/preflight.sh --cacert /path/ca.pem
  HOST=https://secrets.example.com script/preflight.sh --skip-redis

Options:
  --cacert PATH    CA bundle to verify the TLS cert against (self-signed test CAs)
  --resolve H:P:IP Add a DNS override for curl (pre-DNS verification)
  --skip-redis     Skip the Redis isolation checks
  -h, --help       This help

Environment:
  HOST                   Public base URL, including scheme (required)
  HTTP_URL               Plain-HTTP URL for the redirect check (default: http://<host>)
  REDIS_NETWORK          Docker network with Redis (default onetime-secret_backend)
  REDIS_PORT             Redis port (default 6379)
  PREFLIGHT_ALLOW_SIGNUP=1  Create a throwaway account to inspect cookie flags
EOF
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --cacert) CACERT="${2:-}"; shift 2 ;;
    --resolve) RESOLVE+=("--resolve" "${2:-}"); shift 2 ;;
    --skip-redis) SKIP_REDIS=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

if [ -z "$HOST" ]; then
  echo "HOST is required, e.g. HOST=https://secrets.example.com $0" >&2
  exit 2
fi

case "$HOST" in
  *://*) : ;;
  *) echo "HOST must include a scheme, e.g. https://secrets.example.com" >&2; exit 2 ;;
esac

command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 2; }

HOST="${HOST%/}"
if [ -z "$HTTP_URL" ]; then
  HTTP_URL="http://${HOST#*://}"
fi
HTTP_URL="${HTTP_URL%/}"

curl_tls() {
  if [ -n "$CACERT" ]; then
    curl --cacert "$CACERT" ${RESOLVE[@]+"${RESOLVE[@]}"} "$@"
  else
    curl ${RESOLVE[@]+"${RESOLVE[@]}"} "$@"
  fi
}

curl_plain() {
  curl ${RESOLVE[@]+"${RESOLVE[@]}"} "$@"
}

# ---------------------------------------------------------------- TLS / T-70

head_ "TLS termination (T-70) — $HOST"

# 1. HTTPS serves and the certificate verifies against the system trust store.
out=$(curl_tls -sS -o /dev/null -w '%{http_code} %{ssl_verify_result}' \
          --max-time 15 "$HOST/health" 2>&1)
rc=$?
code=${out%% *}
verify=${out##* }
if [ "$rc" -ne 0 ]; then
  first_line=${out%%$"\n"*}
  case "$out" in
    *"SSL certificate problem"*)
      fail "certificate did not validate — $first_line. Wrong host, self-signed, or missing intermediate"
      ;;
    *)
      fail "could not reach $HOST/health: $first_line"
      ;;
  esac
elif [ "$code" = "200" ] && [ "$verify" = "0" ]; then
  pass "health over HTTPS is 200 and the certificate chain validates"
elif [ "$verify" != "0" ]; then
  fail "certificate did not validate (ssl_verify_result=$verify) — wrong host, self-signed, or missing intermediate"
else
  fail "expected 200 from $HOST/health, got $code"
fi

# 2. HSTS is present. It is only sent when SSL=true.
headers=$(curl_tls -sSI --max-time 15 "$HOST/" 2>/dev/null || true)
hsts=$(printf '%s' "$headers" | grep -i '^strict-transport-security:' | tr -d '\r' || true)
if [ -n "$hsts" ]; then
  case "$hsts" in
    *max-age=0*) fail "HSTS present but max-age=0 disables it: $hsts" ;;
    *) pass "HSTS present: ${hsts#*: }" ;;
  esac
else
  fail "no Strict-Transport-Security header — set SSL=true and ensure the proxy does not strip it"
fi

# 3. Hardening headers the app sends (a stripped header means proxy misconfig).
for h in x-content-type-options x-frame-options content-security-policy; do
  if printf '%s' "$headers" | grep -qi "^$h:"; then
    pass "header present: $h"
  else
    fail "missing header: $h (the proxy may be stripping app headers)"
  fi
done

# 4. Session cookie flags. Creating an account is a side effect, so it is opt-in.
auth_mode=$(curl_tls -sS --max-time 15 "$HOST/api/v3/config" 2>/dev/null \
  | sed -n 's/.*"auth_mode":"\([^"]*\)".*/\1/p')
if [ "$PREFLIGHT_ALLOW_SIGNUP" != "1" ]; then
  skip "session cookie flags (set PREFLIGHT_ALLOW_SIGNUP=1 to create a throwaway account)"
elif [ "$auth_mode" != "simple" ]; then
  skip "session cookie flags (auth_mode=${auth_mode:-unknown}; signup unavailable)"
else
  email="preflight-$(date +%s)-$$@example.invalid"
  cookie=$(curl_tls -sS -D- -o /dev/null --max-time 15 -X POST "$HOST/api/v3/signup" \
    -H 'content-type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"preflight-only-password-9x\"}" 2>/dev/null \
    | grep -i '^set-cookie:' | tr -d '\r' || true)
  if [ -z "$cookie" ]; then
    fail "signup did not set a session cookie (cannot verify Secure/HttpOnly/SameSite)"
  else
    missing=""
    printf '%s' "$cookie" | grep -qi 'secure' || missing="$missing Secure"
    printf '%s' "$cookie" | grep -qi 'httponly' || missing="$missing HttpOnly"
    printf '%s' "$cookie" | grep -qi 'samesite' || missing="$missing SameSite"
    if [ -z "$missing" ]; then
      pass "session cookie is Secure + HttpOnly + SameSite"
    else
      fail "session cookie missing:$missing"
    fi
  fi
fi

# 5. Plain HTTP redirects to HTTPS (the proxy terminates, not the app).
redir=$(curl_plain -sS -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 15 "$HTTP_URL/" 2>/dev/null || true)
rcode=${redir%% *}
rurl=${redir#* }
case "$rcode" in
  301|302|307|308)
    case "$rurl" in
      https://*) pass "plain HTTP redirects to HTTPS ($rcode)" ;;
      *) fail "plain HTTP redirects to a non-HTTPS URL: $rurl" ;;
    esac
    ;;
  200)
    fail "$HTTP_URL serves 200 over plain HTTP — traffic is not forced to TLS"
    ;;
  *)
    fail "plain HTTP check returned '$rcode' (expected a 301/308 redirect to https)"
    ;;
esac

# ------------------------------------------------------------ Redis / T-71

head_ "Redis isolation (T-71)"

if [ "$SKIP_REDIS" = "1" ]; then
  skip "Redis network checks skipped by request"
elif ! command -v docker >/dev/null 2>&1; then
  skip "docker not available; cannot inspect the Redis network"
else
  subnet=$(docker network inspect "$REDIS_NETWORK" \
    --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || true)

  if [ -z "$subnet" ]; then
    warn "network '$REDIS_NETWORK' not found — is the stack running under this project name?"
  else
    # The network must be internal: no gateway, so no egress from Redis.
    is_internal=$(docker network inspect "$REDIS_NETWORK" --format '{{.Internal}}' 2>/dev/null || echo false)
    if [ "$is_internal" = "true" ]; then
      pass "network '$REDIS_NETWORK' is internal (Redis has no egress)"
    else
      fail "network '$REDIS_NETWORK' is not internal — Redis can reach the internet"
    fi

    redis_cidr=$(docker network inspect "$REDIS_NETWORK" \
      --format '{{range .Containers}}{{println .Name .IPv4Address}}{{end}}' 2>/dev/null \
      | grep -i redis | head -1 \
      | grep -o '[0-9.]\{7,\}/[0-9]\{1,2\}' || true)

    if [ -n "$redis_cidr" ]; then
      ip=${redis_cidr%%/*}
      # A host process must NOT be able to open the Redis port. If it can, the
      # firewall/network-policy rule from DEPLOYMENT 4.0 has not been applied.
      if timeout 5 bash -c "exec 3<>/dev/tcp/$ip/$REDIS_PORT" 2>/dev/null; then
        fail "host can reach Redis at $ip:$REDIS_PORT — apply the DEPLOYMENT 4.0 firewall rule"
      else
        pass "host cannot reach Redis at $ip:$REDIS_PORT (firewall rule in effect)"
      fi
    else
      warn "no Redis container found on '$REDIS_NETWORK'; skipping reachability probe"
    fi
  fi
fi

# -------------------------------------------------------------------- result

printf '\n== Result ==\n'
if [ "$failures" -eq 0 ]; then
  printf '  \033[32mPREFLIGHT PASSED\033[0m (%d skipped)\n' "$skips"
  exit 0
fi

printf '  \033[31mPREFLIGHT FAILED: %d check(s)\033[0m (%d skipped)\n' "$failures" "$skips"
exit 1
