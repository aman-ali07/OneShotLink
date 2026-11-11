#!/usr/bin/env bash
# frozen_string_literal: true
#
# Doctor: is this machine able to run the loop right now?
#
# The loop is only as real as the agent it drives, so probe each supported agent
# CLI once with a tiny prompt and report which ones actually answer.
#
# The probe asks for a token the model has to COMPUTE (PROBE_<17+25>), because a
# CLI echoes the prompt back and a literal token would match its own echo. That
# false positive was observed with `codex` before this was fixed.
#
#   script/loop_doctor.sh            # probe every installed agent (30s each)
#   script/loop_doctor.sh --slow     # 120s per probe (a CLI may be slow to start)
#   script/loop_doctor.sh --only pi  # probe one
#
# Exit 0 if at least one agent answers, 1 otherwise. Read-only: no writes, no commits.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

TMO=30
ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --slow) TMO=120; shift ;;
    --only) ONLY="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "doctor: unknown arg: $1" >&2; exit 2 ;;
  esac
done

ok()   { printf '  \033[32m[READY]\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m[NO]\033[0m    %s\n' "$1"; }
note() { printf '           %s\n' "$1"; }
info() { printf '\n== %s ==\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

PROMPT_PROBE='What is 17 + 25? Reply with exactly PROBE_<the number> and nothing else.'
EXPECT='PROBE_42'

agent_cmd() {  # $1 agent name -> prints the argv prefix for that agent
  case "$1" in
    pi)       printf '%s\n' "pi -p" ;;
    claude)   printf '%s\n' "claude -p" ;;
    codex)    printf '%s\n' "codex exec --skip-git-repo-check" ;;
    gemini)   printf '%s\n' "gemini --skip-trust -p" ;;
    opencode) printf '%s\n' "opencode run" ;;
    *) return 1 ;;
  esac
}

# probe <agent>: run it once, echo "ready" or a short reason
probe() {
  local agent="$1" out rc prefix
  prefix="$(agent_cmd "$agent")" || { echo "unsupported"; return; }
  # shellcheck disable=SC2086
  out="$(timeout "$TMO" $prefix "$PROMPT_PROBE" 2>&1)"; rc=$?
  if (( rc == 124 )); then echo "timeout after ${TMO}s (try --slow)"; return; fi
  if grep -q "$EXPECT" <<<"$out"; then echo "ready"; return; fi
  echo "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -vE '^\s*$' | tail -n 2 | tr '\n' ' ' | cut -c1-160
}

info "Loop prerequisites"
(( BASH_VERSINFO[0] >= 4 )) && ok "bash ${BASH_VERSION%%-*}" || bad "bash ${BASH_VERSION} (needs 4+)"
have git && ok "git $(git --version | awk '{print $3}')" || bad "git missing"
have docker && ok "docker $(docker --version | sed 's/Docker version //; s/,.*//')" || bad "docker missing - floor gate F2 needs it"
have redis-cli && ok "redis-cli" || bad "redis-cli missing - floor gate F1 needs it"
have npm && ok "npm $(npm --version)" || bad "npm missing - floor gates F3-F5 need it"

info "The goal"
v="$(script/loop_verify.sh --quiet 2>&1)"; vrc=$?
printf '%s\n' "$v" | sed 's/^/  /'
case "$vrc" in
  0) note "GOAL: MET - nothing to do until a new target is armed." ;;
  2) note "No T* target armed: the loop will refuse to work. Arm one (docs/loop/GOAL.md)." ;;
  *) note "A target is armed and red: the loop has work to do." ;;
esac

info "Agents (one probe each, ~${TMO}s max)"
ready_agents=()
for a in pi claude codex gemini opencode; do
  [[ -n "$ONLY" && "$ONLY" != "$a" ]] && continue
  if ! have "$a"; then bad "$a - not installed"; continue; fi
  res="$(probe "$a")"
  if [[ "$res" == "ready" ]]; then
    ok "$a"; ready_agents+=("$a")
  else
    bad "$a - $res"
  fi
done

info "Verdict"
if (( ${#ready_agents[@]} > 0 )); then
  a="${ready_agents[0]}"
  echo "  ${#ready_agents[@]} agent(s) answer: ${ready_agents[*]}"
  echo
  echo "  Start the loop:"
  echo "    LOOP_AGENT=$a script/loop.sh --dry-run   # read the exact prompt first"
  echo "    LOOP_AGENT=$a script/loop.sh --until-goal"
  exit 0
fi

cat <<EOF
  No agent answered, so the loop cannot act. One fix per agent:

    pi        run \`pi\` once and /login (or set a provider API key). A nested
              \`pi -p\` cannot use a credential held by another pi session.
    claude    run \`claude\` once and log in; \`claude -p\` then works unattended.
    codex     npm i -g @openai/codex@latest - this build rejects its configured
              model ("requires a newer version of Codex").
    gemini    needs Google auth/project setup before headless use.
    opencode  provider returned 403; check its auth.

  Anything that takes the prompt as its last argument works too:

    LOOP_AGENT_CMD='my-agent --prompt' script/loop.sh --until-goal

  Meanwhile the machinery is usable by hand: \`script/loop_verify.sh\` gives the
  verdict, \`script/loop.sh --dry-run\` shows exactly what an agent would be told.
EOF
exit 1
