#!/usr/bin/env bash
# frozen_string_literal: true
#
# Observation phase, rendered as text for the agent's next prompt.
# Repo-aware: it also surfaces the open rows in TASKS.md, because that file is the
# status of record in this project (see AGENTS.md).
#
# Env in: LOOP_ITER, LOOP_MAX_ITER, LOOP_ATTEMPT, LOOP_MAX_ATTEMPT, LOOP_STALL
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

cat <<'EOF'
## Observation (generated state, not a human prompt)

EOF

echo "iteration: ${LOOP_ITER:-?}/${LOOP_MAX_ITER:-?}   attempt: ${LOOP_ATTEMPT:-0}/${LOOP_MAX_ATTEMPT:-?}   no-progress streak: ${LOOP_STALL:-0}"
echo "time: $(date -Is)"

echo
echo "### Repository"
echo "- branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
echo "- HEAD: $(git log -1 --oneline 2>/dev/null || echo 'no commits')"
dirty="$(git status --porcelain 2>/dev/null)"
if [[ -z "$dirty" ]]; then
  echo "- working tree: clean"
else
  echo "- working tree: dirty ($(printf '%s\n' "$dirty" | wc -l | tr -d ' ') paths)"
  printf '%s\n' "$dirty" | head -n 25 | sed 's/^/    /'
fi
if [[ -f VERSION ]] || [[ -f lib/onetime/version.rb ]]; then
  echo "- version: $(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' lib/onetime/version.rb 2>/dev/null | head -1)"
fi

echo
echo "### Verifier verdict (authoritative)"
if [[ -f .loop/last-verify.txt ]]; then
  sed 's/^/    /' .loop/last-verify.txt
else
  script/loop_verify.sh 2>&1 | sed 's/^/    /'
fi

echo
echo "### Criteria (human-owned, do not edit)"
grep -vE '^[[:space:]]*(#|$)' docs/loop/goal.criteria 2>/dev/null |
  awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/,"",$1); gsub(/^[ \t]+|[ \t]+$/,"",$2); gsub(/^[ \t]+|[ \t]+$/,"",$3);
               printf "    %-4s %s\n         $ %s\n", $1, $2, $3 }'

echo
echo "### Open work (TASKS.md rows that are not DONE)"
# TASKS.md has two table shapes (Completed: ID|Task|Status|Evidence|Notes, and
# dependency tables), so select by the status word instead of by column position.
grep -E '^\| T-[0-9]+ \|' TASKS.md 2>/dev/null |
  grep -E '\|[[:space:]]*(TODO|BLOCKED|IN PROGRESS)[[:space:]]*\|' |
  awk -F'|' '{ for (i = 2; i < NF; i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i) }
               status = "";
               for (i = 2; i < NF; i++) if ($i == "TODO" || $i == "BLOCKED" || $i == "IN PROGRESS") status = $i;
               printf "    %-6s %-12s %.90s\n", $2, status, $3 }' | head -n 10

echo
echo "### Plan memory (docs/loop/PLAN.md, section: Now)"
awk '/^## +Now/{f=1;next} /^## /{f=0} f' docs/loop/PLAN.md 2>/dev/null |
  sed '/^[[:space:]]*$/d; s/^/    /' | head -n 40

echo
echo "### Last 2 iterations (docs/loop/LOG.md)"
awk '/^## /{n++} {buf[n]=buf[n] $0 "\n"} END{for (i=(n>2?n-1:1); i<=n; i++) printf "%s", buf[i]}' \
  docs/loop/LOG.md 2>/dev/null | sed 's/^/    /'
