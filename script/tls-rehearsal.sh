#!/usr/bin/env bash
# frozen_string_literal: true
#
# Rehearse the TLS go-live checklist (T-70) without owning a domain.
#
# Boots the production Compose stack behind a real TLS terminator (Caddy) using
# a throwaway local CA, then runs script/preflight.sh against it with the
# certificate verified. This proves the app side of the TLS gate end to end:
# HSTS under SSL=true, hardening headers surviving the proxy, Secure/HttpOnly/
# SameSite cookies, and the plain-HTTP redirect.
#
# It is NOT a substitute for running the same gate on the operator's host: a
# local CA and a hosts-free --resolve cannot prove DNS, a real certificate
# chain, or the Redis firewall rule (T-71). Use --with-redis to include the
# Redis isolation checks against the rehearsal stack.
#
# Usage:
#   script/tls-rehearsal.sh                # TLS checks only
#   script/tls-rehearsal.sh --with-redis   # TLS + Redis network isolation
#   APP_PORT=13457 HTTPS_PORT=18443 HTTP_PORT=18088 script/tls-rehearsal.sh
#
# Requires: docker, openssl, curl. Leaves nothing behind (stack, CA and proxy
# container are removed on exit).

set -uo pipefail

APP_PORT="${APP_PORT:-13457}"
HTTPS_PORT="${HTTPS_PORT:-18443}"
HTTP_PORT="${HTTP_PORT:-18088}"
DOMAIN="${DOMAIN:-secrets.localtest}"
PROJECT="${PROJECT:-otstls-rehearsal}"
PROXY_NAME="${PROXY_NAME:-otstls-caddy}"
WITH_REDIS=0

for arg in "$@"; do
  case "$arg" in
    --with-redis) WITH_REDIS=1 ;;
    -h|--help) sed -n '3,30p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

for bin in docker openssl curl; do
  command -v "$bin" >/dev/null 2>&1 || { echo "$bin is required" >&2; exit 2; }
done

work=$(mktemp -d)
cleanup() {
  docker rm -f "$PROXY_NAME" >/dev/null 2>&1 || true
  SECRET=unused REDIS_PASSWORD=unused APP_PORT="$APP_PORT" \
    docker compose -p "$PROJECT" down -v >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT INT TERM

echo "== local CA and certificate =="
openssl req -x509 -newkey rsa:2048 -sha256 -days 2 -nodes \
  -keyout "$work/ca.key" -out "$work/ca.crt" -subj "/CN=OneShotLink Rehearsal CA" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -keyout "$work/srv.key" -out "$work/srv.csr" \
  -subj "/CN=$DOMAIN" 2>/dev/null
printf 'subjectAltName=DNS:%s\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n' \
  "$DOMAIN" > "$work/ext.cnf"
openssl x509 -req -in "$work/srv.csr" -CA "$work/ca.crt" -CAkey "$work/ca.key" \
  -CAcreateserial -days 2 -sha256 -extfile "$work/ext.cnf" -out "$work/srv.crt" 2>/dev/null
chmod 644 "$work/srv.key" "$work/srv.crt" "$work/ca.crt"
echo "   issued $DOMAIN from a throwaway CA"

cat > "$work/Caddyfile" <<EOF
{
	auto_https disable_redirects
}
http://$DOMAIN:$HTTP_PORT {
	redir https://$DOMAIN:$HTTPS_PORT{uri} permanent
}
https://$DOMAIN:$HTTPS_PORT {
	tls /certs/srv.crt /certs/srv.key
	encode zstd gzip
	reverse_proxy 127.0.0.1:$APP_PORT
}
EOF

echo "== boot the production stack (SSL=true, HOST=$DOMAIN:$HTTPS_PORT) =="
secret=$(openssl rand -hex 32)
redis_password=$(openssl rand -hex 24)
if ! SECRET="$secret" REDIS_PASSWORD="$redis_password" AUTH_MODE=simple \
     APP_PORT="$APP_PORT" SSL=true HOST="$DOMAIN:$HTTPS_PORT" TRUSTED_PROXIES=127.0.0.1 \
     docker compose -p "$PROJECT" up -d --wait >"$work/compose.log" 2>&1; then
  echo "compose failed to come up:" >&2
  tail -20 "$work/compose.log" >&2
  exit 1
fi

echo "== start the TLS terminator =="
if ! docker run -d --name "$PROXY_NAME" --network host \
     -v "$work:/certs:ro" -v "$work/Caddyfile:/etc/caddy/Caddyfile:ro" \
     caddy:2-alpine >/dev/null 2>"$work/proxy.log"; then
  echo "could not start the terminator:" >&2
  cat "$work/proxy.log" >&2
  exit 1
fi

# Wait for the proxy to answer before handing over to the real gate.
ready=0
for _ in $(seq 1 30); do
  if curl -s --cacert "$work/ca.crt" --resolve "$DOMAIN:$HTTPS_PORT:127.0.0.1" \
       --max-time 3 "https://$DOMAIN:$HTTPS_PORT/health" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
if [ "$ready" != "1" ]; then
  echo "the terminator never answered over HTTPS:" >&2
  docker logs "$PROXY_NAME" 2>&1 | tail -20 >&2
  exit 1
fi
echo "   HTTPS is answering"

echo
if [ "$WITH_REDIS" = "1" ]; then
  HOST="https://$DOMAIN:$HTTPS_PORT" HTTP_URL="http://$DOMAIN:$HTTP_PORT" \
  PREFLIGHT_ALLOW_SIGNUP=1 REDIS_NETWORK="${PROJECT}_backend" \
  script/preflight.sh --cacert "$work/ca.crt" \
    --resolve "$DOMAIN:$HTTPS_PORT:127.0.0.1" --resolve "$DOMAIN:$HTTP_PORT:127.0.0.1"
else
  HOST="https://$DOMAIN:$HTTPS_PORT" HTTP_URL="http://$DOMAIN:$HTTP_PORT" \
  PREFLIGHT_ALLOW_SIGNUP=1 \
  script/preflight.sh --skip-redis --cacert "$work/ca.crt" \
    --resolve "$DOMAIN:$HTTPS_PORT:127.0.0.1" --resolve "$DOMAIN:$HTTP_PORT:127.0.0.1"
fi
status=$?

if [ "$status" -eq 0 ]; then
  echo
  echo "Rehearsal passed: the app side of the TLS gate holds behind a real terminator."
  echo "Still the operator's to prove on the real hostname: DNS, the real certificate"
  echo "chain, and the Redis host firewall rule (T-71)."
fi
exit "$status"
