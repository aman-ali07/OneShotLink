#!/usr/bin/env bash
# Boot a throwaway OneShotLink stack and run every dependency-free SDK example.
# Usage: script/test-examples.sh
# Requires: docker, curl, python3, node. Leaves no containers behind.
set -euo pipefail

cd "$(dirname "$0")/.."

REDIS_PORT="${EXAMPLE_REDIS_PORT:-6415}"
APP_PORT="${EXAMPLE_APP_PORT:-3015}"
REDIS_NAME="ots-examples-redis-$$"
APP_NAME="ots-examples-app-$$"
BASE="http://127.0.0.1:${APP_PORT}"

cleanup() {
  docker rm -f "$APP_NAME" "$REDIS_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

docker run -d --rm --name "$REDIS_NAME" -p "${REDIS_PORT}:6379" redis:7.4-alpine >/dev/null
docker run -d --name "$APP_NAME" --network=host \
  -v "$PWD":/app -v ots-bundle:/bundle -e BUNDLE_PATH=/bundle \
  -e "SECRET=$(openssl rand -hex 32)" \
  -e "REDIS_URL=redis://127.0.0.1:${REDIS_PORT}/13" \
  -e RACK_ENV=production -e "PORT=${APP_PORT}" \
  -w /app ots-dev bundle exec puma -C config/puma.rb >/dev/null

ready=0
for _ in $(seq 1 30); do
  if curl -fsS --max-time 2 "$BASE/health" >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
if [ "$ready" != "1" ]; then
  echo "stack never became healthy" >&2
  docker logs "$APP_NAME" 2>&1 | tail -20 >&2
  exit 1
fi

for example in curl/quickstart.sh typescript/quickstart.mjs python/quickstart.py; do
  printf '\n== examples/%s ==\n' "$example"
  case "$example" in
    *.sh)  BASE_URL="$BASE" bash "examples/$example" ;;
    *.mjs) BASE_URL="$BASE" node "examples/$example" ;;
    *.py)  BASE_URL="$BASE" python3 "examples/$example" ;;
  esac
done

printf '\nAll SDK examples passed against %s\n' "$BASE"
