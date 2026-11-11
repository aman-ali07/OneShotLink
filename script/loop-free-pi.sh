#!/usr/bin/env bash
# frozen_string_literal: true
#
# Run ONE loop-engineering cycle with free-pi (npx free-pi-cli@latest).
#
# free-pi has no headless/print mode - it is a TUI - so this drives the TUI inside a
# detached tmux session: start it, paste the cycle prompt, wait until the screen stops
# changing for --idle seconds, capture the transcript, exit.
#
#   script/loop-free-pi.sh                     # one triage cycle (L1 report-only)
#   script/loop-free-pi.sh --keep              # leave the session running: tmux attach -t loop-freepi
#   script/loop-free-pi.sh --idle 60 --timeout 2400
#   script/loop-free-pi.sh --continue          # resume the last free-pi session instead of --new
#
# Exit: 0 the cycle finished (screen went idle), 1 timeout or setup failure.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

SESSION="loop-freepi"
IDLE=45
TMO=1800
KEEP=0
MODE="--new"
RUNS=".loop-runs"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session)  SESSION="${2:-loop-freepi}"; shift 2 ;;
    --idle)     IDLE="${2:-45}"; shift 2 ;;
    --timeout)  TMO="${2:-1800}"; shift 2 ;;
    --keep)     KEEP=1; shift ;;
    --continue) MODE="--continue"; shift ;;
    -h|--help)  sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "loop-free-pi: unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v tmux >/dev/null || { echo "loop-free-pi: tmux is required (apt install tmux)" >&2; exit 1; }
command -v npx  >/dev/null || { echo "loop-free-pi: npx is required" >&2; exit 1; }
[[ -f .claude/skills/loop-triage/SKILL.md ]] ||
  { echo "loop-free-pi: .claude/skills/loop-triage/SKILL.md missing - run npx @cobusgreyling/loop init . --pattern daily-triage --tool claude" >&2; exit 1; }

mkdir -p "$RUNS"
STAMP="$(date +%Y%m%d-%H%M%S)"
TRANSCRIPT="$RUNS/$STAMP-transcript.txt"
PROMPT_FILE="$RUNS/$STAMP-prompt.txt"

# --- the cycle prompt ---------------------------------------------------------
cat >"$PROMPT_FILE" <<'EOF'
You are running ONE cycle of an automated loop in this repository (the loop-engineering
kit). This is a report-only cycle: L1. Do not change code, do not commit, do not push,
do not open PRs, do not run anything that talks to a live host.

Read, in this order, before you do anything else:

1. `AGENTS.md` (repo working rules and the doc table)
2. `LOOP.md` (what this loop is allowed to do), `loop-constraints.md` (binding rules),
   `STATE.md` (what the loop already knows), `loop-budget.md` (caps)
3. `.claude/skills/loop-triage/SKILL.md` - follow it exactly; it defines the report
   format and the rules

Then gather real evidence from this repo, cheapest first:

- `git log --oneline -30`, `git status`, recent diffs on main
- open rows in `TASKS.md` that are not DONE, and the open items in `KNOWN_ISSUES.md`
- `PRODUCTION_READINESS.md` open gates (T-70 TLS, T-71 Redis firewall are operator-only:
  never propose code for them)
- whether the gates still pass - only run a gate if it is cheap and local:
  `npm --prefix frontend test`, `npm --prefix frontend run typecheck`, or the backend
  suite via `docker run --rm --network=host -v "$PWD":/app -v ots-bundle:/bundle -e
  BUNDLE_PATH=/bundle -w /app ots-dev bundle exec rspec` (needs Redis on port 6399).
  Do not run `script/preflight_selftest.sh` or a Compose stack in this cycle.

Then write your output:

- Rewrite `STATE.md` keeping its current structure: `Last run:` (ISO timestamp),
  `## High Priority`, `## Watch List`, `## Recent Noise (ignored this run)`. Facts only,
  each with the file or command that proves it. Drop the template placeholders.
