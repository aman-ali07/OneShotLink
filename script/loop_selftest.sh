#!/usr/bin/env bash
# frozen_string_literal: true
#
# Self-test for the loop controller, in the spirit of script/preflight_selftest.sh:
# prove the gate cannot rot into "always green". Drives the real controller with
# fake agents so no model calls happen, and asserts every stop condition fires.
#
#   script/loop_selftest.sh
#
# Each case builds a throwaway repo containing only the loop machinery, so this
# tests the controller, not the product. Exits 0 when every case behaves.
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

ok()  { PASS=$((PASS + 1)); printf '  \033[32m[PASS]\033[0m %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  \033[31m[FAIL]\033[0m %s\n' "$1"; }
info() { printf '\n== %s ==\n' "$1"; }

sandbox() {
  local d
  d="$(mktemp -d)"
  mkdir -p "$d/script" "$d/docs/loop"
  cp "$SRC"/script/loop.sh "$SRC"/script/loop_verify.sh \
     "$SRC"/script/loop_observe.sh "$SRC"/script/loop_prompt.sh "$d/script/"
  cp "$SRC"/docs/loop/PROMPT.md "$SRC"/docs/loop/GOAL.md \
     "$SRC"/docs/loop/PLAN.md "$SRC"/docs/loop/LOG.md "$d/docs/loop/"
  printf '# AGENTS.md (stub for the self-test)\n' >"$d/AGENTS.md"
  printf 'TASKS.md: no rows\n' >"$d/TASKS.md"
  chmod +x "$d"/script/*.sh
  ( cd "$d" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm base ) >/dev/null
  printf '%s' "$d"
}

criteria() {  # $1 dir, $2 body
  printf '%s\n' "$2" >"$1/docs/loop/goal.criteria"
  ( cd "$1" && git add -A && git -c user.name=t -c user.email=t@t commit -qm criteria ) >/dev/null
}

fake_agent() {  # $1 dir, $2 shell body
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"$1/agent.sh"
  chmod +x "$1/agent.sh"
}

run_loop() {  # $1 dir, rest = args; echoes exit code
  local d="$1"; shift
  ( cd "$d" && LOOP_AGENT="$d/agent.sh" script/loop.sh "$@" ) >"$d/out.log" 2>&1
  echo $?
}

FLOOR='F1 | target file exists | test -f app.txt | 0 | | 10'
TARGET='T1 | app reports ready | test "$(cat app.txt 2>/dev/null)" = "ready" | 0 | | 10'

# --- 1. convergence ----------------------------------------------------------
info "1. converges: target flips, GOAL MET, iteration committed"
d="$(sandbox)"; criteria "$d" "$FLOOR
$TARGET"
fake_agent "$d" 'echo ready > app.txt; echo "REPORT: wrote app.txt"; echo "NEXT: none"; echo "STATUS: done"'
rc="$(run_loop "$d" -n 3)"
[[ "$rc" == 0 ]] && ok "exit 0 on goal met" || bad "exit $rc (want 0)"
v="$( cd "$d" && script/loop_verify.sh --quiet 2>&1 )"
[[ "$v" == *"GOAL: MET"* ]] && ok "verifier agrees" || bad "verifier disagrees"
commits="$( cd "$d" && git log --oneline )"
[[ "$commits" == *"chore(loop): iter 1"* ]] && ok "iteration commit recorded" || bad "no iteration commit"
( cd "$d" && grep -q 'GOAL MET' docs/loop/LOG.md ) && ok "LOG records the verdict" || bad "LOG missing verdict"
rm -rf "$d"

# --- 2. undefined target -----------------------------------------------------
info "2. no target armed: refuses to work, exits 0"
d="$(sandbox)"; criteria "$d" "$FLOOR"
fake_agent "$d" 'echo ready > app.txt; echo "STATUS: progress"'
rc="$(run_loop "$d" -n 3)"
[[ "$rc" == 0 ]] && ok "exit 0" || bad "exit $rc"
( cd "$d" && grep -q 'no target is armed' out.log ) && ok "explains why it did nothing" || bad "no explanation"
( cd "$d" && [[ ! -f app.txt ]] ) && ok "agent never ran" || bad "agent ran with no target"
rm -rf "$d"

# --- 3. floor regression ----------------------------------------------------
info "3. floor regression keeps the goal red even when the target passes"
d="$(sandbox)"; criteria "$d" 'F1 | missing floor file | test -f never.txt | 0 | | 10
T1 | target passes | true | 0 | | 10'
fake_agent "$d" 'echo "REPORT: target is fine"; echo "NEXT: floor"; echo "STATUS: progress"'
rc="$(run_loop "$d" -n 2)"
[[ "$rc" == 3 ]] && ok "exit 3 (stalled, goal still red)" || bad "exit $rc (want 3)"
v="$( cd "$d" && script/loop_verify.sh --quiet 2>&1 )"
[[ "$v" == *"GOAL: NOT_MET"* ]] && ok "GOAL stays NOT_MET" || bad "floor ignored"
[[ "$v" == *"floor 0/1"* && "$v" == *"target 1/1"* ]] &&
  ok "floor red + target green still reads NOT_MET" || bad "floor/target accounting wrong: $v"
rm -rf "$d"

# --- 4. stall ---------------------------------------------------------------
info "4. stops on stall instead of spinning"
d="$(sandbox)"; criteria "$d" "$FLOOR
$TARGET"
fake_agent "$d" 'echo "REPORT: did nothing"; echo "NEXT: same idea"; echo "STATUS: progress"'
rc="$(run_loop "$d" -n 10)"
[[ "$rc" == 3 ]] && ok "exit 3 on stall" || bad "exit $rc (want 3)"
iters="$( cd "$d" && grep -c 'loop: iter' out.log )"
[[ "$iters" -lt 10 ]] && ok "stopped early ($iters iterations of 10)" || bad "used the whole budget"
rm -rf "$d"

# --- 5. rule violation ------------------------------------------------------
info "5. reverts and stops when the agent edits the goal"
d="$(sandbox)"; criteria "$d" "$FLOOR
$TARGET"
fake_agent "$d" 'echo "T9 | trivial | true | 0 | | 5" >> docs/loop/goal.criteria; echo "REPORT: relaxed the goal"; echo "NEXT: none"; echo "STATUS: done"'
rc="$(run_loop "$d" -n 2)"
[[ "$rc" == 1 ]] && ok "exit 1 on violation" || bad "exit $rc (want 1)"
( cd "$d" && grep -q 'T9' docs/loop/goal.criteria ) && bad "goal edit survived" || ok "goal edit reverted"
( cd "$d" && grep -q 'RULE VIOLATION' docs/loop/LOG.md ) && ok "violation logged" || bad "not logged"
rm -rf "$d"

# --- 6. blocked -------------------------------------------------------------
info "6. stops cleanly when the agent is blocked"
d="$(sandbox)"; criteria "$d" "$FLOOR
$TARGET"
fake_agent "$d" 'echo "REPORT: needs approved copy"; echo "NEXT: human supplies copy"; echo "STATUS: blocked"'
rc="$(run_loop "$d" -n 5)"
[[ "$rc" == 0 ]] && ok "exit 0 on blocked" || bad "exit $rc (want 0)"
( cd "$d" && grep -q 'BLOCKED (agent)' docs/loop/LOG.md ) && ok "question recorded" || bad "not recorded"
rm -rf "$d"

# --- 7. false completion claim ----------------------------------------------
info "7. a false 'done' claim is recorded, not believed"
d="$(sandbox)"; criteria "$d" "$FLOOR
$TARGET"
fake_agent "$d" 'echo "REPORT: all done"; echo "NEXT: none"; echo "STATUS: done"'
rc="$(run_loop "$d" -n 2)"
[[ "$rc" == 3 ]] && ok "exit 3 (stalled, not fooled)" || bad "exit $rc (want 3)"
( cd "$d" && grep -q 'false completion claim' docs/loop/LOG.md ) && ok "claim logged as unverified" || bad "claim not logged"
rm -rf "$d"

# --- 8. attempt budget ------------------------------------------------------
info "8. attempt budget stops a loop that makes progress then plateaus"
d="$(sandbox)"; criteria "$d" "$FLOOR
$TARGET"
fake_agent "$d" 'echo "REPORT: partial"; echo "NEXT: keep going"; echo "STATUS: progress"'
( cd "$d" && LOOP_AGENT="$d/agent.sh" LOOP_MAX_ATTEMPT=2 LOOP_STALL_LIMIT=99 script/loop.sh -n 10 >out.log 2>&1 )
rc=$?
[[ "$rc" == 4 ]] && ok "exit 4 on attempt budget" || bad "exit $rc (want 4)"
rm -rf "$d"

# --- 9. dry run -------------------------------------------------------------
info "9. --dry-run renders the self-prompt and touches nothing"
d="$(sandbox)"; criteria "$d" "$FLOOR
$TARGET"
fake_agent "$d" 'echo ready > app.txt'
rc="$(run_loop "$d" --dry-run)"
[[ "$rc" == 0 ]] && ok "exit 0" || bad "exit $rc"
( cd "$d" && [[ ! -f app.txt ]] ) && ok "agent did not run" || bad "agent ran in dry-run"
p="$( cd "$d" && ls .loop/transcripts/*.prompt.md 2>/dev/null | head -n1 )"
[[ -n "$p" ]] && ok "prompt saved for inspection" || bad "no prompt saved"
( cd "$d" && grep -q 'Observation' "$p" && grep -q 'T1' "$p" && grep -q 'STATUS:' "$p" ) &&
  ok "prompt has observation, criteria, report contract" || bad "prompt incomplete"
rm -rf "$d"

# --- 10. malformed criteria -------------------------------------------------
info "10. rejects a criterion whose command contains a pipe"
d="$(sandbox)"; criteria "$d" 'F1 | bad | true || false | 0 | | 5'
v="$( cd "$d" && script/loop_verify.sh --quiet 2>&1 )"
[[ "$v" == *"malformed criterion"* ]] && ok "malformed row reported" || bad "malformed row accepted"
[[ "$v" == *"GOAL: NOT_MET"* ]] && ok "verdict refuses to be green" || bad "verdict trusted a broken file"
rm -rf "$d"

# --- 11. this repo's own gate ----------------------------------------------
info "11. this repository"
( cd "$SRC" && bash -n script/loop.sh && bash -n script/loop_verify.sh &&
  bash -n script/loop_observe.sh && bash -n script/loop_prompt.sh ) && ok "scripts parse" || bad "syntax error"
v="$( cd "$SRC" && script/loop_verify.sh --quiet 2>&1 )"
[[ "$v" != *"malformed"* ]] && ok "goal.criteria is well-formed" || bad "malformed criteria in the repo"
[[ "$v" == *"floor 5/5"* ]] && ok "floor gates are green" || bad "floor is red: $v"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))