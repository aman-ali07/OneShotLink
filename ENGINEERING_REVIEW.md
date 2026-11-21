# OneShotLink — Engineering quality review

**Date:** 2026-11-21
**Role:** independent engineering-quality review and cleanup pass
**Method:** four `.claude/` specialists ran **in parallel** on disjoint scopes — frontend
(`vue-reviewer`/`typescript-reviewer`/`code-simplifier`), backend (`ruby-reviewer`/
`code-simplifier`/`comment-analyzer`), database/Redis (`database-reviewer`), and
dependencies/config. Every report was re-read against the source by the main agent; no agent
report was accepted without code evidence. `@stageshow` produced the coordination still
`docs/engineering-quality-posture.{html,png}` (1030×560, zero page errors, no overflow).
`@reverse-engineer-anything` was not used: no competitor artifact was supplied and the complete
source is available locally, which its own routing rule says to inspect with repository tools.

## 1. Cleanups applied

| Area | Change | Why it is safe | Verification |
| --- | --- | --- | --- |
| Frontend | Removed dead `AbortController` from `ConcealView.vue` (declaration, assignment, unmount hook and now-unused import) | `publicConfig()` and `concealSecret()` take no signal; nothing observed the abort | `vue-tsc --noEmit` clean, 35 Vitest tests |
| Frontend | Deleted unused ambient `frontend/src/jsdom.d.ts` | Repo-wide grep found zero `jsdom` imports; the `?raw` site test uses Vitest's jsdom environment | typecheck + tests green |
| Frontend | Exported `Delivery` from `api.ts` and replaced the inline duplicate in `DashboardView.vue` | Two real definitions of the same schema; type-only change, no runtime code | typecheck + build green |
| Frontend | **Bug fix:** `RevealView` now re-peeks when the router reuses the view for a new `/secret/:key`; peek logic extracted into `load()` with a per-load `AbortController` | Previously the component reset to `idle` and never previewed the new key — a blank screen instead of passphrase/gone/invalid phase | New `RevealView.test.ts` was red (only first key peeked) then green; all 8 browser journeys green |
| Backend | Deleted dead `Config.auth_enabled?` | Zero callers repo-wide; callers use `auth_mode`/`full_mode?` | 306 backend examples green |
| Backend | Deleted `Store.get_json`/`set_json` and their sole example | Zero production callers; models need raw bytes for CAS and parse inline | full suite green; the removed example tested only the deleted helpers, not product behavior |
| Backend | `RotateKey` now reuses `Webhook::ENDPOINT_PREFIX` and `SecretRequest::OBJECT_PREFIX` instead of duplicate literals | Byte-identical strings; constants are loaded before `rotate_key.rb` | rotation/ops specs green |
| Backend | Corrected stale comments in `models/secret.rb` (v2→v3), `logic/secret_requests.rb` (TTL fallback now only covers `-1`), `webhook.rb` (accurate "metadata and opaque identifiers" claim) | Comment-only; no behavior change | full suite green |
| Docs | Corrected current-state drift: `DATABASE.md` receipt-index lifecycle, `ARCHITECTURE.md` v2→v3 claims (historical downgrade row marked as history), `DECISIONS.md` D-016 superseded axe package, `PRD.md`/`FEATURE_MATRIX.md`/`TASKS.md` removed-gem claims, `TESTING.md` `.rspec --warnings` wording, `API.md` reveal passphrase `422` | Docs now match shipped code; historical pass records left intact | source/doc re-read; no behavior change |

## 2. Verification after cleanup

| Gate | Result |
| --- | --- |
| Backend RSpec (30 files, one container per file because this host OOM-kills large runs) | **306 examples, 0 failures** (`TOTAL_EXAMPLES=306`) |
| Vitest | **35 passed / 8 files**, 0 failures |
| `vue-tsc --noEmit` | clean |
| `npm --prefix frontend run build` | `✓ built in 4.79s`; hashed JS 253.72 kB / CSS 23.00 kB |
| 8 browser journeys (`journey`, `accounts`, `requests`, `file`, `webhooks`, `states`, `mobile`, `a11y`) | all exit 0; axe gate 0 violations including the negative control |
| `script/brand-sweep.sh` | `Clean.` |
| Stageshow still | rendered 1030×560, `{"errors":[],"overflowX":false,"overflowY":false}` |

