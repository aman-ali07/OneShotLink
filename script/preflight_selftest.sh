#!/usr/bin/env bash
# frozen_string_literal: true
#
# Self-test for script/preflight.sh.
#
# Stands up this project behind a real TLS terminator with a throwaway CA, then
# asserts that preflight PASSES on a good configuration and FAILS on each bad
# one. This exists so the go-live gate cannot silently rot into a check that
# always prints PASS.
#
# Usage: script/preflight_selftest.sh
# Requires docker with compose. Leaves no containers, networks or volumes behind.
#
# Ports are overridable: PF_HTTPS_PORT (9443), PF_HTTP_PORT (9080).

set -uo pipefail

cd "$(dirname "$0")/.." || exit 2
ROOT="$PWD"

HTTPS_PORT="${PF_HTTPS_PORT:-9443}"
HTTP_PORT="${PF_HTTP_PORT:-9080}"
DOMAIN="preflight.selftest.invalid"
NET="onetime-secret_frontend"
CADDY="preflight-selftest-caddy"
WORK="$(mktemp -d)"

failures=0
checks=0

ok()   { printf '  \033[32m[PASS]\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m[FAIL]\033[0m %s\n' "$1"; failures=$((failures + 1)); }
info() { printf '\n== %s ==\n' "$1"; }

cleanup() {
  docker rm -f "$CADDY" >/dev/null 2>&1
  SECRET=x REDIS_PASSWORD=y docker compose down -v --remove-orphans >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 2; }
command -v openssl >/dev/null 2>&1 || { echo "openssl is required" >&2; exit 2; }

# --- throwaway cert -----------------------------------------------------------
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -subj "/CN=$DOMAIN" -addext "subjectAltName=DNS:$DOMAIN" >/dev/null 2>&1 \
  || { echo "could not generate a test certificate" >&2; exit 2; }

cat > "$WORK/Caddyfile" <<EOF
{
	admin off
	auto_https off
}
https://$DOMAIN:$HTTPS_PORT {
	tls /etc/caddy/cert.pem /etc/caddy/key.pem
	reverse_proxy web:3000
}
http://$DOMAIN:$HTTP_PORT {
	redir https://$DOMAIN:$HTTPS_PORT{uri} permanent
}
EOF

# --- bring the stack up -------------------------------------------------------
info "starting the stack"
export SECRET="${SECRET:-$(openssl rand -hex 32)}"
export REDIS_PASSWORD="${REDIS_PASSWORD:-$(openssl rand -hex 24)}"
export APP_PORT=3000 HOST="$DOMAIN" SSL=true AUTH_MODE=simple
export TRUST_PROXY=true TRUSTED_PROXIES=172.16.0.0/12

docker compose up -d >/dev/null 2>&1 || { echo "compose up failed" >&2; exit 1; }

healthy=0
for _ in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:3000/health >/dev/null 2>&1; then healthy=1; break; fi
  sleep 2
done
[ "$healthy" = "1" ] || { echo "stack never became healthy" >&2; exit 1; }

docker rm -f "$CADDY" >/dev/null 2>&1
docker run -d --name "$CADDY" --network "$NET" \
  -p "127.0.0.1:$HTTPS_PORT:$HTTPS_PORT" -p "127.0.0.1:$HTTP_PORT:$HTTP_PORT" \
  -v "$WORK/Caddyfile:/etc/caddy/Caddyfile:ro" \
  -v "$WORK/cert.pem:/etc/caddy/cert.pem:ro" \
  -v "$WORK/key.pem:/etc/caddy/key.pem:ro" \
  caddy:2-alpine >/dev/null 2>&1 || { echo "caddy failed to start" >&2; exit 1; }

for _ in $(seq 1 30); do
  if curl --resolve "$DOMAIN:$HTTPS_PORT:127.0.0.1" --cacert "$WORK/cert.pem" \
       -fsS "https://$DOMAIN:$HTTPS_PORT/health" >/dev/null 2>&1; then break; fi
  sleep 1
done

# --- helpers ------------------------------------------------------------------
define_preflight() { # define_preflight <extra args...>; prints output, returns rc
  local out rc
  out=$(HOST="https://$DOMAIN:$HTTPS_PORT" HTTP_URL="http://$DOMAIN:$HTTP_PORT" \
    PREFLIGHT_ALLOW_SIGNUP=1 "$ROOT/script/preflight.sh" \
    --cacert "$WORK/cert.pem" \
    --resolve "$DOMAIN:$HTTPS_PORT:127.0.0.1" \
    --resolve "$DOMAIN:$HTTP_PORT:127.0.0.1" "$@" 2>&1) && rc=0 || rc=$?
  printf '%s\n' "$out"
  return $rc
}

expect() { # expect <wanted: pass|fail> <label> <cmd...>
  local want="$1" label="$2"; shift 2
  checks=$((checks + 1))
  local out rc
  out=$("$@" 2>&1) && rc=0 || rc=$?
  if [ "$want" = "pass" ] && [ "$rc" -eq 0 ]; then
    ok "$label (exit 0)"
  elif [ "$want" = "fail" ] && [ "$rc" -ne 0 ]; then
    ok "$label (exit non-zero)"
  else
    bad "$label: wanted $want, got exit $rc"
    printf '%s\n' "$out" | sed 's/^/      /'
  fi
}

# --- cases --------------------------------------------------------------------
# The Redis reachability check is skipped in these cases: this host can reach the
# container IP, so asserting it here would only test the machine's firewall.
info "case: healthy config must PASS"
check_good() { define_preflight --skip-redis >/dev/null; }
expect pass "TLS, headers, cookie and redirect all green" check_good

info "case: untrusted certificate must FAIL"
check_bad_cert() {
  HOST="https://$DOMAIN:$HTTPS_PORT" "$ROOT/script/preflight.sh" \
    --resolve "$DOMAIN:$HTTPS_PORT:127.0.0.1" --skip-redis >/dev/null 2>&1
}
expect fail "self-signed cert without --cacert is rejected" check_bad_cert

info "case: plain HTTP serving 200 must FAIL the redirect check"
check_no_redirect() {
  HOST="https://$DOMAIN:$HTTPS_PORT" HTTP_URL="http://127.0.0.1:3000" \
    "$ROOT/script/preflight.sh" --cacert "$WORK/cert.pem" \
    --resolve "$DOMAIN:$HTTPS_PORT:127.0.0.1" --skip-redis >/dev/null 2>&1
}
expect fail "a plain-HTTP 200 is not accepted" check_no_redirect

info "case: reachable Redis must FAIL the isolation check"
check_reachable_redis() {
  define_preflight >/dev/null   # no --skip-redis
}
expect fail "a host-reachable redis:6379 fails the gate" check_reachable_redis

info "case: missing HOST must exit 2"
check_no_host() { "$ROOT/script/preflight.sh" >/dev/null 2>&1; }
expect fail "invoked without HOST" check_no_host

# --- summary ------------------------------------------------------------------
printf '\n== Result ==\n'
if [ "$failures" -eq 0 ]; then
  printf '  \033[32mPREFLIGHT SELFTEST PASSED\033[0m (%d assertions)\n' "$checks"
  exit 0
fi
printf '  \033[31mPREFLIGHT SELFTEST FAILED: %d of %d\033[0m\n' "$failures" "$checks"
exit 1
