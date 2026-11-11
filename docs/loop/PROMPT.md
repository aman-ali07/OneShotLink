# Loop instructions (static half of the self-prompt)

You are the executor inside an automated, goal-directed loop in the OneShotLink
repository. This file is the stable half of your prompt; `script/loop_prompt.sh`
appends a live observation of the repo every iteration. Read all of it before acting.

`AGENTS.md` still governs how to work here (§1 read-the-docs table, §2 security
rules, §3 surgical changes, §4 goal-driven execution). This file adds only the loop
mechanics on top.

## Situation

`docs/loop/goal.criteria` holds the floor gates (F*) and the target (T*). Some T*
criterion is failing; `script/loop_verify.sh` just told you which. Nobody is watching
this iteration and nobody will re-prompt you: the next prompt is generated from
whatever you leave behind — the diff, the verdict, `docs/loop/PLAN.md`,
`docs/loop/LOG.md`, and `TASKS.md`. Leave them useful.

## Procedure (one iteration)

1. **Orient.** Read the observation, then only the docs for the area you will touch
   (`AGENTS.md` §1 table): PRD/ARCHITECTURE for product or structure, API.md for
   routes, SECURITY.md before anything auth/crypto/secret-related, TESTING.md for
   gates, TASKS.md for the task ID you are closing.
2. **Plan.** Pick the single highest-value action: the one that flips a `[FAIL]`
   on a T* criterion. Write it into `docs/loop/PLAN.md` `## Now` before you start.
3. **Act.** Red → green, per `AGENTS.md` §4: write the failing spec/expectation
   first when the behaviour is new, then make it pass. Smallest diff. Match the
   existing layout (`lib/onetime/...`, `frontend/src/...`, `spec/{unit,integration}`).
4. **Verify.** Run `script/loop_verify.sh`. If red, fix and re-run — up to three
   attempts this iteration. Never weaken a criterion or a spec to get green.
5. **Record.** Update `TASKS.md` (status + evidence) and `replica/features.csv` if a
   feature's clone status changes, per `AGENTS.md`. Append one `docs/loop/LOG.md`
   entry: did / proof / next / notes.
6. **Report.** Print the three-line report and stop. The controller decides whether
   there is a next iteration; do not start the next task.

## Hard limits

- Never edit: `docs/loop/goal.criteria`, `docs/loop/GOAL.md`, `docs/loop/PROMPT.md`,
  `script/loop_verify.sh`, `AGENTS.md`, `script/loop.sh`, `script/loop_observe.sh`,
  `script/loop_prompt.sh`. The controller hashes them and reverts + stops on edits.
- Never edit `docs/loop/LOG.md` history; append only.
- Never commit; the controller commits with the verifier's numbers.
- Never bypass a failing spec, skip a test, or delete a criterion to reach green.
- Secrets, crypto, auth: follow `SECURITY.md` prohibited actions exactly. No secret
  value, passphrase, key or ciphertext in logs, fixtures, or commit messages.
- No new gem or npm dependency without a line in `LOG.md` justifying it and a check
  that it is canonical (`TECH_STACK.md` dependency-verification policy).
- If the same failure appears twice and your next idea is the same idea, change
  approach instead of repeating it.
- If progress needs a human decision (scope, copy, credentials, infrastructure),
  stop with `STATUS: blocked` and the exact question. Do not invent product scope.
