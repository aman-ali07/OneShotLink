#!/usr/bin/env bash
# frozen_string_literal: true
#
# The loop controller for OneShotLink: observe -> plan -> act -> verify -> record,
# until the goal in docs/loop/goal.criteria is PROVED met, a budget runs out,
# progress stalls, or the agent asks for a human.
#
#   script/loop.sh                 # one iteration (safe default)
#   script/loop.sh -n 5            # up to 5 iterations
#   script/loop.sh --until-goal    # run to the goal (hard cap 25 iterations)
#   script/loop.sh --dry-run       # render the self-prompt, run nothing
#   script/loop.sh --no-commit     # never commit
#
# Env: LOOP_AGENT (default pi), LOOP_MAX_ITER, LOOP_MAX_ATTEMPT (6),
#      LOOP_STALL_LIMIT (2), LOOP_COMMIT (1|0), LOOP_CRITERIA.
#
# Exit codes: 0 goal met / agent blocked / goal undefined; 1 rule violation or
# agent crash; 3 stalled; 4 attempt budget exhausted; 5 iteration budget exhausted.
#
# See docs/loop/GOAL.md for the floor/target design and the deep gates.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

MAX_ITER="${LOOP_MAX_ITER:-1}"
HARD_CAP=25
MAX_ATTEMPT="${LOOP_MAX_ATTEMPT:-6}"
STALL_LIMIT="${LOOP_STALL_LIMIT:-2}"
DO_COMMIT="${LOOP_COMMIT:-1}"
AGENT="${LOOP_AGENT:-pi}"
DRY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--iterations) MAX_ITER="${2:-1}"; shift 2 ;;
    --until-goal)    MAX_ITER="$HARD_CAP"; shift ;;
    --no-commit)     DO_COMMIT=0; shift ;;
    --dry-run)       DRY=1; shift ;;
    -h|--help)       sed -n '2,22p' "$0"; exit 0 ;;
    *)               echo "loop: unknown arg: $1" >&2; exit 2 ;;
  esac
done

mkdir -p .loop/transcripts
STATE=".loop/state.env"
RID="$(date +%Y%m%d-%H%M%S)-$$"
TS="$(date +%Y-%m-%dT%H:%M)"

ITER=0 ATTEMPT=0 STALL=0 PASS_PREV=-1 PASS_TOTAL=0
# shellcheck disable=SC1090
[[ -f "$STATE" ]] && . "$STATE"
ITER="${ITER:-0}"; ATTEMPT="${ATTEMPT:-0}"; STALL="${STALL:-0}"
PASS_PREV="${PASS_PREV:--1}"; PASS_TOTAL="${PASS_TOTAL:-0}"

save_state() {
  cat >"$STATE" <<EOF
ITER=$ITER
ATTEMPT=$ATTEMPT
STALL=$STALL
PASS_PREV=$PASS_PREV
PASS_TOTAL=$PASS_TOTAL
UPDATED=$(date -Is)
EOF
}

log_append() { printf '%s\n' "$*" >>docs/loop/LOG.md; }

report_line() {  # $1 transcript, $2 did|next -> report text with the prefix stripped
  local pat
  [[ "$2" == "did" ]] && pat='^REPORT:' || pat='^NEXT:'
  grep -iE "$pat" "$1" | tail -n 1 | sed -E "s/^[A-Za-z]+:[[:space:]]*//" | cut -c1-200
}

pass_count() { sed -n 's/^VERIFY: \([0-9][0-9]*\)\/.*/\1/p' "$1" | tail -n 1; }

# --- guard: humans own the goal ------------------------------------------------
HUMAN_FILES=(
  docs/loop/goal.criteria
  docs/loop/GOAL.md
  docs/loop/PROMPT.md
  script/loop_verify.sh
  AGENTS.md
)
snapshot_human() { sha256sum "${HUMAN_FILES[@]}" 2>/dev/null | sha256sum | cut -d' ' -f1; }
HUMAN_NOW="$(snapshot_human)"

