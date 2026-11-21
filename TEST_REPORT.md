# OneShotLink — Test Report

> **Point-in-time QA pass.** Some counts below are snapshots from earlier passes; the final
> release totals are **307 backend examples / 35 frontend tests / 8 journeys**, recorded with
> command output in `RELEASE_CHECKLIST.md` and `TESTING.md`.

**Date:** 2026-11-21
**Role:** senior QA automation engineer
**Scope:** the complete repository — Ruby/Roda backend, Vue 3 SPA, HTTP API contracts, browser
journeys, responsive layout, WCAG 2.2 AA, auth/authz, expiration, passphrase, concurrent
retrieval, edge cases, invalid inputs and failure injection. Code-level and local-live testing
only; **no public host was deployed or exposed**.

## 1. Method and evidence standard

Six `.claude/agents/` QA personas were launched **in parallel**, each with a disjoint read-only
scope so their work could not conflict:

| Persona | Scope |
| --- | --- |
| `qa-unit` | crypto, password, IDs, limiter, config, store, session, migration, audit, metrics, backup, webhook, CLI |
| `qa-api` | v1/v3 routes, error envelopes, headers, body caps, rate-limit scopes, OpenAPI, 503 paths |
| `qa-auth` | sessions, cookie flags, sliding TTL, CSRF/origin proofs, owner isolation, full-mode gate |
| `qa-edge` | atomic consume/CAS, expiry, passphrase budget, receipt lifecycle, burn, restore safety |
| `qa-browser` | eight puppeteer journeys, console/storage assertions, copy/double-submit states |
| `qa-responsive` | 320/375/768/1280 layout, 44 px targets, focus, axe WCAG 2.2 AA gate |

Every agent finding was re-read against the implementation before any change: agent prose is
**not** evidence. Product defects were reproduced with a failing spec (red) before the fix and
re-run green afterwards. Browser findings were reproduced against a live Puma on `127.0.0.1:3100`
(`AUTH_MODE=simple`). Ruby runs in the `ots-dev` Docker image against throwaway Redis DB 15.

## 2. Coverage matrix

| Area | Where | What is exercised |
| --- | --- | --- |
| Unit | `spec/unit/*_spec.rb` (15 files) | AES-GCM round-trip (UTF-8, empty, **binary**), fresh IV/salt, **salt-swap integrity**, wrong key, tamper, algorithm downgrade, Argon2id, limiter math, config fail-closed, store CAS/consume, session TTL/revocation, migration, audit redaction, metrics, webhook validation, CLI |
| Integration / API | `spec/integration/*_spec.rb` (13 files) | v1/v3 routes, payloads, typed error envelopes, **error-path no-store/Pragma/HSTS**, media type, body caps, all limiter scopes, accounts, receipts, burn, requests, webhooks, OpenAPI 3.1 |
| Edge / invalid input | `qa_defect_regression`, `edge_hardening`, `security_hardening`, `web_spec` | malformed/non-object JSON, non-string passphrase, chunked oversized bodies, Redis outage + OOM → 503, corrupt/rotated records, uniform 404, **backup entries with missing/zero TTL** |
| Concurrency / race | `qa_acceptance`, `store_spec`, `secrets_api_spec` | 8-way reveal on unprotected and passphrase-protected secrets, per-secret guess budget under a wrong-passphrase burst, two-key CAS rotation, request `SET NX` single-answer retirement |
| Auth / authz | `accounts_spec`, `session_spec`, `hardening_spec` | cookie flags, sliding TTL + index re-add CAS, revoke-all, CSRF and origin proofs (forwarded-header resistant), owner isolation, `AUTH_MODE=full` → 501 with the **v1 envelope**, all-or-nothing deletion |
| Expiration / passphrase | `secrets_api_spec`, `receipt_lifecycle_spec` | TTL expiry, 30-day receipt retained with no payload, 8-byte floor, wrong/missing/short passphrase, budget without consumption, burn |
| Browser / E2E | `e2e/*.mjs` (8 journeys) | lifecycle, accounts, file bytes, incoming requests, webhooks, terminal states, mobile 320/375, axe a11y |
| Responsive / a11y | `e2e/mobile.mjs`, `e2e/a11y.mjs` | no horizontal overflow, **44 px targets including 0 px collapse**, skip link, 40 axe states across 4 viewports + dark theme |

