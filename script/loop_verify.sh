#!/usr/bin/env bash
# frozen_string_literal: true
#
# The verdict for the loop. Independent, human-authored proof that the goal is met.
#
#   script/loop_verify.sh           # readable report; exit 0 iff GOAL: MET
#   script/loop_verify.sh --quiet   # only the last two lines
#
# Reads docs/loop/goal.criteria (see the header there for the format).
# ID prefixes: F* = floor (regression), T* = target (the work in flight).
#
# Exits: 0 met, 1 not met (or malformed criteria), 2 undefined target.
#
# This script and the criteria file are HUMAN-OWNED. The loop agent may not edit
# them; script/loop.sh hashes them and reverts + stops if it tries.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

CRIT="${LOOP_CRITERIA:-docs/loop/goal.criteria}"
QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1
say() { (( QUIET )) || echo "$@"; }

if [[ ! -f "$CRIT" ]]; then
  echo "verify: missing $CRIT"
  echo "VERIFY: 0/0 criteria pass"
  echo "GOAL: UNDEFINED"
  exit 2
fi

total=0 pass=0 floor_total=0 floor_pass=0 target_total=0 target_pass=0
malformed=0 lineno=0
fail_ids=()

while IFS= read -r line || [[ -n "$line" ]]; do
  lineno=$((lineno + 1))
  case "$line" in ''|'#'*|' '[[:space:]]*'#'*) continue ;; esac

  nf="$(awk -F'|' '{print NF}' <<<"$line")"
  if (( nf != 6 )); then
    echo "[FAIL] goal.criteria:$lineno  malformed criterion ($nf fields, need 6)"
    echo "       a '|' or '||' in the command column? line: $line"
    malformed=$((malformed + 1))
    continue
  fi

  IFS='|' read -r id title cmd want_exit want_sub tmo <<<"$line"
  trim() { sed 's/^[[:space:]]*//; s/[[:space:]]*$//' <<<"${1:-}"; }
  id="$(trim "$id")"; title="$(trim "$title")"; cmd="$(trim "$cmd")"
  want_exit="$(tr -d '[:space:]' <<<"${want_exit:-0}")"; want_sub="$(trim "$want_sub")"
  tmo="$(tr -d '[:space:]' <<<"${tmo:-300}")"
  [[ -z "$id" || -z "$cmd" ]] && continue
  [[ "$want_exit" =~ ^-?[0-9]+$ ]] || want_exit=0
  [[ "$tmo" =~ ^[0-9]+$ ]] || tmo=300

  total=$((total + 1))
  case "$id" in
    F*) floor_total=$((floor_total + 1)) ;;
    T*) target_total=$((target_total + 1)) ;;
  esac

  out="$(timeout "$tmo" bash -c "$cmd" 2>&1)"
  rc=$?
  ok=1; reason=""
  if [[ "$rc" != "$want_exit" ]]; then ok=0; reason="exit $rc (expected $want_exit)"; fi
  if (( ok )) && [[ -n "$want_sub" ]] && ! grep -qF -- "$want_sub" <<<"$out"; then
    ok=0; reason="output missing $(printf '%q' "$want_sub")"
  fi

  if (( ok )); then
    pass=$((pass + 1))
    case "$id" in
      F*) floor_pass=$((floor_pass + 1)) ;;
      T*) target_pass=$((target_pass + 1)) ;;
    esac
    say "[PASS] $id  $title"
  else
    fail_ids+=("$id")
    say "[FAIL] $id  $title"
    say "       \$ $cmd"
    say "       -> $reason"
    [[ -n "$out" ]] && printf '%s\n' "$out" | tail -n 8 | sed 's/^/       | /'
  fi
done <"$CRIT"

(( malformed > 0 )) && echo "verify: $malformed malformed line(s) in $CRIT - fix the criteria before trusting any verdict"
say ""
echo "VERIFY: ${pass}/${total} criteria pass (floor ${floor_pass}/${floor_total}, target ${target_pass}/${target_total})"
echo "FAILING: ${fail_ids[*]:-none}"

if (( malformed > 0 )); then echo "GOAL: NOT_MET"; exit 1; fi
if (( target_total == 0 )); then
  echo "GOAL: UNDEFINED"
  echo "verify: no T* criterion is active - the floor is a regression net, not a goal."
  echo "verify: arm one in $CRIT (see docs/loop/GOAL.md)."
  exit 2
fi
if (( pass == total )); then echo "GOAL: MET"; exit 0; fi
echo "GOAL: NOT_MET"
exit 1