revert_human() {
  local reverted=0 f
  for f in "${HUMAN_FILES[@]}"; do
    git ls-files --error-unmatch "$f" >/dev/null 2>&1 || continue
    if [[ -n "$(git status --porcelain -- "$f")" ]]; then
      git checkout -q -- "$f" && reverted=$((reverted + 1))
    fi
  done
  echo "$reverted"
}

# --- preflight ----------------------------------------------------------------
script/loop_verify.sh --quiet >.loop/last-verify.txt 2>&1
vrc=$?
pre_pass="$(pass_count .loop/last-verify.txt)"
pre_line="$(grep -E '^VERIFY:' .loop/last-verify.txt | tail -1)"

if grep -q '^GOAL: UNDEFINED' .loop/last-verify.txt; then
  if (( DRY )); then
    echo "loop: no target is armed yet - rendering the prompt anyway (dry run)."
  else
    echo "loop: no target is armed - the floor is a regression net, not a goal."
    echo "loop: $pre_line"
    echo "loop: arm one T* criterion in docs/loop/goal.criteria (see docs/loop/GOAL.md)."
    echo "loop: nothing was done."
    exit 0
  fi
fi

if (( vrc == 0 )); then
  echo "loop: goal already met at start - nothing to do."
  echo "loop: $pre_line"
  exit 0
fi

# Cheap tripwire: an obviously broken tree (syntax/format) should not burn an
# iteration. The criteria remain the authority.
if command -v git >/dev/null 2>&1 && [[ -n "$(git diff --name-only 2>/dev/null)" ]]; then
  echo "loop: note - working tree already has uncommitted changes; they count as this iteration's starting point."
fi

echo "loop: run $RID  budget=$MAX_ITER iter, $MAX_ATTEMPT attempts, stall limit $STALL_LIMIT"
echo "loop: $pre_line"

# --- the loop ----------------------------------------------------------------
pass="${pre_pass:-0}"
total="$(sed -n 's/^VERIFY: [0-9][0-9]*\/\([0-9][0-9]*\).*/\1/p' .loop/last-verify.txt | tail -1)"
PASS_PREV="$pass"
PASS_TOTAL="${total:-0}"

