#!/usr/bin/env bash
# One command to prove a running OneShotLink deployment works, end to end.
# Usage: BASE_URL=http://127.0.0.1:3000 script/verify-deployment.sh
#
# Requires: curl, docker, node, python3, openssl, Chrome/Chromium for the
# browser journeys. e2e/node_modules is installed here if absent. The stack
# must already be up with AUTH_MODE=simple (the Compose default is disabled).
# Optional: SITE_URL (serve site/ over HTTP for the mobile skip-link check),
# METRICS_TOKEN (authenticated /metrics probe), OTS_VERIFY_RESTORE=1 (isolated
# restore drill; needs ots-dev and redis-cli, touches no production data).
set -uo pipefail

cd "$(dirname "$0")/.."

BASE="${BASE_URL:-http://127.0.0.1:3000}"
export BASE_URL="$BASE"
export CHROME_PATH="${CHROME_PATH:-$(command -v google-chrome || command -v chromium || echo /usr/bin/google-chrome)}"

failed=()
ran=0

step() {
  local name="$1"; shift
  ran=$((ran + 1))
  printf '\n== %s ==\n' "$name"
  if "$@"; then
    printf '[PASS] %s\n' "$name"
  else
    printf '[FAIL] %s\n' "$name" >&2
    failed+=("$name")
  fi
}

step "health" curl -fsS "$BASE/health"
step "config" curl -fsS "$BASE/api/v3/config"
step "SDK examples" script/test-examples.sh

# e2e/node_modules is git-ignored, so a fresh clone has no puppeteer-core.
if [[ ! -d e2e/node_modules/puppeteer-core ]]; then
  step "e2e dependencies" npm --prefix e2e ci --no-audit --no-fund
fi

for journey in test test:accounts test:file test:requests test:webhooks test:states test:a11y; do
  step "e2e $journey" npm --prefix e2e run "$journey"
done

if [[ -n "${SITE_URL:-}" ]]; then
  step "e2e test:mobile" env SITE_URL="$SITE_URL" npm --prefix e2e run test:mobile
else
  printf '\n[SKIP] e2e test:mobile — set SITE_URL to the HTTP-served site/ directory\n'
fi

metrics_scrape() {
  # Read the bearer header from stdin so the token never appears in a process
  # argument list (/proc/<pid>/cmdline) during the verification run.
  printf 'Authorization: Bearer %s\n' "$METRICS_TOKEN" | curl -fsS -H @- "$BASE/metrics"
}

if [[ -n "${METRICS_TOKEN:-}" ]]; then
  step "metrics scrape" metrics_scrape
else
  printf '\n[SKIP] metrics scrape — set METRICS_TOKEN\n'
fi

if [[ "${OTS_VERIFY_RESTORE:-0}" == "1" ]]; then
  step "isolated restore drill" script/restore-drill.sh
else
  printf '\n[SKIP] restore drill — set OTS_VERIFY_RESTORE=1 (isolated instance only)\n'
fi

printf '\n== Result ==\n'
printf '%d checks run, %d failed\n' "$ran" "${#failed[@]}"
if ((${#failed[@]})); then
  printf 'Failed: %s\n' "${failed[*]}" >&2
  exit 1
fi
printf 'DEPLOYMENT VERIFIED against %s\n' "$BASE"
