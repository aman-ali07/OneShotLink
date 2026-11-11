# LOG — append-only memory of the loop

One entry per iteration, plus human notes. Newest at the bottom. Never rewrite
history; append a correction instead.

Machine-written entries:

```
## YYYY-MM-DDTHH:MM iter N - verify P/T
- did: <agent REPORT line>
- proof: <verdict + transcript path>
- next: <agent NEXT line>
- notes: stall=<n> attempt=<n>
```

Human entries: `## YYYY-MM-DDTHH:MM — human: <decision>`

---

## 2026-11-11T00:20 — human: loop engineering installed

- did: added a goal-directed controller to this repo, adapted to its own gates:
  `script/loop.sh` (controller, persistent state in `.loop/`, budgets, stall
  detection, per-iteration commit, rule guard), `script/loop_verify.sh` (the
  verdict, reads `docs/loop/goal.criteria`), `script/loop_observe.sh` (live state +
  open `TASKS.md` rows), `script/loop_prompt.sh` (self-prompt), and
  `script/loop_selftest.sh` (controller tests with fake agents).
- proof: `script/loop_verify.sh` -> floor 5/5 green, `GOAL: UNDEFINED` (no target
  armed, by design); `script/loop_selftest.sh` -> all cases pass
- next: arm a T* target in `docs/loop/goal.criteria`; T-78 (landing route) is the
  only open TODO in `TASKS.md`
- notes: the floor criteria are the repo's existing gates from `TESTING.md`
  (Redis DB 15, RSpec in `ots-dev`, Vitest, typecheck, build) so the loop cannot
  drift from the documented quality bar. Heavy gates (`preflight_selftest.sh`,
  Compose E2E, load test) are listed in `docs/loop/GOAL.md` as deep checks rather
  than run every iteration.

## 2026-11-12T00:35 — human: armed T-78 and added an agent doctor

- did: armed the landing target in `docs/loop/goal.criteria` (T1 route/spec, T2 the
  approved hero headline in the built bundle), wrote the first plan entry in
  `docs/loop/PLAN.md`, and added `script/loop_doctor.sh` (prerequisites, verdict,
  one probe per agent). `script/loop.sh` now supports `pi|claude|codex|gemini|
  opencode` presets plus `LOOP_AGENT_CMD` for anything else.
- proof: `script/loop_verify.sh` -> `VERIFY: 5/7 (floor 5/5, target 0/2)`,
  `GOAL: NOT_MET` — the target is honestly red. `script/loop_doctor.sh` -> all
  prerequisites READY, no agent READY (each with the reason and the fix).
- next: log in to one agent (`pi` -> /login, or `claude`), re-run the doctor, then
  `LOOP_AGENT=pi script/loop.sh --until-goal`
- notes: the doctor's probe originally grepped for a literal token, which matched
  the CLI's own echo of the prompt and falsely reported codex as READY. The probe
  now asks for a computed token (PROBE_<17+25>) so an echo cannot pass.

## Decisions

- Floor (`F*`) vs target (`T*`) split: the loop refuses to run when only the floor
  is active, because "keep it green" is not a goal and this repo is already green.
- The goal and the verifier are human-owned and hashed by the controller; the
  agent may not move them. Unlike `script/check.sh` in a bare scaffold, there is no
  separate hygiene gate here: the floor criteria already are the repo's gates.
- One commit per iteration, `chore(loop): iter N - verify P/T`, so a bad iteration
  is one `git revert` and thrash shows up in `git log`.
- Criteria assert approved copy, not file existence, so neither a stub page nor a
  self-written trivially-passing spec can satisfy a target.