while :; do
  if [[ "$ITER" -ge "$MAX_ITER" ]]; then
    echo "loop: iteration budget ($MAX_ITER) exhausted; goal still NOT met."
    echo "loop: re-run script/loop.sh --until-goal to continue."
    save_state
    exit 5
  fi
  ITER=$((ITER + 1))

  export LOOP_ITER="$ITER" LOOP_MAX_ITER="$MAX_ITER" LOOP_ATTEMPT="$ATTEMPT"
  export LOOP_MAX_ATTEMPT="$MAX_ATTEMPT" LOOP_STALL="$STALL"
  PROMPT="$(script/loop_prompt.sh)"
  transcript=".loop/transcripts/${RID}-iter$(printf '%02d' "$ITER").log"

  if (( DRY )); then
    printf '%s\n' "$PROMPT" >"${transcript%.log}.prompt.md"
    echo "loop: dry-run, self-prompt saved to ${transcript%.log}.prompt.md ($(printf '%s\n' "$PROMPT" | wc -l | tr -d ' ') lines)"
    echo "loop: would run: $AGENT -p <that prompt>"
    save_state
    exit 0
  fi

  echo
  echo "loop: iter $ITER/$MAX_ITER  attempt $((ATTEMPT + 1))/$MAX_ATTEMPT  progress $pass/$total"

  "$AGENT" -p "$PROMPT" 2>&1 | tee "$transcript"
  agent_status="${PIPESTATUS[0]}"

  if [[ "$(snapshot_human)" != "$HUMAN_NOW" ]]; then
    reverted="$(revert_human)"
    log_append ""
    log_append "## $TS iter $ITER - RULE VIOLATION"
    log_append "- did: modified a human-owned file (${HUMAN_FILES[*]})"
    log_append "- proof: baseline hash mismatch; reverted $reverted file(s), transcript $transcript"
    log_append "- next: a human reviews the transcript and restates the goal if it was wrong"
    log_append "- notes: the agent does not get to move the goal"
    echo "loop: the agent edited a human-owned file. Reverted $reverted file(s); stopping." >&2
    exit 1
  fi

  script/loop_verify.sh >.loop/last-verify.txt 2>&1
  vrc=$?
  pass="$(pass_count .loop/last-verify.txt)"; pass="${pass:-0}"
  total="$(sed -n 's/^VERIFY: [0-9][0-9]*\/\([0-9][0-9]*\).*/\1/p' .loop/last-verify.txt | tail -1)"
  total="${total:-0}"

  if [[ "$agent_status" != "0" ]]; then
    log_append ""
    log_append "## $TS iter $ITER - agent exited $agent_status"
    log_append "- did: unknown, see $transcript"
    log_append "- proof: \`$AGENT\` exited $agent_status; verifier $pass/$total"
    log_append "- next: read the transcript, fix the invocation or the task, then re-run"
    log_append "- notes: harness failure, not a product failure"
    save_state
    echo "loop: agent exited $agent_status - stopping (transcript: $transcript)" >&2
    exit 1
  fi

  if [[ "$DO_COMMIT" == "1" ]] && [[ -n "$(git status --porcelain)" ]]; then
    git add -A
    git commit -qm "chore(loop): iter $ITER - verify $pass/$total (attempt $((ATTEMPT + 1)))" ||
      echo "loop: commit failed (continuing)"
  fi

  if (( vrc == 0 )); then
    log_append ""
    log_append "## $TS iter $ITER - GOAL MET"
    log_append "- did: $(report_line "$transcript" did)"
    log_append "- proof: \`script/loop_verify.sh\` -> GOAL: MET ($pass/$total); transcript $transcript"
    log_append "- next: human review of the diff; then arm the next T* criterion"
    log_append "- notes: the agent's self-report is not part of the proof"
    PASS_PREV="$pass"; PASS_TOTAL="$total"
    save_state
    echo
    echo "loop: GOAL MET ($pass/$total) after $ITER iteration(s)."
    grep -E '^VERIFY:|^GOAL:' .loop/last-verify.txt | tail -2
    exit 0
  fi

  if grep -qiE '^STATUS: *blocked' "$transcript"; then
    log_append ""
    log_append "## $TS iter $ITER - BLOCKED (agent)"
    log_append "- did: $(report_line "$transcript" did)"
    log_append "- proof: verifier $pass/$total, see $transcript"
    log_append "- next: $(report_line "$transcript" next)"
    log_append "- notes: waiting on a human decision"
    PASS_PREV="$pass"; PASS_TOTAL="$total"
    save_state
    echo "loop: agent reports blocked - a human decision is needed (see docs/loop/LOG.md)."
    exit 0
  fi

  if grep -qiE '^STATUS: *done' "$transcript"; then
    log_append ""
    log_append "## $TS iter $ITER - false completion claim"
    log_append "- did: agent claimed done, verifier disagrees"
    log_append "- proof: \`script/loop_verify.sh\` -> GOAL: NOT_MET ($pass/$total)"
    log_append "- next: do not trust the report; read the failing criteria in $transcript"
    log_append "- notes: recorded so the pattern is visible later"
  fi

  if (( PASS_PREV >= 0 )) && (( pass <= PASS_PREV )); then
    STALL=$((STALL + 1)); ATTEMPT=$((ATTEMPT + 1))
  else
    STALL=0; ATTEMPT=0
  fi
  PASS_PREV="$pass"; PASS_TOTAL="$total"
  save_state

  log_append ""
  log_append "## $TS iter $ITER - verify $pass/$total"
  log_append "- did: $(report_line "$transcript" did)"
  log_append "- proof: verify.sh -> $pass/$total, transcript $transcript"
  log_append "- next: $(report_line "$transcript" next)"
  log_append "- notes: stall=$STALL attempt=$ATTEMPT"

  if (( STALL >= STALL_LIMIT )); then
    echo "loop: stalled - $STALL iterations without verifier progress. Stopping for a human." >&2
    exit 3
  fi
  if (( ATTEMPT >= MAX_ATTEMPT )); then
    echo "loop: $ATTEMPT attempts without meeting the goal. Stopping for a human." >&2
    exit 4
  fi
done
