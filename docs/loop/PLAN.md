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

- [ ] **T-78 / T1: make `/landing` answer with the landing page.** Read
      `replica/launch/landing.md` §1 (hero) first; the route, the view and
      `spec/integration/landing_spec.rb` do not exist yet, so T1 is red because the
      spec file is missing. Follow AGENTS.md §1 doc table: DESIGN_SYSTEM.md before
      styling, API.md if server behaviour changes.
- [ ] **T-78 / T2: the built SPA must carry the approved hero headline** — the exact
      string from `replica/launch/landing.md` §1, including the em dash. Wiring the
      route without the approved copy leaves T2 red.

## Blocked

- [ ] **Human: give the loop an agent.** `script/loop_doctor.sh` found no answering
      agent on this machine (pi/claude need an interactive login, codex needs an
      upgrade, gemini/opencode are unauthenticated). Until one answers,
      `script/loop.sh` will stop at iteration 1 with "agent exited N". See the
      fix list the doctor prints.

## Done

- [x] Loop engineering installed: controller, observation, self-prompt, verifier,
      rule guard, self-test (proof: `script/loop_selftest.sh`)