Dependencies were independently checked by the specialists: every declared gem and npm package
has a real caller; both npm lockfiles match their manifests; no typosquat or hallucinated package.
No new dependency was added, so no DECISIONS/TECH_STACK entry was needed.

## 3. Deliberately not changed (with reason)

- `Webhook.validate_url!` — spec-only wrapper, but **kept** because `SECURITY_AUDIT.md` and the
  feature matrix record it as a deliberate validation seam. Removing it needs a human decision.
- `RotateKey#reencrypt` — one-line helper with one call site, but the file is security-sensitive
  and the cleanup value is negligible; left untouched.
- `ApiError.requestId` — populated but unread by views; the comment retains it for support
  reports. Removing it changes the typed error API.
- Frontend `preview` npm script — unused in CI but a standard Vite convenience; harmless.
- Focus-management duplication in `RevealView` — a shared helper would be a11y-critical churn;
  the existing axe/keyboard gates are the right guard, so no refactor.
- Repeated `kind` inference / count aggregation in `backup.rb`, `with_env` in specs, and the
  four `expected_value` guards in `store.rb` — consolidation would require new helpers with only
  two call sites each, which the repo's "no abstraction without 2–3 real call sites" rule forbids.
- Persistent data shapes (`META_VERSION`, `META_FIELDS`, backup format 1/2, schema marker) —
  changing them requires expand→migrate→contract, not cleanup.

## 4. Unresolved issues (need human/operator action)

1. **HIGH — clean checkout is incomplete.** `git ls-files e2e/` lists only 5 of the 8 journeys;
   `e2e/{a11y,mobile,states}.mjs` are untracked. Several production modules under
   `frontend/src/lib/` (`authMode.ts`, `clipboard.ts`, `config.ts`, `format.ts`) and the test files
   that make up the 35-test count are also untracked. On a fresh clone, `npm --prefix e2e test:a11y`
   fails with "cannot find module" and the frontend build can fail on missing imports. The agent
   did **not** stage or commit anything: the temporary working tree is the user's state, and
   git staging is a human decision. Remediation: review and `git add` the intended source, tests
   and journeys together, then re-run the clean-checkout CI container job.
2. **MED — duplicated protected CI step.** `ci.yml:125-126` runs `test:mobile` twice. Editing
   `.github/workflows/` is a protected path; needs operator approval.
3. **MED — generated artifacts not triaged.** Untracked `docs/*-posture.html`/`.png` pairs,
   `docs/responsive-*.png` and design-gate screenshots are not covered by `.gitignore`, despite
   the repo rule that screenshots are references in `replica/screens/`. Human decision: ignore or
   delete throwaway renders; keep deliberately authored stills. This review added two more stills
   (`engineering-quality-posture.*`, and the earlier security/performance posture) — they are
   coordination artifacts, not assets.
4. **LOW — `docs/FEATURE_EVIDENCE.md:23,66`** still says "no committed axe-core assertion". It is
   literally true while `e2e/a11y.mjs` is untracked; it resolves automatically once issue 1 is
   handled, then the doc should be updated.
5. **LOW — `PROJECT_AUDIT.md`** is a historical snapshot and still names the removed `i18n` gem
   and pre-fix `secure_compare` state. Left intact as history; do not read as current status.
6. **LOW — no lint runner.** There is no ESLint/Biome config or `lint` script. Adding one requires
   a canonical-package check and a `DECISIONS.md` entry; not done in this cleanup.
7. **Operator gates T-70/T-71** remain open, as do the protected-path proposals from the security
   audit (base-image digest pinning, receipt-listing N+1, CI cleanup). No deploy or public exposure
   was attempted; the release verdict stays **NO-GO** pending target-host evidence and sign-offs.

## 5. Independent second-reviewer pass (2026-11-21)

Four more `.claude/` specialists ran **in parallel** on disjoint scopes (`quality-frontend`,
`quality-backend`, `quality-database`, `quality-deps`). Every report was re-read against source;
no agent prose was accepted without a grep/read proving the claim. `@stageshow` produced
`docs/engineering-quality-independent.html` / `.png` (1030×560, zero page errors, no overflow).
`@reverse-engineer-anything` was not applicable (no competitor artifact; complete source tree).

### 5.1 Cleanups and fixes applied

