# Loop State — OneShotLink

Last run: 2026-11-11T20:30:00Z (L1 triage, report-only). **Budget: 2 of 2 daily runs used.**

## High Priority (loop is acting or waiting on human)

None. B1 (account deletion) is committed (`09353c2`), CI `43086869846` green,
`main == origin/main`, tree clean.

## Watch List

- **Specs share Redis DB 15 with any live server.** `spec/spec_helper.rb:32,36` `flushdb`s
  DB 15; a concurrent `puma` on that DB made a run report **66 examples instead of 109**
  (exit 0, silently lost). Next action: refuse to run when DB 15 is in use, or per-run DB.
  Effort **S**, needs approval (test infrastructure).
- **`DeleteAccount` is not transactional.** `logic/delete_account.rb:20-29` makes 5
  `Store.redis` calls (one per receipt, in a loop) with no `MULTI`, unlike conceal/reveal
  (`models/secret.rb:71`); a mid-way failure leaves partial state. Next action: wrap in
  `Store.redis.multi` + an all-or-nothing spec. Effort **S**.
- **Stale `TASKS.md` statuses.** `TASKS.md:79` (R-11) still says "no account deletion" while
  `replica/deploy.md:29` marks B1 **done**; `:73-75` (R-05/06/07) are `IN PROGRESS` though
  criteria are met (`logic/sign_in.rb` ships sessions; `secrets_api_spec.rb:92` race, `:107`
  expiry, `:71` passphrase; parity 11/11). Next action: reconcile. Effort **XS**, docs only.
- **Stale spec counts.** `TASKS.md:17,160` say 92, `KNOWN_ISSUES.md:6` says 94; actual
  **109**. Effort **XS**, docs only.
- **No committed test for account deletion.** `deleteAccount()` + dashboard form covered
  only by an ad-hoc browser run. Next action: one Vitest case + a delete step in
  `e2e/accounts.mjs`. Effort **S**.
- **Pre-existing state, unchanged and already documented** — not new findings:
  B2–B6 open (`replica/deploy.md:26-31`), T-70/T-71 operator-only with 19 gates verified
  and exactly those 2 open (`PRODUCTION_READINESS.md`), and the 14 open KNOWN_ISSUES
  (K-31 S2; K-10/11/12/14/15/17/21 S3; K-20/22/24/27/30/35 S4). Read the source docs; this
  loop adds nothing to them and proposes no code for T-70/T-71.

## Recent Noise (ignored this run)

- **Loop tooling broke the rebrand sweep, now fixed.** `sweep.py` flagged
  `.loop-runs/*-transcript.txt` with 10 hits of `onetime-secret` — the *directory name* in TUI chrome, not product copy — and
  `.loop-runs/` was **not** gitignored. Added `.loop-runs/` to `.gitignore`, deleted the
  regenerable transcript; sweep is Clean. `sweep.py` walks the filesystem and does **not**
  honour `.gitignore`, so any run artifact can fail this gate.
- `script/loop-free-pi.sh` — untracked TUI tooling, not reviewed.
- `3a6c531` carries the first `app.rb` hunk; `09353c2` is the complete change.

## State Updates

- HEAD `09353c2`, `main == origin/main`, CI green. Gates re-run cheapest-first with DB 15
  empty and `:3000` free: `npm test` **9/9** (exit 0), `typecheck` **exit 0**, `rspec`
  **109 examples / 0 failures**. DB 15 read 2 immediately after the suite but was **0 on
  re-check** and `--scan` was empty — expired keys awaiting lazy expiry, not leaked state.
  Parity **63.0** (11/11), sweep clean.
- Redis on **6399** answered `PONG`; `spec_helper.rb:5` defaults to `/15` and `:29-30`
  **refuses to run** on any other DB. After the suite, DB 15 is absent (empty) and `db0`
  (15 keys belonging to something else) is untouched — the suite isolates itself correctly.
- Timestamps are **UTC**. Verify DB 15 and `:3000` are clear before running specs.
- Disclosed loop deviations: one temporary `app.rb` backtrace log (restored, no residue),
  one scratch-spec deletion, and the six prescribed reads were not the first tool calls. No
  code, commit, push or PR from the loop.

---
Run log: `loop-run-log.md`
