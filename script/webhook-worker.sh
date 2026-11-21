#!/usr/bin/env bash
# One-shot drain of queued webhook deliveries.
#
# This is intentionally NOT a daemon and costs nothing: host cron or a systemd
# timer (both already on the machine) calls it. The app never runs a worker in
# the web process, and the queue is Redis (already running), so no new service,
# broker, or paid add-on is introduced (K-46).
#
# Safety properties:
#   * flock prevents overlapping runs, so a slow delivery cannot double-drain.
#   * It refuses to run when WEBHOOK_ALLOW_PRIVATE=true (the local-testing SSRF
#     bypass). The app itself pins delivery to the IP validated at creation and
#     rejects private ranges; the operator's egress firewall is the last layer.
#   * No secret is passed on the command line: exec inherits the container env.
set -euo pipefail

# Default to this script's repository, not an author-specific absolute path.
# Cron/systemd units may still override with OTS_PROJECT_DIR.
PROJECT_DIR="${OTS_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
# A predictable lock in world-writable /tmp can be pre-created or symlinked by
# another local user (and truncating a symlink target as root destroys files).
# Default to a private, worker-owned directory; callers may still override.
LOCK_DIR="${OTS_WORKER_LOCK_DIR:-${XDG_RUNTIME_DIR:-${PROJECT_DIR}/tmp}}"
LOCK_FILE="${OTS_WORKER_LOCK:-${LOCK_DIR}/ots-webhook-worker.lock}"
mkdir -p "$LOCK_DIR"
chmod 700 "$LOCK_DIR" 2>/dev/null || true
umask 077
COMPOSE_PROJECT="${COMPOSE_PROJECT_NAME:-oneshotlink}"
LIMIT="${OTS_WEBHOOK_LIMIT:-10}"

command -v flock >/dev/null || { echo "webhook-worker: flock is required (util-linux)" >&2; exit 1; }
command -v docker >/dev/null || { echo "webhook-worker: docker is required" >&2; exit 1; }

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "webhook-worker: another run holds the lock; exiting cleanly"
  exit 0
fi

cd "$PROJECT_DIR"

if docker compose -p "$COMPOSE_PROJECT" exec -T web printenv WEBHOOK_ALLOW_PRIVATE 2>/dev/null | grep -qx true; then
  echo "webhook-worker: refusing to run with WEBHOOK_ALLOW_PRIVATE=true" >&2
  exit 1
fi

docker compose -p "$COMPOSE_PROJECT" exec -T web bin/ots webhooks:work "$LIMIT"
