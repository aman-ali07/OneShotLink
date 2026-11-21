#!/usr/bin/env bash
# Advanced OneShotLink flow: passphrase gate, file secret, and owner burn.
# Uses only curl + python3 (JSON parsing), a cookie jar and a same-origin Origin
# header for authenticated mutations. No secret material is logged.
# Usage: BASE_URL=http://127.0.0.1:3000 bash examples/curl/advanced.sh
set -euo pipefail

BASE="${BASE_URL:-http://127.0.0.1:3000}"
BASE="${BASE%/}"
ORIGIN="$BASE"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
jar="$WORK/cookies.txt"
stamp=$(date +%s)

post_json() { curl -fsS -X POST "$1" -H 'content-type: application/json' -H "Origin: $ORIGIN" "${@:2}"; }

# An account is required for the owner-only burn route (AUTH_MODE=simple).
post_json "$BASE/api/v3/signup" -c "$jar" \
  -d "{\"email\":\"advanced-$stamp@example.com\",\"password\":\"advanced-example-password-$stamp\"}" >/dev/null

# 1. Passphrase gate: preview is metadata-only; a wrong guess must not consume.
guarded="advanced-pass-$stamp"
created=$(curl -fsS -b "$jar" -X POST "$BASE/api/v3/guest/conceal" \
  -H 'content-type: application/json' -H "Origin: $ORIGIN" \
  -d "{\"secret\":\"$guarded\",\"ttl\":1800,\"passphrase\":\"correct-horse\"}")
key=$(printf '%s' "$created" | python3 -c 'import json,sys;print(json.load(sys.stdin)["secret_key"])')

preview=$(curl -fsS "$BASE/api/v3/guest/secret/$key")
test "$(printf '%s' "$preview" | python3 -c 'import json,sys;print(str(json.load(sys.stdin)["passphrase_required"]).lower())')" = true
wrong=$(curl -s -o "$WORK/wrong.json" -w '%{http_code}' -X POST \
  "$BASE/api/v3/guest/secret/$key/reveal" -H 'content-type: application/json' -d '{"passphrase":"wrong"}')
test "$wrong" = 401
test "$(python3 -c 'import json;print(json.load(open("'$WORK'/wrong.json"))["error"]["code"])')" = invalid_passphrase
right=$(curl -fsS -X POST "$BASE/api/v3/guest/secret/$key/reveal" \
  -H 'content-type: application/json' -d '{"passphrase":"correct-horse"}' \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["secret_value"])')
test "$right" = "$guarded"

# 2. File secret: strict base64 in, base64 + filename out, exactly once.
payload_b64='AAH+/0FCQg=='
file_created=$(curl -fsS -X POST "$BASE/api/v3/guest/conceal" \
  -H 'content-type: application/json' \
  -d "{\"kind\":\"file\",\"filename\":\"fixture.bin\",\"secret\":\"$payload_b64\",\"ttl\":1800}")
file_key=$(printf '%s' "$file_created" | python3 -c 'import json,sys;print(json.load(sys.stdin)["secret_key"])')
file_result=$(curl -fsS -X POST "$BASE/api/v3/guest/secret/$file_key/reveal" \
  -H 'content-type: application/json' -d '{}')
test "$(printf '%s' "$file_result" | python3 -c 'import json,sys;print(json.load(sys.stdin)["secret_value"])')" = "$payload_b64"
test "$(printf '%s' "$file_result" | python3 -c 'import json,sys;print(json.load(sys.stdin)["metadata"]["filename"])')" = fixture.bin

# 3. Owner burn: session cookie + same-origin proof, no plaintext returned.
burn_created=$(curl -fsS -b "$jar" -X POST "$BASE/api/v3/secret/conceal" \
  -H 'content-type: application/json' -H "Origin: $ORIGIN" \
  -d '{"secret":"advanced-burn-payload","ttl":1800}')
burn_key=$(printf '%s' "$burn_created" | python3 -c 'import json,sys;print(json.load(sys.stdin)["secret_key"])')
burned=$(curl -fsS -b "$jar" -X DELETE "$BASE/api/v3/secret/$burn_key" \
  -H 'content-type: application/json' -H "Origin: $ORIGIN" -d '{}')
test "$(printf '%s' "$burned" | python3 -c 'import json,sys;print(json.load(sys.stdin)["metadata"]["status"])')" = burned
gone=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  "$BASE/api/v3/guest/secret/$burn_key/reveal" -H 'content-type: application/json' -d '{}')
test "$gone" = 404

printf 'ok: passphrase=%s wrong=%s right=%s file=%s burn=%s replay=%s\n' \
  "${key:0:8}" "$wrong" "${right:0:8}" "${file_key:0:8}" burned "$gone"