## 3. Execution results

All commands were executed locally; results are pasted from the actual runs.

| Command | Result |
| --- | --- |
| `docker run … ots-dev bundle exec rspec spec/unit` | **137 examples, 0 failures** |
| `docker run … ots-dev bundle exec rspec spec/integration` | **166 examples, 0 failures** |
| Backend total | **303 examples, 0 failures** (all 30 spec files, two batches to avoid host OOM) |
| `npm --prefix frontend run test` | **34 passed (7 files)** |
| `npm --prefix frontend run typecheck` | `vue-tsc --noEmit` clean |
| `npm --prefix frontend run build` | clean — `index-7RkpDxeX.js` 253.74 kB, `index-BlR2tdn2.css` 23.00 kB |
| `node e2e/journey.mjs` | `ok: true`, `errors: []` (incl. passphrase wrong→correct, multi-byte, file) |
| `node e2e/accounts.mjs` | `accounts journey ok` |
| `node e2e/requests.mjs` | `ok: true`, `errors: []` |
| `node e2e/file.mjs` | `{"ok":true,"bytes":8,"replay":404,"errors":[]}` (measured status) |
| `node e2e/webhooks.mjs` | `ok: true`, signing secret + delivery event asserted |
| `node e2e/states.mjs` | 2 journeys, 0 errors |
| `node e2e/mobile.mjs` | `ok: true`, 20 checks, 0 overflow, 0 browser errors |
| `node e2e/a11y.mjs` | **40 states, 0 WCAG 2.2 AA violations**; negative control `image-alt` detected |
| `bash script/brand-sweep.sh` | `Clean. Nothing of the original's name, domain or colours found.` |
| Live curl (error headers) | 404/401 now return `cache-control: no-store`, `pragma: no-cache` |

Browser gate evidence (final run):

```
a11y gate passed: 0 WCAG 2.2 AA violations across audited states
{"name":"negative-control-image-alt","detected":true}
```

## 4. Failures found and fixed

Seven defects were fixed (four product, three test-integrity), each verified red → green.

### F1 — P1 product: backup restore could create an immortal secret

`Backup.validate_entries!` guarded a TTL only when the `ttl` key existed
(`entry.key?("ttl") && entry["ttl"].to_i <= 0`). A hand-edited backup omitting `ttl` passed
pre-flight; `restore_section` computed `nil.to_i == 0` and issued a bare `SET`, permanently
restoring an encrypted payload. A submission key filed under another section had the same gap.

**Red:** two new specs in `spec/integration/qa_defect_regression_spec.rb` →
`2 examples, 2 failures` ("expected Onetime::Error … but nothing was raised").
**Fix:** `lib/onetime/backup.rb` now requires a strictly positive integer TTL for any
`raw` entry or any key in a secret-bearing namespace (`secret:object:`, `secret:receipt:`,
`request:secret:`, `webhook:delivery:`), matched on the **key**, not the section. Persistent
namespaces such as `webhook:queue` are deliberately excluded.
**Green:** `spec/integration/qa_defect_regression_spec.rb spec/unit/ops_spec.rb` →
`34 examples, 0 failures`.

### F2 — P1 product: error responses lost no-store/Pragma/HSTS

The headers were set inside the Roda `route` block; Roda's error handler rebuilds the response,
so every 4xx/5xx lost `Cache-Control: no-store`, `Pragma: no-cache` and HSTS. Confirmed live:
`GET /api/v3/guest/secret/<unknown>` → 404 with no `cache-control` header, while `/health` 200
had it. A consumed link's 404 is a secret-bearing answer and must not be cacheable.

**Red:** two new specs in `spec/integration/web_spec.rb` → `Cache-Control` and
`Strict-Transport-Security` were `nil`.
**Fix:** extracted `apply_response_headers!` in `lib/onetime/web/app.rb`, called from both the
route and the error handler.
**Green:** 3 targeted examples `0 failures`; live re-check after fix:

```
HTTP/1.1 404 Not Found
cache-control: no-store
pragma: no-cache
HTTP/1.1 401 Unauthorized
cache-control: no-store
pragma: no-cache
```

### F3 — P2 contract: v1 full-mode 501 used the v3 error envelope

The `AUTH_MODE=full` guard raised before `env["onetime.api_version"] = "v1"`, so
`POST /api/v1/share` answered `{"error":{...}}` instead of the frozen v1 `{"message":...}`.

