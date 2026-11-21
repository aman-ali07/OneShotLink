#!/usr/bin/env bash
# Verify a backup/restore round trip on a THROWAWAY Redis instance.
#
# This script never touches a production database: it starts its own Redis
# container on a private loopback port, flushes only that instance's DB 15,
# and removes the container and temp files on exit. Nothing is deployed.
set -euo pipefail

PORT="${OTS_DRILL_PORT:-6413}"
NAME="ots-restore-drill-$$"
WORK="$(mktemp -d)"
# Test-only key. It is printed nowhere and is never a deployment credential.
SECRET_VALUE="drill-only-not-a-deployment-key-0000000000000000000000000000"
REDIS_URL_VALUE="redis://127.0.0.1:${PORT}/15"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

docker run -d --rm --name "$NAME" -p "127.0.0.1:${PORT}:6379" redis:7.4-alpine >/dev/null
for _ in $(seq 1 30); do
  redis-cli -p "$PORT" ping >/dev/null 2>&1 && break
  sleep 0.2
done
redis-cli -p "$PORT" ping >/dev/null

run() {
  docker run --rm --network=host \
    -v "$PWD":/app -v ots-bundle:/bundle -v "$WORK":/drill \
    -e BUNDLE_PATH=/bundle -e REDIS_URL="$REDIS_URL_VALUE" \
    -e SECRET="$SECRET_VALUE" -e RACK_ENV=test -e AUTH_MODE=disabled \
    -w /app ots-dev "$@"
}

echo "== seed throwaway DB =="
KEYS="$(run bundle exec ruby -e '
  require_relative "lib/onetime"
  Onetime::Migrate.apply!
  live, = Onetime::Models::Secret.create(plaintext: "drill-live-payload", ttl: 600, owner_id: "drill-owner")
  spent, = Onetime::Models::Secret.create(plaintext: "drill-spent-payload", ttl: 600)
  raw = Onetime::Store.redis.get(Onetime::Models::Secret.object_key(spent))
  raise "consume failed" unless Onetime::Models::Secret.consume(spent, raw)
  puts "#{live} #{spent}"
' | tail -1)"
LIVE_KEY="${KEYS%% *}"
SPENT_KEY="${KEYS##* }"
echo "seeded live=$LIVE_KEY spent=$SPENT_KEY"

echo "== export =="
run bin/ots backup --out /drill/backup.json
test -s "$WORK/backup.json"

echo "== wipe ONLY the throwaway DB and restore =="
redis-cli -p "$PORT" -n 15 flushdb >/dev/null
run bin/ots restore --in /drill/backup.json

echo "== verify =="
RESULT="$(run bundle exec ruby -e '
  require_relative "lib/onetime"
  live = ARGV[0]; spent = ARGV[1]
  raw = Onetime::Store.redis.get(Onetime::Models::Secret.object_key(live))
  value = raw ? Onetime::Crypto.decrypt(JSON.parse(raw)) : "MISSING"
  puts "live=#{value}"
  puts "spent=#{Onetime::Store.redis.exists?(Onetime::Models::Secret.object_key(spent)) ? "RESURRECTED" : "GONE"}"
  puts "schema=#{Onetime::Migrate.current_version}"
  puts "migration_pending=#{Onetime::Migrate.dry_run[:planned].empty? ? "no" : "yes"}"
' "$LIVE_KEY" "$SPENT_KEY")"
echo "$RESULT"

echo "$RESULT" | grep -q '^live=drill-live-payload$'
echo "$RESULT" | grep -q '^spent=GONE$'
echo "$RESULT" | grep -q '^schema=1$'
echo "$RESULT" | grep -q '^migration_pending=no$'
echo "RESTORE DRILL PASSED (isolated instance; no production data touched)"
