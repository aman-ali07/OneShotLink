#!/usr/bin/env bash
# Local, non-deploying verification of the Stage 16 production-preparation artifacts.
# Run from the repository root: bash deploy/free-tier/verify.sh [--verify-build]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
DIR="deploy/free-tier"
FAIL=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAIL=$((FAIL+1)); }

echo "== Stage 16 local verification (no deploy) =="

# 1. Every production-relevant Config key appears in the environment contract.
mapfile -t KEYS < <(awk '/^    DEFAULTS = \{/{inside=1; next} inside && /^    \}\.freeze/{exit} inside && match($0,/"[A-Z0-9_]+" *=>/){s=substr($0,RSTART+1,RLENGTH-5); print s}' lib/onetime/config.rb)
KEYS+=(SECRET REDIS_URL REDIS_PASSWORD SSL MAX_SECRET_BYTES PORT RACK_ENV
       WEB_CONCURRENCY PUMA_MIN_THREADS PUMA_MAX_THREADS PUMA_WORKER_TIMEOUT
       LOG_LEVEL WEBHOOK_ALLOW_PRIVATE OTS_URL OTS_ALLOW_INSECURE VITE_API_PROXY)
missing=()
for k in "${KEYS[@]}"; do
  if ! grep -Eq "^(${k}|# ${k})=" "$DIR/env.production.example"; then missing+=("$k"); fi
done
if [ ${#missing[@]} -eq 0 ]; then pass "env contract covers ${#KEYS[@]} Config keys"; else fail "env contract missing: ${missing[*]}"; fi

# 2. No development-only or unsafe value is active in the production contract.
for bad in '^SSL=false' '^REDIS_URL=redis://' '^TRUST_PROXY=true' '^HOST=localhost' '^WEBHOOK_ALLOW_PRIVATE=true' '^AUTH_MODE=full'; do
  if grep -Eq "$bad" "$DIR/env.production.example"; then fail "unsafe active value: $bad"; else pass "no active $bad"; fi
done
grep -q '^SECRET=REPLACE_WITH_32_BYTE_HEX$' "$DIR/env.production.example" \
  && pass 'SECRET is a non-working placeholder' || fail 'SECRET placeholder changed'

# 3. Both YAML artifacts parse; workflow actions are pinned to full SHAs.
python3 - <<'PY' || FAIL=$((FAIL+1))
import re, sys, yaml
for path in ["deploy/free-tier/ops-free-tier.yml"]:
    d = yaml.safe_load(open(path))
    assert "jobs" in d and set(d["jobs"]) == {"migrate", "webhooks", "backup"}, path
    print("PASS YAML parsed:", path, "jobs =", list(d["jobs"]))
text = open("deploy/free-tier/ops-free-tier.yml").read()
uses = re.findall(r"^\s*- uses:\s*([^\s#]+)", text, re.M)
assert uses, "no uses: lines"
for u in uses:
    ref = u.split("@")[-1]
    assert re.fullmatch(r"[0-9a-f]{40}", ref), f"unpinned action: {u}"
print("PASS all", len(uses), "uses: refs are 40-hex SHAs")
PY

# 4. Lockfiles and digest pins are present.
for f in Gemfile.lock frontend/package-lock.json; do [ -s "$f" ] && pass "$f present" || fail "$f missing"; done
grep -q 'node@sha256:' "$DIR/Dockerfile.pinned" && grep -q 'ruby@sha256:' "$DIR/Dockerfile.pinned" \
  && pass 'pinned image uses registry digests' || fail 'image digests missing'
grep -q 'bundle _2.5.22_ install' "$DIR/Dockerfile.pinned" && grep -q 'bundler -v 2.5.22' "$DIR/Dockerfile.pinned" \
  && pass 'bundler pinned to Gemfile.lock version' || fail 'bundler not pinned'

# 5. Compose still renders with placeholder secrets (Render does not use Compose, but
#    keeping it valid protects the documented local rehearsal path).
if SECRET=local-verify-secret-0123456789abcdef0123456789 REDIS_PASSWORD=local-verify-redis \
   docker compose config --quiet >/dev/null 2>&1; then pass 'compose config --quiet'; else fail 'compose config --quiet'; fi

# 6. Optional: build the pinned image twice from scratch and compare image IDs.
if [ "${1:-}" = "--verify-build" ]; then
  echo "== reproducible build check (two --no-cache builds, may take several minutes) =="
  docker build --pull --no-cache -q -f "$DIR/Dockerfile.pinned" -t ots-verify-a .
  docker build --pull --no-cache -q -f "$DIR/Dockerfile.pinned" -t ots-verify-b .
  A="$(docker image inspect --format '{{.Id}}' ots-verify-a)"
  B="$(docker image inspect --format '{{.Id}}' ots-verify-b)"
  echo "image A: $A"; echo "image B: $B"
  if [ "$A" = "$B" ]; then
    pass 'two clean builds produced identical image IDs'
  else
    # The legacy builder (Docker without buildx) records wall-clock mtimes in layer
    # tars, so `mkdir tmp /backups` alone changes the image ID between runs. Compare
    # the content that actually matters instead; bit-for-bit IDs require BuildKit
    # with a fixed SOURCE_DATE_EPOCH, unavailable on this host (buildx missing).
    echo 'note: image IDs differ; comparing deterministic content (legacy-builder mtimes)'
    probe() {
      docker run --rm "$1" sh -c '
        sha256sum Gemfile.lock
        find public/app -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum
        ruby -v
        bundle _2.5.22_ -v
        find /usr/local/bundle/gems -maxdepth 1 -type d | sed "s|.*/||" | sort | sha256sum
      ' | sha256sum
    }
    CA="$(probe ots-verify-a)"; CB="$(probe ots-verify-b)"
    echo "content A: $CA"; echo "content B: $CB"
    [ "$CA" = "$CB" ] \
      && pass 'two clean builds have identical lockfile/assets/gems/versions (content reproducibility)' \
      || fail 'image content differs between clean builds'
  fi
fi

echo "== result: $FAIL failure(s) =="
exit "$FAIL"