**Red:** assertion added to the existing full-mode example → `expected {"error"=>...} to include "message"`.
**Fix:** tag `api_version` as v1 before raising for `/api/v1` paths.
**Green:** targeted example `0 failures`.

### F4 — test integrity: deleted-account sign-in could false-pass

`e2e/accounts.mjs` waited for `main`, which lives in the App shell and exists before the async
sign-in settles — a broken app could still "pass". Now it waits for `#signin-error` and asserts
the path stays `/signin`. Journey re-run green (after a 60 s cooldown for the 10/60 s signin
limiter, which had caused a transient failure during back-to-back runs).

### F5 — test integrity: 44 px mobile gate ignored collapsed controls

`e2e/mobile.mjs` filtered `h > 0 && h < 44`, so a 0 px control passed. Tolerances now fail on any
height below 44 px, require at least one matched control, and the gate also runs on the home and
reveal-idle states. Re-run: 20 checks, 0 errors.

### F6 — test integrity: file "replay 404" was hard-coded

`e2e/file.mjs` logged `replay: "404"` without measuring it. It now fetches the guest preview for
the spent key and asserts the real status. Re-run: `"replay":404` measured.

### F7 — accessibility: dark-mode contrast regression

The axe gate caught `color-contrast` **4.07:1** on dark-mode muted text at 1280 px (AA needs
4.5:1). The corrected token (`--ots-text-muted: #b9b4ae`) had landed in source *after* the last
bundle, so the served CSS was stale. Rebuilt the SPA and re-ran: **40 states, 0 violations**.

**Coverage additions (no product change):** binary and salt-swap crypto invariants
(`crypto_spec`, 11/0), backup missing-TTL cases (F1), error-header and v1-envelope cases
(F2/F3), and a timestamp formatter case (`format.test.ts`). A concurrent agent in the same
working tree also added complementary backup/delivery TTL and static-CTA tests; all were
executed as part of the final suites.

## 5. Product-level acceptance (@stageshow)

`@stageshow` was used for the product-engineering acceptance conversation. The coordination
still is `docs/qa-final-acceptance-posture.html` with its rendered
`docs/qa-final-acceptance-posture.png` (1030×560, zero page errors, no document overflow). It
shows the gate totals and the fixes above on its face, keeps the honest status — **code-level
acceptance GO; public launch NO-GO** until T-70 (TLS on a real hostname) and T-71 (Redis host
firewall) have target-host evidence — and carries no zero-knowledge/E2EE claim (D-012).

## 6. Residual risks and not executed here

- **T-70 / T-71 remain operator-owned** — no public DNS, certificate chain or host firewall was
  touched, and nothing was deployed. Only the local TLS rehearsal exists.
- A **conditional** auth finding was not changed: `revoke_all` enumerates sessions from
  `customer:sessions:<id>`, so if that index key is evicted/tampered while a session hash lives,
  a password change could leave that session live. Normal operation keeps index and hash TTLs
  synchronised; no spec reproduces it outside that precondition. Logged for product follow-up.
- No live production restore or `SECRET` rotation was run against real data; the isolated drills
  only prove the tooling.
- The full backend suite is run in two batches because a single 300-example process can be
  OOM-killed on this host; all 30 spec files were executed in the final runs.
- Pre-existing `git diff --check` trailing whitespace in `replica/features.csv` comes from
  concurrent work outside this QA pass; left untouched deliberately.

## 7. Reproduction commands

```bash
# Backend (two batches; Ruby is not installed on the host)
docker run --rm --network=host -v "$PWD":/app -v ots-bundle:/bundle \
  -e BUNDLE_PATH=/bundle -w /app ots-dev bundle exec rspec spec/unit
docker run --rm --network=host -v "$PWD":/app -v ots-bundle:/bundle \
  -e BUNDLE_PATH=/bundle -w /app ots-dev bundle exec rspec spec/integration

# Frontend
npm --prefix frontend run test && npm --prefix frontend run typecheck && npm --prefix frontend run build

# Browser (live stack on :3100, AUTH_MODE=simple)
export BASE_URL=http://127.0.0.1:3100 CHROME_PATH=/usr/bin/google-chrome
for j in journey accounts requests file webhooks states mobile a11y; do node "e2e/$j.mjs"; done
```
