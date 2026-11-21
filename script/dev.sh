#!/usr/bin/env bash
# One-command local development: source-mounted Puma + Redis + Vite dev server.
# No Ruby on the host; Ctrl-C stops every child and removes the containers.
# Usage: bash script/dev.sh   (then open http://127.0.0.1:5174)
set -euo pipefail

cd "$(dirname "$0")/.."

APP_PORT="${DEV_APP_PORT:-3110}"
UI_PORT="${DEV_UI_PORT:-5174}"
REDIS_PORT="${DEV_REDIS_PORT:-6429}"
REDIS_NAME="ots-dev-redis-$$"
APP_NAME="ots-dev-app-$$"
DEV_IMAGE="ots-dev"
BUNDLE_VOLUME="ots-bundle"

cleanup() {
  docker rm -f "$APP_NAME" "$REDIS_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

# Build the small dev image once if it is not present. The production image is
# not used here: it bakes the built SPA and does not mount the source tree.
if ! docker image inspect "$DEV_IMAGE" >/dev/null 2>&1; then
  echo "Building $DEV_IMAGE once (network required: apt)..."
  docker build -t "$DEV_IMAGE" -f - . <<'DOCKER'
FROM ruby:3.3-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential libssl-dev curl && rm -rf /var/lib/apt/lists/*
DOCKER
fi
docker volume inspect "$BUNDLE_VOLUME" >/dev/null 2>&1 || docker volume create "$BUNDLE_VOLUME" >/dev/null

echo "Starting Redis on :${REDIS_PORT} (throwaway DB 15)..."
docker run -d --rm --name "$REDIS_NAME" -p "127.0.0.1:${REDIS_PORT}:6379" redis:7.4-alpine >/dev/null

echo "Starting Puma on :${APP_PORT} (source mounted, hot reload via restart)..."
docker run -d --name "$APP_NAME" --network=host \
  -v "$PWD":/app -v "$BUNDLE_VOLUME":/bundle \
  -e BUNDLE_PATH=/bundle -e RACK_ENV=development -e "PORT=${APP_PORT}" \
  -e "SECRET=${DEV_SECRET:-$(openssl rand -hex 32)}" \
  -e "REDIS_URL=redis://127.0.0.1:${REDIS_PORT}/15" -e REDIS_PASSWORD=dev-only \
  -e "HOST=127.0.0.1:${UI_PORT}" -e AUTH_MODE=simple -e WEB_CONCURRENCY=1 \
  -w /app "$DEV_IMAGE" bundle exec puma -C config/puma.rb >/dev/null

for _ in $(seq 1 30); do
  curl -fsS "http://127.0.0.1:${APP_PORT}/health" >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS "http://127.0.0.1:${APP_PORT}/health" >/dev/null

echo "Starting Vite on http://127.0.0.1:${UI_PORT} (proxies /api and /health to :${APP_PORT})..."
VITE_API_PROXY="http://127.0.0.1:${APP_PORT}" npm --prefix frontend run dev -- --host 127.0.0.1 --port "$UI_PORT"
