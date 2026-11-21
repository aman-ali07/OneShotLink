# Engineering quality review — OneShotLink

**Date:** 2026-11-21
**Scope:** the whole repository — frontend SPA, Ruby backend, Redis data layer, dependencies,
configuration and CI. No behaviour, API shape or persisted data shape was changed.

## 1. Method

Four `.claude/agents/` quality specialists ran in parallel: **frontend**, **backend**,
**database**, **dependency/config**. Each candidate for removal was verified with a repo-wide
grep before being touched; public CLI entry points and spec-only helpers are not dead code.
`@stageshow` was used to coordinate the implementation; the still is at
`docs/quality-review-posture.html` / `.png` (1030×560, 0 render errors).

## 2. Removals (dead code and artifacts)

| Item | Evidence | Action |
| --- | --- | --- |
| `Backup.collect_receipts`, `Backup.collect_customers` | only definitions; `export` routes all non-secret sections through `collect_typed` | deleted |
| `Store.flush_test_db!` | no callers; specs call `redis.flushdb` directly | deleted |
| `Models::SecretRequest.fetch_submission` | no callers; reveal reads Redis directly | deleted |
| Gems `i18n`, `semantic_logger` | zero references in `lib/`, `bin/`, `spec/`; `TECH_STACK.md` already said "not wired" | removed from `Gemfile`, lockfile regenerated with `bundle lock --local`, `TECH_STACK.md` corrected |
| `DEBUG_MAIN` / `DEBUG_ERRORS` dumps in `e2e/requests.mjs` | printed the DOM containing the submitted secret into CI logs | deleted; plain timeout used instead |

## 3. Refactors (maintainability only)

- `Config::LIMIT_SCOPES` is now the single source of truth for rate-limit scopes used by both
  boot validation and `rate_limit`; an unknown scope now raises instead of silently borrowing
  the reveal limit. `Config#[]` no longer has a no-op ternary.
- Frontend: `dateTimeLabel()` in `lib/format.ts` replaces two byte-identical
  `Intl.DateTimeFormat` helpers in `DashboardView`; `PublicConfig` is re-exported from `api.ts`
  instead of being re-derived; the `sharedOn` alias in `RevealView` was removed; the redundant
  wildcard `*.vue` ambient shim was deleted (verified by a clean `vue-tsc` run).
- CLI admin commands (`ots list`, health secret count) use `SCAN` instead of blocking `KEYS`.
- `DATABASE.md`, `SECURITY.md` and `SECURITY_AUDIT.md` were reconciled with the current
  `META_VERSION = 3` (the MAC now covers `ciphertext`) and the 30-day receipt retention; a
  stale `SISMEMBER` claim and the missing `request_key` MAC field were corrected.
- `.env.example` now documents `OTS_URL`, `OTS_ALLOW_INSECURE`, `WEBHOOK_ALLOW_PRIVATE`
  (testing-only) and `VITE_API_PROXY`; CI now runs the previously ungated `test:mobile` journey.

## 4. Verification (all executed after the changes)

| Gate | Result |
| --- | --- |
| Backend suite, 30 spec files | **303 examples, 0 failures** in one run (three-batch confirmation 138 + 73 + 92) |
| `npm --prefix frontend run test` | **28 passed** (5 files) |
| `npm --prefix frontend run typecheck` | clean (no wildcard SFC shim) |
| `npm --prefix frontend run build` | clean, built in 7.35 s |
| 8 browser journeys (journey, accounts, requests, file, webhooks, states, mobile, a11y) | **PASS**, 0 page/console errors |
| `bash script/test-examples.sh` | all SDK quickstarts pass |
| `docker compose config --quiet` | OK |
| Debug-artifact grep (`DEBUG_`, `console.log`, `binding.pry`) in first-party source | clean |

## 5. Unresolved issues (documented, not silently deferred)

1. **REQUIRES SERVER OPERATOR — T-70 / T-71.** Real TLS hostname and the host Redis firewall
   need target-host access; only local rehearsals exist. No launch claim is made.
2. **REQUIRES HUMAN APPROVAL — untracked product-engineering artifacts.** `docs/*-posture.html/.png`
   and several audit reports are untracked. They are intentional deliverables from prior
   coordination objectives, so they were **kept**, not deleted. Someone must decide whether to
   commit them or add explicit ignore rules; they are already excluded from the Docker build
   only by extension of the current `.dockerignore` (no `docs/` rule yet).
3. **ACCEPTED — repeated best-effort cleanup rescue.** Four sites (`reveal_secret`,
   `burn_secret`, `secret_requests`, `app.rb#peek_payload`) log a class-only warning and count a
   failure. Their messages and scopes differ slightly; extracting a generic helper would hide
   that context for little gain. Left as-is.
4. **ACCEPTED (design decision) — two timestamp formats.** `formatTimestamp()` includes a
   timezone name and is used on reveal pages; `dateTimeLabel()` uses medium/short styles for
   receipts and deliveries. Unifying them is a copy/design choice, not a code defect.
5. **BLOCKED — no public production verification.** No live restore, TLS chain or rotation was
   attempted; those require an operator and are classified in `GO_LIVE_REMINDER.md`.

## 6. Assessment

Code-level engineering quality is **GO**: dead code removed, duplication consolidated, build and
all test gates green. Public launch remains **NO-GO** until the operator-owned security gates
produce target-host evidence.
