# Loop Constraints

> Add rules below with `/constraints <rule>` in your agent.
> The `loop-constraints` skill reads this file at the start of every run.
> Constraints here are **binding** — the agent MUST follow them.

## Push & Merge
- Don't push before telling me
- Never auto-merge to main without human approval
- Always create a draft PR first; let me review before marking ready

## Paths
- Never edit .env, .env.*, auth/, payments/, secrets/, credentials/
- Never edit infrastructure configs without human approval

## Code
- Always run tests before proposing a fix
- Never disable tests to make CI green
- Never refactor unrelated code — one fix per run
- Max 3 fix attempts per item; escalate after
- Enforce the attempt limit mechanically: log each try to `loop-ledger.json` and run `loop-context --check` before retrying (see the `loop-guard` skill)

## Communication
- Always tell me what you're about to do before doing it
- Never close an issue or PR without my approval

## Budget
- If token spend hits 80% of daily cap, switch to report-only
- If loop-pause-all is active, exit immediately

---
<!-- Add your own rules below. Use plain English. The loop reads this verbatim. -->

## This repository (OneShotLink) — added by hand, binding

- **Read before you act:** `AGENTS.md` has the doc table (PRD, ARCHITECTURE, API,
  SECURITY, TESTING, DATABASE). `SECURITY.md` before anything touching secrets, crypto,
  sessions or auth. Do not guess at routes or record shapes.
- **The gates are Docker-shaped.** Ruby is not installed on the host; the backend suite
  runs as
  `docker run --rm --network=host -v "$PWD":/app -v ots-bundle:/bundle -e BUNDLE_PATH=/bundle -w /app ots-dev bundle exec rspec`.
  Frontend: `npm --prefix frontend test`, `npm --prefix frontend run typecheck`,
  `npm --prefix frontend run build`. Nothing is "verified" until one of those ran.
- **Redis: DB 15 only, never `FLUSHALL`.** `spec_helper` refuses a non-15 URL.
- **Copy rules (D-012, SECURITY.md):** the passphrase is an access gate, not a second
  encryption key. Never write "zero-knowledge". Never write "production ready" while
  T-70/T-71 are open.
- **Status of record:** `TASKS.md` (IDs are stable, do not renumber) and
  `replica/features.csv` (`clone` column). Update them in the same change that earns it.
- **No new gem or npm package** without a line in `docs/DECISIONS.md` and a check that it
  is canonical (`TECH_STACK.md` dependency policy).
- **Report, do not deploy.** This loop never runs `docker compose up` on a public host,
  never rotates keys, never restores a backup; those are human actions in `RUNBOOK.md`.
