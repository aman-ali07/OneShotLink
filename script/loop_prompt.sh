#!/usr/bin/env bash
# frozen_string_literal: true
#
# The self-prompt: this project's static loop instructions + a freshly generated
# observation. Re-rendered every iteration, so the agent always starts from the
# current verdict, diff, plan memory and TASKS.md state.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

cat docs/loop/PROMPT.md
echo
echo "---"
echo
script/loop_observe.sh
echo
echo "---"
cat <<'EOF'
## Your move

Make the smallest change that turns at least one T* `[FAIL]` into `[PASS]` without
turning any `[PASS]` (floor included) into `[FAIL]`. Then run
`script/loop_verify.sh` yourself and fix what it reports, up to three times. Then
write your report.

Your last three lines must be exactly:

REPORT: <what you changed and the proof command you ran>
NEXT: <the single next action you would take>
STATUS: progress | done | blocked

Use `done` only if `script/loop_verify.sh` printed `GOAL: MET` in this iteration.
Use `blocked` only for something a human must decide or supply. Then stop.
EOF
