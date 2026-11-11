# docs/loop/GOAL.md — what the loop is aiming at, and how to aim it

Human-owned. Read `AGENTS.md` §4 ("Goal-Driven Execution") first: this directory is
that rule wired into a machine.

## The shape

```
docs/loop/goal.criteria   the terminus: F* floor gates + T* target criteria
script/loop_verify.sh     runs them, prints GOAL: MET | NOT_MET | UNDEFINED
script/loop_observe.sh    live repo state + verdict, rendered as text
script/loop_prompt.sh     static instructions + that observation = the self-prompt
script/loop.sh            the controller: observe -> act -> verify -> record -> repeat
script/loop_selftest.sh   tests the controller itself with fake agents
script/loop_doctor.sh     is this machine able to run the loop? probes each agent
docs/loop/PLAN.md         plan memory the agent rewrites each iteration
docs/loop/LOG.md          append-only evidence: did / proof / next
```

## Floor vs target

- **Floor (`F*`)** — the repository's own gates, already documented in
  `TESTING.md`: Redis DB 15, backend RSpec in `ots-dev`, frontend Vitest,
  typecheck, build. They must stay green at every commit; that is the regression
  net the loop runs on.
- **Target (`T*`)** — whatever you are actually shipping next, expressed as
  observable behaviour. The loop only has work to do when at least one target is
  active. With no target the verifier says `GOAL: UNDEFINED` and the controller
  exits without touching anything — it will not invent a milestone.

## Arming a target

1. Pick the item: a `TODO`/`IN PROGRESS` row in `TASKS.md`, or a `KNOWN_ISSUES.md`
   ID, or the next milestone in `ROADMAP.md`.
2. Write down what "done" looks like as behaviour, in `goal.criteria`, `T*` ids.
   Example, for T-78: the landing route answers `200` with the approved copy, and
   the view renders the approved headline.
3. Run `script/loop_verify.sh`. It must be **red** on the new criteria, and still
   green on the floor. A target that is already green is not a target.
4. `script/loop.sh --dry-run` to read the exact prompt, then
   `script/loop.sh --until-goal`.
5. When it hits `GOAL: MET`, review the diff, then either add the next target or
   comment the finished one out with a dated note here.

## Deep gates (not run every iteration)

These are real but too slow or too infrastructure-shaped for a per-iteration
verdict. Run them before calling a milestone done:

```bash
script/preflight_selftest.sh                     # TLS + Compose go-live gate self-test
docker compose up -d && npm --prefix e2e test    # browser journeys (journey.mjs)
npm --prefix e2e run test:accounts
script/loadtest.rb 400 40                        # single-use invariant under load
HOST=https://your.domain script/preflight.sh     # the operator-only T-70/T-71 gate
```

If a deep gate is the thing a target promises, add it as a `T*` criterion anyway
and accept the slower iteration: correctness beats a fast loop.

## Budgets and stops

`LOOP_MAX_ITER` (default 1), `LOOP_MAX_ATTEMPT` (6), `LOOP_STALL_LIMIT` (2),
`LOOP_COMMIT=0` to stop the per-iteration commit.

`LOOP_AGENT` picks the executor (`pi`, `claude`, `codex`, `gemini`, `opencode`, or a
bare binary that takes `-p "<prompt>"`); `LOOP_AGENT_CMD` is the escape hatch for
anything else, and receives the prompt as its final argument. Check what is usable
on this machine first:

```bash
script/loop_doctor.sh            # prerequisites, the verdict, one probe per agent
script/loop_doctor.sh --slow     # 120s probes when a CLI is slow to start
```
Exit codes: `0` met / blocked / undefined, `1` rule violation or crash, `3`
stalled, `4` attempts exhausted, `5` iteration budget exhausted.

State lives in `.loop/` (git-ignored): `state.env`, transcripts of every iteration,
and the last verdict. Read `docs/loop/LOG.md` before re-running after a stop.