- Append ONE entry to `loop-run-log.md`: date, cycle type (L1 triage), what you looked
  at, counts (high/watch/noise), gates you ran and their result, and anything you could
  not check and why.
- Do not invent work. If nothing is worth acting on, say so plainly; an empty high-priority
  list is a valid result.

Constraints that are not negotiable: never print or commit secrets, passphrases, keys or
ciphertext; never claim zero-knowledge; never write "production ready" while T-70/T-71 are
open; do not add dependencies.

When you are finished writing those two files, reply with a 5-line summary of what you
found and end your message with the single line: LOOP_RUN_DONE
EOF

# --- start the TUI in tmux ----------------------------------------------------
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "loop-free-pi: session '$SESSION' already exists; reusing it (tmux attach -t $SESSION)"
else
  tmux new-session -d -s "$SESSION" -x 200 -y 50 -c "$ROOT" \
    "npx -y free-pi-cli@latest $MODE" ||
    { echo "loop-free-pi: could not start tmux session" >&2; exit 1; }
  echo "loop-free-pi: started free-pi in tmux session '$SESSION' (attach: tmux attach -t $SESSION)"
fi

pane() { tmux capture-pane -p -t "$SESSION" 2>/dev/null; }

# --- wait until the input box is up -----------------------------------------
ready=0
for _ in $(seq 1 60); do
  sleep 2
  # The TUI is ready when its status/placeholder line is on screen. free-pi shows a
  # credits + model status bar and a `Try "..."` placeholder; older pi builds show an
  # input box. Match any of them rather than one build's exact wording.
  if pane | grep -qE 'credits left|Try "|/help for commands|esc to interrupt'; then ready=1; break; fi
done
if (( ! ready )); then
  echo "loop-free-pi: the TUI did not reach an input prompt in 120s. Last screen:" >&2
  pane | tail -20 >&2
  echo "loop-free-pi: attach and finish any sign-in, then re-run: tmux attach -t $SESSION" >&2
  exit 1
fi
sleep 2

# --- send the prompt --------------------------------------------------------
tmux load-buffer -b "loopprompt" "$PROMPT_FILE" || { echo "loop-free-pi: load-buffer failed" >&2; exit 1; }
tmux paste-buffer -b "loopprompt" -t "$SESSION"
sleep 1
tmux send-keys -t "$SESSION" Enter
echo "loop-free-pi: prompt sent ($(wc -l <"$PROMPT_FILE" | tr -d ' ') lines); waiting for the cycle to finish"

# --- wait for idle, then capture -------------------------------------------
start="$(date +%s)"
last_hash=""
stable=0
done_reason="idle"
while :; do
  sleep 5
  now="$(date +%s)"
  if (( now - start > TMO )); then done_reason="timeout"; break; fi
  screen="$(pane)"
  hash="$(printf '%s' "$screen" | sha256sum | cut -d' ' -f1)"
  if grep -q 'LOOP_RUN_DONE' <<<"$screen"; then done_reason="finished"; break; fi
  if [[ "$hash" == "$last_hash" ]]; then
    stable=$((stable + 5))
    if (( stable >= IDLE )); then done_reason="idle"; break; fi
  else
    stable=0
    last_hash="$hash"
  fi
done

pane >"$TRANSCRIPT"
echo "loop-free-pi: cycle ended ($done_reason) after $(( $(date +%s) - start ))s"
echo "loop-free-pi: transcript $TRANSCRIPT"

if (( KEEP )); then
  echo "loop-free-pi: session kept alive: tmux attach -t $SESSION   (kill: tmux kill-session -t $SESSION)"
else
  tmux kill-session -t "$SESSION" 2>/dev/null
fi

# --- what changed ----------------------------------------------------------
echo
echo "changed files:"
git status --short | sed 's/^/  /' || true
echo
echo "STATE.md and loop-run-log.md are the loop's memory: review them, then commit."
[[ "$done_reason" == "timeout" ]] && exit 1
exit 0
