#!/usr/bin/env bash
# OneShotLink guest flow using curl + python3 (no jq, no SDK).
# Usage: BASE_URL=http://127.0.0.1:3000 bash examples/curl/quickstart.sh
set -euo pipefail

BASE="${BASE_URL:-http://127.0.0.1:3000}"
BASE="${BASE%/}"
SECRET_VALUE="curl-example-$(date +%s)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Discover the operator's TTL allowlist instead of hard-coding a duration.
TTL=$(curl -fsS "$BASE/api/v3/config" | python3 -c 'import json,sys; print(json.load(sys.stdin)["default_ttl"])')
create=$(curl -fsS -X POST "$BASE/api/v3/guest/conceal" \
  -H 'content-type: application/json' \
  -d "{\"secret\":\"$SECRET_VALUE\",\"ttl\":$TTL}")
key=$(printf '%s' "$create" | python3 -c 'import json,sys; print(json.load(sys.stdin)["secret_key"])')
test -n "$key"

# GET is a preview: it must not return the plaintext or consume the record.
preview=$(curl -fsS "$BASE/api/v3/guest/secret/$key")
if printf '%s' "$preview" | grep -q "$SECRET_VALUE"; then
  echo "FAIL: preview leaked the secret" >&2; exit 1
fi

revealed=$(curl -fsS -X POST "$BASE/api/v3/guest/secret/$key/reveal" \
  -H 'content-type: application/json' -d '{}')
value=$(printf '%s' "$revealed" | python3 -c 'import json,sys; print(json.load(sys.stdin)["secret_value"])')
test "$value" = "$SECRET_VALUE"

again=$(curl -s -o "$work/second.json" -w '%{http_code}' -X POST \
  "$BASE/api/v3/guest/secret/$key/reveal" -H 'content-type: application/json' -d '{}')
test "$again" = "404"

printf 'ok: create=%s preview=no-content reveal=match replay=%s\n' "${key:0:8}" "$again"
