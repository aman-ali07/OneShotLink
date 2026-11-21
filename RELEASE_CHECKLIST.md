# Release checklist — OneShotLink

**Final verdict (2026-11-21): NO-GO for public launch.** Code-level readiness is **GO** for
every in-repo testable requirement, **except** the fresh-clone/CI-reproduction gate, which stays
**BLOCKED** until a human commits/tags the staged release tree. Mandatory operator and human
gates are open. This is the signable companion to `GO_LIVE_REMINDER.md`; no deploy has been
performed.

Classifications: **FIXED AND VERIFIED** (command output in this repo) · **REQUIRES HUMAN APPROVAL**
(person must review/decide/sign) · **REQUIRES SERVER OPERATOR** (target host needed) ·
**BLOCKED** (cannot be closed here; gates launch).

Six parallel release agents (`release-product`, `release-security`, `release-frontend`,
`release-backend`, `release-infra`, `release-docs`) audited the tree; their findings were
re-read against source and are reflected below. `@stageshow` coordination still:
`docs/release-readiness-posture.html` / `.png` (1030×560, 0 render errors).

## 1. Critical features and user journeys

| Requirement | Classification | Evidence |
| --- | --- | --- |
| Create → link → preview → reveal once → gone | **FIXED AND VERIFIED** | `e2e/journey.mjs`: `ok: true`, zero page/console errors; `secrets_api_spec.rb` 8-way race yields exactly one 200 |
| Passphrase path (wrong doesn't consume, 8-byte floor, budget) | **FIXED AND VERIFIED** | `e2e/journey.mjs` wrong/right assertions; `qa_acceptance_spec.rb` concurrent budget burst 2×401 / 6×429, record intact |
| File secrets (encrypted, download, replay 404) | **FIXED AND VERIFIED** | `e2e/file.mjs`: `{"ok":true,"filename":"fixture.bin","bytes":8,"replay":404,"errors":[]}` |
| Accounts: signup → receipt → signout → signin → delete | **FIXED AND VERIFIED** | `e2e/accounts.mjs`: `accounts journey ok` (fresh stack, elevated test limits) |
| Owner receipts, statuses, burn, already-viewed/destroyed | **FIXED AND VERIFIED** | `e2e/states.mjs` burn→destroyed; `receipt_lifecycle_spec.rb`; `DashboardView.vue` status + Destroy control |
| Incoming request → respond → reveal once | **FIXED AND VERIFIED** | `e2e/requests.mjs`: `ok: true`; 409/taken asserted |
| Webhook create → event → signed delivery listing | **FIXED AND VERIFIED (code)** | `e2e/webhooks.mjs`: `ok: true`, signing secret shown once, `secret.created` in deliveries; external signed delivery is unit-proven only |
| All 11 `must` rows of `replica/features.csv` implemented | **FIXED AND VERIFIED** | `features.csv` rows 2–12 `clone=yes`; working-tree parity **80.8/100, 11/11 must-haves** (`parity.py` re-run this pass; row 19 theme corrected to `partial`); committed HEAD figure 66.7/100 — commit is a human gate. Row 31 (file/image secrets) corrected to `partial`: binary files ≤512 KiB ship, image preview/multipart do not |
| Webhook worker scheduled and monitored on target | **REQUIRES SERVER OPERATOR** | K-46: `script/webhook-worker.sh` + `docs/ops/webhook-worker.md` ready; no cron/systemd/alert on a server — webhooks stay off |
| Deferred/accepted gaps recorded rather than silently marked done | **FIXED AND VERIFIED** | `replica/features.csv` rows 15–33 (`no`/`partial` with notes: i18n, orgs/RBAC/SSO, MFA, domains, email jobs, client-side encryption). Row 31 corrected to `partial` this pass: binary files ≤512 KiB ship, image preview/multipart do not (no invented parity) |
| `AUTH_MODE=full` fails closed, never silently degrades | **FIXED AND VERIFIED** | `errors.rb` `NotConfigured`→501; `secrets_api_spec.rb` full-mode 501; `API.md` §1; no silent fallback found |
| E2EE / zero-knowledge non-claim | **FIXED AND VERIFIED** | Negation-only grep recorded in `SECURITY_AUDIT.md` §7; passphrase is an access gate (D-012); no affirmative claim in shipped copy |
| Primary copy action exercised in a real browser | **FIXED AND VERIFIED (this pass)** | `e2e/journey.mjs` now clicks `Copy link` and `Copy secret` and asserts the `role=status` feedback; `node journey.mjs` → `ok: true`, zero errors |

## 2. Automated tests, security and build

| Requirement | Classification | Evidence |
| --- | --- | --- |
| Backend suite | **FIXED AND VERIFIED (this pass)** | 30 spec files, one container per file (host OOM limit) → **307 examples, 0 failures** (`/tmp/opencode/final-per-file2.log`, `TOTAL_EXAMPLES=307`; one earlier run hit the DB-15 guard from a stale client, retried clean) |
| Frontend unit/component tests | **FIXED AND VERIFIED (this pass)** | `npm --prefix frontend run test` → **35 passed (8 files)** (`/tmp/opencode/final-frontend-test2.log`); an earlier parallel run timed out 3 files under load, re-run clean |
| TypeScript typecheck | **FIXED AND VERIFIED** | `vue-tsc --noEmit` clean (including new `siteCta`/`DashboardView` tests) |
| Production build | **FIXED AND VERIFIED (this pass)** | `npm --prefix frontend run build` → clean, hashed assets JS 253.72 kB / CSS 23.00 kB in `public/app` (`/tmp/opencode/final-frontend-build.log`) |
| 8 browser journeys desktop + 320/375 px | **FIXED AND VERIFIED (this pass)** | all eight `e2e/*.mjs` scripts → PASS against the local Puma stack (`/tmp/opencode/final-e2e*`, earlier matrix; `journey.mjs` re-run green with new copy assertions) |
| Accessibility WCAG 2.2 AA + best-practice | **FIXED AND VERIFIED** | `e2e/a11y.mjs` → **0 violations across 4 viewports**, `{"negative-control-image-alt":"detected":true}` proves the gate is non-vacuous |
| Security S1/S2 closure | **FIXED AND VERIFIED** | `SECURITY_AUDIT.md` §3/§13/§14: all S1/S2 fixed with red→green specs; no open S1/S2 |
| Security invariants (atomic consume, verify-before-delete, no plaintext, CSRF/origin, uniform 404, metrics token, SSRF guard) | **FIXED AND VERIFIED** | re-verified by `release-security` against current source; E2EE/zero-knowledge non-claim holds (negation-only grep) |
| SDK examples | **FIXED AND VERIFIED** | `bash script/test-examples.sh` → `All SDK examples passed against http://127.0.0.1:3015` |
| Brand / dependency gates | **FIXED AND VERIFIED** | `script/brand-sweep.sh` → Clean; `bundler-audit` + `npm audit --audit-level=high` green in CI |
| Protected-path review (crypto.rb, app.rb, compose.yaml) | **REQUIRES HUMAN APPROVAL** | diffs re-read in `SECURITY_AUDIT.md` §14.5; sign-off below unsigned |
| Residual S3/S4 findings and waivers have an owner | **FIXED AND VERIFIED (dispositions)** | `SECURITY_AUDIT.md` §19 residuals SA-60…SA-69; protected-path proposals (PUMA_BIND, `__Host-` cookie, preflight port, Dockerfile script set, digest pins) are **proposed, not applied**; waivers K-49 (9 high e2e dev advisories), K-50 (5 moderate dev-only), K-51. No open S1/S2; the one open S3 (SA-61, missing `__Host-` cookie prefix) is **proposed, not applied**, pending protected-path approval |
| Dependency audits scoped correctly | **FIXED AND VERIFIED** | `bundler-audit` 1406 advisories → none; frontend production `npm audit` → 0; dev-only advisories waived with evidence in K-49/K-50 (`SECURITY_AUDIT.md` §19.1). `npm audit --audit-level=high` in CI covers production trees only |

## 3. Data, migrations, environment and deployment config

| Requirement | Classification | Evidence |
| --- | --- | --- |
| Redis key/TTL shapes and data-layer invariants | **FIXED AND VERIFIED** | `DATABASE.md` reconciled to `META_VERSION=3`; `ops_spec` + `qa_unit_acceptance_spec` cover CAS, two-key consume, key shapes |
| Migration substrate: idempotent marker, dry-run, no record rewrites | **FIXED AND VERIFIED** | `bin/ots migrate --dry-run` + `migration_spec.rb`; `SET NX` marker, newer-version refusal |
| Backup confidentiality (0600), allowlist, `schema:version` pre-flight | **FIXED AND VERIFIED** | `ops_spec.rb` round-trip + corrupt-marker rejection; `backup.rb` validates before any write |
| Backup/restore drill | **FIXED AND VERIFIED (isolated only)** | `script/restore-drill.sh` → `RESTORE DRILL PASSED`, throwaway container/DB 15 (object, spent link, schema marker). Receipt/customer-index restoration is unit-proven (`ops_spec.rb`), not drill-proven; live restore and the off-host encrypted backup schedule/RPO/RTO remain **REQUIRES HUMAN APPROVAL** (`PRODUCTION_READINESS.md`) |
| Migration rehearsal and rollback | **FIXED AND VERIFIED (forward only)** | `migration_spec.rb`: dry-run writes nothing, idempotent apply, no record rewrite, corrupt/newer marker refused; format-1/2 backup readers in `backup.rb` with schema pre-flight. No `down` migration exists and no format-1 **positive** restore spec exists (documented gap); deploy rollback = code revert + `bin/ots restore` (`RUNBOOK.md`) |
| Environment variables complete and consistent | **FIXED AND VERIFIED** | `config_spec.rb` drift guards compare `Config::DEFAULTS`, compose interpolations, DEPLOYMENT.md and `.env.example`; 47-key free-tier contract in `deploy/free-tier/env.production.example` verified by `deploy/free-tier/verify.sh` (15 static checks). Placeholders `CHANGE-ME` for `SECRET`/`REDIS_PASSWORD` rejected at boot (`config.rb`); `VITE_API_PROXY` aligned to `3100`; `OTS_PASSWORD` documented as CLI-only. Note: `REPLACE_*` host placeholders fail at connect time, not boot (documented limitation) |
| Fresh-clone build and CI reproduce the documented gates | **BLOCKED (human commit/tag)** | A HEAD-only snapshot fails typecheck with **13 TS2307 errors** (`frontend/src/lib/{authMode,clipboard,config,format}.ts` absent at HEAD); HEAD `.env.example` still has localhost Redis. Current git state at final check: `HEAD=741e71f`, **227 files staged, 11 unstaged, 0 untracked** — the release work is staged but **not committed or tagged**. A full working-tree snapshot passes npm ci/test/build, RSpec sample, journey and axe (`OPEN_SOURCE_READINESS.md` §3/§4). Human must commit the final index (including the 11 unstaged edits), tag, and re-run CI from a clean clone |
| Container build and hardening | **FIXED AND VERIFIED** | `Dockerfile`: pinned lockfiles, non-root UID 10001, read-only rootfs; `compose.yaml`: `cap_drop: ALL`, internal Redis net, named volumes. `.dockerignore` excludes `.git`, `.env*`, `node_modules`, build output and screens; Redis intentionally keeps SETUID/SETGID/CHOWN caps for its entrypoint (documented exception) |
| Accepted single-instance topology decision | **FIXED AND VERIFIED (documented)** | `DEPLOYMENT.md` §"single Redis is a single point of failure; Sentinel/Cluster out of scope" — a deliberate deviation from the general "Compose is not production" guidance, not an undiscovered defect. Digest-pinned base images remain a protected-path proposal (K-51) |
| CI gates | **FIXED AND VERIFIED** | `.github/workflows/ci.yml`: security, backend, frontend, container + 8 journeys, SDK examples, load, preflight self-test. Known wart: duplicate `test:mobile` step at lines 125–126 (protected path, proposal only); `e2e` audit not gated (K-49 waiver) |
| Preflight self-test and TLS rehearsal | **FIXED AND VERIFIED (local)** | `script/preflight_selftest.sh` → `PREFLIGHT SELFTEST PASSED (5 assertions)`; `script/tls-rehearsal.sh` → `PREFLIGHT PASSED (1 skipped)` — app-side only, not target-host evidence (T-70) |
| Release-config proposals left unapplied | **REQUIRES HUMAN APPROVAL** | Protected paths: K-51 digest pins, SA-60 `PUMA_BIND`, SA-61 `__Host-` cookie, SA-66 preflight port validation, SA-69 Dockerfile script set. Also no lint runner and untriaged generated stills (`ENGINEERING_REVIEW.md` §4) |
| Release artifact committed/tagged | **REQUIRES HUMAN APPROVAL** | `main` still at HEAD `741e71f`; 227 files staged + 11 unstaged at final check, no commit/tag identifies the release. Agents did not commit, push or tag |
| T-70 TLS on a real hostname | **REQUIRES SERVER OPERATOR** | `HOST=https://<host> script/preflight.sh` exits 0 on target — not run |
| T-71 Redis host firewall | **REQUIRES SERVER OPERATOR** | target preflight reports `PASS host cannot reach Redis …` with 0 skips, or provider isolation recorded — not run |
| K-46 webhook scheduler + queue monitoring + egress | **REQUIRES SERVER OPERATOR** | cron/systemd installed and alert on `ZCARD webhook:queue` — not run |
| METRICS_TOKEN on server + scrape restriction | **REQUIRES SERVER OPERATOR** | token in provider secret store; scrapers allowlisted |
| Persistent `/backups` volume | **REQUIRES SERVER OPERATOR** | persistent disk on target; free Redis is not durable |
| Legal pages, trademark/lawyer, absolute `og:image`, go/no-go signature | **REQUIRES HUMAN APPROVAL** | publish `site/privacy.html` + `site/terms.html`; sign below |
| Product decisions D-token, D-request-mode | **REQUIRES HUMAN APPROVAL** | record in `docs/DECISIONS.md` before related code (D-017 defers the second token) |

## 4. Blockers

| Item | Classification | Why |
| --- | --- | --- |
| Public launch | **BLOCKED** | T-70 and T-71 have no target-host evidence; release artifact uncommitted (fresh clone cannot build); protected-path approvals unsigned |
| Fresh-clone build | **BLOCKED** | Required source/test files untracked; human must stage, commit and re-run CI from a clean clone before tagging |
| Live restore / real TLS verification | **BLOCKED** | no host access; only isolated drill and local rehearsal were run |
| Webhooks enabled publicly | **BLOCKED** until K-46 | no scheduler, queue alert or egress policy on a server |
| Paid VPS / domain | **BLOCKED** | budget ₹0; deferred until usage justifies it |

## 5. Fixes applied during this final review

- Real-browser coverage added for the primary copy action: `e2e/journey.mjs` now clicks
  `Copy link` and `Copy secret` and asserts `role=status`; journey re-run green.
- Evidence ledger completed: final gate re-runs (backend 307/0, frontend 35/0, all eight journeys),
  parity recomputed on the working tree (80.8/100, 11/11 must-haves), `replica/features.csv` rows 19 and 31
  corrected from `yes` to `partial`, stale counts reconciled across status docs (`site/index.html`
  now says "300+" so shipped copy does not drift on every suite run).
- An earlier parallel frontend run timed out 3 files under host load and a backend run hit the
  DB-15 client guard; both were re-run clean without weakening any test.
- Historical (point-in-time, 303/0) fixes from the earlier pass:

- Order-dependent spec failures in `qa_defect_regression_spec.rb` (persisted `Sec-Fetch-Site`) —
  made the origin proof explicit; 303/0 was the count at that time (final total 307).
- Real dark-mode WCAG contrast defect (`.transition` 4.07:1) — `--ots-text-muted` in
  `replica/design/tokens.css` raised to an AA-passing value; a11y gate re-run clean.
- A11y gate negative control was absent despite doc claims — `e2e/a11y.mjs` now seeds an
  `image-alt` violation, confirms axe detects it, and fails the gate if it does not.
- New test typecheck broke on Node/jsdom types — added `"node"` to tsconfig types and a minimal
  ambient `jsdom` declaration (no new dependency); typecheck/build clean.
- Release-doc drift corrected in `RELEASE_CHECKLIST.md`, `QUALITY_REVIEW.md`,
  `SECURITY_AUDIT.md`, `KNOWN_ISSUES.md` (K-48 resolved), `API.md`,
  `PRODUCTION_READINESS.md`, `PRD.md`, `FEATURE_MATRIX.md` and `replica/features.csv`.

## 6. GO / NO-GO

**NO-GO for public launch.** Every *in-repo testable* requirement is **FIXED AND VERIFIED**
with command output (307 backend specs, 35 frontend tests, 8 journeys, 0 a11y violations, clean
build, compose, examples, migration and restore drill). The fresh-clone/CI gate is **BLOCKED**
until the staged tree is committed/tagged; operator gates T-70/T-71/K-46 and human approvals are
also open. No deploy, commit, push or production infrastructure change was made.

When the operator evidence exists, attach it here and flip the verdict — not before.

### Sign-off (humans only)

- Protected-path review approved by: ____________________  date: __________
- Release artifact committed/tagged by: ____________________  ref: __________
- Operator T-70 evidence attached by: ____________________  date: __________
- Operator T-71 evidence attached by: ____________________  date: __________
- Final go/no-go signed by: ____________________  date: __________

Do not fill these lines from an agent report. They require a person and recorded target-host output.

## 7. Final independent verification (this pass)

Six `.claude/` release specialists ran **simultaneously** on disjoint scopes: product acceptance,
security verification, frontend QA, backend QA, infrastructure and documentation. Every report was
re-read against source by the main agent. `@stageshow` coordination still:
`docs/final-release-review.html` / `.png` (1030×560, zero page errors, no overflow).
`@reverse-engineer-anything` was not applicable (no competitor artifact; complete source tree).

### 7.1 Reviewer verdicts (code scope only)

| Scope | Verdict | Note |
| --- | --- | --- |
| Product acceptance | **GO** | All 11 `must` rows verified with source + asserting spec/journey; deferrals honest. Fixed parity row 19 undercount (theme → `partial`, re-scored 80.8/100), PRD count and parity history this pass |
| Security | **GO (code-level)** | No open S1/S2; SA-61 (S3, cookie prefix) remains proposed-only pending protected-path approval. Copy rule holds (negation-only) |
| Frontend | **GO (code-level)** | 8 journeys assert real outcomes; axe gate has no rule exclusions and a working negative control; built tree has one JS + one CSS, no maps/secrets |
| Backend | **GO** | Status-code coverage, typed envelopes, body caps, 503 mapping, CAS consume, decrypt-before-delete, full-mode 501, CSRF/origin, webhook SSRF and migration all code- and spec-backed |
| Infrastructure | **GO (in-repo config)** | Non-root/read-only image, loopback publish, Redis auth/ceiling/internal net, SHA-pinned CI, env contract, backup/migration/TLS rehearsal verified. T-70/T-71/K-46 are operator-owned |
| Documentation | **NO-GO → corrected** | Honest-reporting gap (code-readiness claim vs blocked fresh-clone gate) and stale counts fixed in §1, §2, §3 and this section; all relative links resolve |

### 7.2 Commands executed by the main agent

| Gate | Command / evidence | Result |
| --- | --- | --- |
| Backend unit | `docker run … ots-dev bundle exec rspec spec/unit` | **138 examples, 0 failures** |
| Backend integration | `docker run … ots-dev bundle exec rspec spec/integration` | **169 examples, 0 failures** |
| Frontend unit | `npm --prefix frontend run test` | **35 passed / 8 files** |
| Typecheck / production build | `npm --prefix frontend run typecheck` / `run build` | clean; JS 253.72 kB, CSS 23.00 kB |
| Brand sweep | `bash script/brand-sweep.sh` | `Clean.` |
| Migration | `bin/ots migrate --dry-run` → `migrate` → `migrate` on scratch DB14 | current `0→1`, dry-run no write, re-apply "nothing applied", exit 0 |
| Backup / restore | `bash script/restore-drill.sh` | `RESTORE DRILL PASSED`; live payload intact, spent gone, schema=1 |
| Dependency audits | `bundler-audit check --update`; `npm --prefix frontend audit --omit=dev --audit-level=high` | 1406 advisories / 0; production npm 0 |
| Parity | `python3 parity.py replica/features.csv` | **80.8/100, 11/11 must-haves** |
| Fresh clone | `git write-tree` → `git archive` → build/test/image in `/tmp/ots-fresh` | 289 files, 35 tests, 307 specs, `User=ots` image (see `OPEN_SOURCE_READINESS.md` §4) |

### 7.3 Blockers and disposition

- **BLOCKED — public launch:** T-70 TLS on a real hostname, T-71 host Redis firewall, K-46
  webhook scheduler/queue alert/egress. No target host was touched.
- **BLOCKED — CI reproduction:** the complete release tree is staged but **uncommitted**; human
  commit/tag/sign-off required (`OPEN_SOURCE_READINESS.md` §5).
- **PENDING APPROVAL (S3):** SA-61 `__Host-` cookie prefix (`app.rb` is protected).
- No new product defect was found in this pass; no test was weakened to obtain a green run.

### 7.4 Final recommendation

**NO-GO for public deployment.** All code-level requirements are verified and all fixable
documentation defects were corrected in this pass, but the objective's own rule — declare GO only
when *all* critical release requirements are verified — cannot be met while the operator gates and
the commit/tag/sign-off remain unexecuted. **No deploy, push or public exposure was performed.**