| Area | Change | Evidence / verification |
| --- | --- | --- |
| e2e | Replaced three byte-identical local `assert` helpers (`journey`, `accounts`, `states`) with the canonical `node:assert/strict` import used by the other five journeys | grep proved three copies; all eight scripts pass `node --check`; four affected journeys re-run green |
| e2e | Deleted a `DEBUG=`/`ERRORS=` catch-block dump in `webhooks.mjs` that printed the dashboard DOM while the one-time signing secret was visible | Same secrecy rationale as the earlier `requests.mjs` fix; journey re-run green |
| e2e | Removed an allocated-but-never-used temp directory and its `node:os`/`node:path` imports from `a11y.mjs` | only two references existed (create + delete); axe gate unchanged |
| Backend | Deleted dead `Store.attr_writer :redis` and corrected the "everything uses Lua" comment (multi-key writes use `MULTI`) | zero `.redis =` callers; store/ops specs green |
| Backend | Added the missing `require "time"` in `lib/onetime.rb` | `Time#iso8601` was reachable only through transitive requires |
| Backend | `bin/ots` password reset now uses `SignUp::MIN/MAX_PASSWORD_BYTES` instead of a duplicated literal | CLI-only; bounds unchanged |
| Backend | Consolidated the 128-byte capability-key ceiling into `Ids::MAX_KEY_BYTES` (4 non-protected call sites) and the byte-identical `validate_ttl` into `Config.valid_ttl!` (2 call sites) | behavior-neutral; full suite green |
| Backend | **Bug fix:** a malformed webhook queue item no longer HSETs a TTL-less `webhook:delivery:` key for a nil id | red spec (key existed) → green; webhook suites 20/0 |
| Database | Backup now excludes all `DENIED_PREFIXES` in `collect_typed` instead of a duplicated session literal; comment lists session digests | behavior unchanged (no other denied prefix overlaps a section) |
| Config/docs | Removed a no-op Ruby magic comment from `tls-rehearsal.sh`; corrected `TESTING.md` §8 (SDK examples **are** a CI step), `DEPLOYMENT.md` (Compose proxy defaults), `DATABASE.md` command inventory | all verified against `ci.yml`, `compose.yaml` and source |

No dependency was added or removed; every declared gem/npm package still has a real caller and
both lockfiles match their manifests.

### 5.2 Verification after this pass

| Gate | Result |
| --- | --- |
| Backend RSpec (two batches) | **138 unit + 168 integration = 306 examples, 0 failures** |
| `npm --prefix frontend run test` | **35 passed / 8 files** |
| `npm --prefix frontend run typecheck` | clean |
| `npm --prefix frontend run build` | clean — JS 253.72 kB / CSS 23.00 kB |
| Modified e2e journeys | `journey`, `webhooks`, `states`, `accounts` all green |
| All e2e scripts | `node --check` passes for all eight |
| Brand sweep / shell syntax | `Clean.`; `tls-rehearsal.sh` and `webhook-worker.sh` pass `bash -n` |

### 5.3 Unresolved issues (not silently ignored)

1. **HIGH — clean checkout still incomplete** (carried from §4): several CI-referenced e2e
   journeys and frontend source/test files are untracked. Staging is a human decision; no git
   staging or commit was performed in either review.
2. **MED — protected paths left untouched:** the Ruby magic comment remains in `preflight.sh`
   and `preflight_selftest.sh`; `app.rb` still hard-codes `128` and `12..256`; the duplicated
   CI `test:mobile` step remains in `ci.yml`. All need operator approval.
3. **MED — duplicated throwaway-stack shell logic** (`seq 1 30` health poll and loopback Redis
   setup repeated in ≥5 scripts). Extracting a shared helper would touch protected files and
   standalone scripts; deferred rather than half-applied.
4. **LOW — `Onetime::RateLimited` metadata** is attached/read via instance variables in a logic
   class and protected `app.rb`; typed accessors would change a typed-error API.
5. **LOW — `Metrics` fallback bucket `"other"`** is never rendered; no caller uses it today, so
   changing `/metrics` output was avoided.
6. **LOW — `"org_id" => nil`** in every v3 secret record is never read, but removing it changes
   persisted bytes and needs expand→migrate→contract, not cleanup.
7. **LOW — `limiter:<client>:<scope>:counter`** is write-only in application code but is used by
   RUNBOOK operator commands; it was deliberately retained.
8. **LOW — no lint runner** (unchanged from §4).
