#!/usr/bin/env bash
# Brand sweep over the surfaces that actually ship (T-78 / R-09 gate).
#
# The replica-brand tool walks the filesystem and ignores .gitignore, so a run
# from the repo root also scans prose and any local run artifacts. That made the
# gate fail on this checkout's own directory name used as a path in agent notes
# and transcripts, while no shipped surface was ever affected. Weakening the tool
# is not an option, so this wrapper narrows what gets scanned instead: the
# tracked files that reach a user, a browser or a host. Prose (*.md) and the
# replica/ planning folder are excluded because the original's name legitimately
# appears there as a comparison.
#
# Exit codes: 0 clean, 1 hits found, 2 the sweep tool is not installed.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sweep="${SWEEP:-$HOME/.agents/skills/replica-brand/sweep.py}"

if [ ! -f "$sweep" ]; then
  echo "brand sweep: $sweep not found; reinstall the replica-brand skill (see AGENTS.md)" >&2
  exit 2
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Copy exactly the tracked, non-prose, non-planning files at their repo paths so
# the report's file names match the repo. Untracked artifacts cannot sneak in.
git -C "$root" ls-files -z -- . ':(exclude)*.md' ':(exclude)replica/**' |
  tar -C "$root" --null -T - -cf - |
  tar -xf - -C "$work"

cd "$work"
exec python3 "$sweep" . --config "$root/replica/brand.json"
