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

## Decisions

- Floor (`F*`) vs target (`T*`) split: the loop refuses to run when only the floor
  is active, because "keep it green" is not a goal and this repo is already green.
- The goal and the verifier are human-owned and hashed by the controller; the
  agent may not move them. Unlike `script/check.sh` in a bare scaffold, there is no
  separate hygiene gate here: the floor criteria already are the repo's gates.
- One commit per iteration, `chore(loop): iter N - verify P/T`, so a bad iteration
  is one `git revert` and thrash shows up in `git log`.
