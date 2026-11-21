#!/usr/bin/env bash
# Boot a throwaway OneShotLink stack and run every dependency-free SDK example.
# Usage: script/test-examples.sh
# Requires: docker, curl, python3, node, openssl. Leaves no containers behind.
# Uses throwaway Redis DB 15 in its own container; never touches a shared instance.
set -euo pipefail

cd "$(dirname "$0")/.."

# Prefer the source-mounted ots-dev image: a locally built oneshotlink-web can
# be stale after a source change and fail the examples for the wrong reason.
# CI has no ots-dev and builds oneshotlink-web fresh, so it falls through to
# that image. Set OTS_APP_IMAGE explicitly to override the choice.
APP_IMAGE="${OTS_APP_IMAGE:-}"
if [[ -z "$APP_IMAGE" ]]; then
  if docker image inspect ots-dev >/dev/null 2>&1 && docker volume inspect ots-bundle >/dev/null 2>&1; then
    APP_IMAGE="ots-dev"
  elif docker image inspect oneshotlink-web >/dev/null 2>&1; then
    APP_IMAGE="oneshotlink-web"
  else
    echo "No image found. Build once:" >&2
    echo "  docker build -t oneshotlink-web .   # production image" >&2
    echo "  # or see TESTING.md §2 for the ots-dev workflow" >&2
    exit 1
  fi
else
  docker image inspect "$APP_IMAGE" >/dev/null 2>&1 || { echo "No image $APP_IMAGE" >&2; exit 1; }
fi

REDIS_PORT="${EXAMPLE_REDIS_PORT:-6415}"
APP_PORT="${EXAMPLE_APP_PORT:-3015}"
REDIS_NAME="ots-examples-redis-$$"
APP_NAME="ots-examples-app-$$"
BASE="http://127.0.0.1:${APP_PORT}"

cleanup() {
  docker rm -f "$APP_NAME" "$REDIS_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

docker run -d --rm --name "$REDIS_NAME" -p "127.0.0.1:${REDIS_PORT}:6379" redis:7.4-alpine >/dev/null
APP_ARGS=()
WORKDIR_ARGS=()
if [ "$APP_IMAGE" = "ots-dev" ]; then
  APP_ARGS=(-v "$PWD":/app -v ots-bundle:/bundle -e BUNDLE_PATH=/bundle -w /app)
  WORKDIR_ARGS=(bundle exec puma -C config/puma.rb)
fi
docker run -d --name "$APP_NAME" --network=host \
  "${APP_ARGS[@]}" \
  -e "SECRET=$(openssl rand -hex 32)" \
  -e "REDIS_URL=redis://127.0.0.1:${REDIS_PORT}/15" \
  -e REDIS_PASSWORD=example-harness-token \
  -e RACK_ENV=production -e "PORT=${APP_PORT}" \
  -e AUTH_MODE=simple -e "HOST=127.0.0.1:${APP_PORT}" \
  "$APP_IMAGE" "${WORKDIR_ARGS[@]}" >/dev/null

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

for example in curl/quickstart.sh curl/advanced.sh typescript/quickstart.mjs typescript/advanced.mjs python/quickstart.py python/advanced.py; do
  printf '\n== examples/%s ==\n' "$example"
  case "$example" in
    *.sh)  BASE_URL="$BASE" bash "examples/$example" ;;
    *.mjs) BASE_URL="$BASE" node "examples/$example" ;;
    *.py)  BASE_URL="$BASE" python3 "examples/$example" ;;
  esac
done

printf '\nAll SDK examples passed against %s\n' "$BASE"
