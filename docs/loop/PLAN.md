# PLAN — plan memory for the loop

Not a backlog: `TASKS.md` is the status of record, and `docs/loop/goal.criteria`
decides when work is done. This file is the **plan phase's** scratchpad, rewritten
by the agent each iteration so the next iteration inherits its decisions.

Rules:

- `## Now` holds at most 3 items. Item 1 is what the current iteration is doing,
  and names the criterion and the TASKS.md ID it advances.
- Done items move to `## Done` with the proof (spec name or command).
- Anything needing a human decision goes to `## Blocked` with the exact question.
- Half-finished work: write the remainder explicitly, so a stall is recoverable.

## Now

- [ ] (empty — the first armed iteration writes this from the failing T* criterion)

## Blocked

- [ ] **Human: arm a target.** `docs/loop/goal.criteria` has floor gates only, so
      `script/loop_verify.sh` reports `GOAL: UNDEFINED` and `script/loop.sh` exits
      without doing anything. Pick the next item (T-78 is the only `TODO` in
      `TASKS.md` today), write it as T* behaviour criteria, confirm they are red,
      then run the loop. `docs/loop/GOAL.md` has the procedure.

## Done

- [x] Loop engineering installed: controller, observation, self-prompt, verifier,
      rule guard, self-test (proof: `script/loop_selftest.sh`)
