# Testing

> **Status: 307 backend examples, 0 failures (2026-11-21), plus eight verified headless
> browser journeys and a Compose smoke test.** Ruby/Bundler are not installed on the
> host, so backend tests run in the `ots-dev` Docker image against Redis DB 15. Lifecycle,
> passphrase, TTL, at-rest encryption, concurrency, v1, rate limits, and simple-mode
> accounts are implemented. The Vue build/typecheck passes, Vitest covers the API client,
> `e2e/journey.mjs` plus `e2e/accounts.mjs` are the two primary browser journeys; six more
> (requests, file, webhooks, states, mobile, a11y) are committed and listed in §3.

## 1. Strategy

- **Integration-first for the lifecycle.** The product's contract is HTTP behaviour, so
  specs drive Roda through `rack-test` and a real Redis (DB 15). No mocking of Redis:
  the atomic consume script *is* the behavior under test.
- **Unit specs for pure logic.** Crypto, IDs, password hashing, limiter math, config
  parsing. No network.
- **Frontend:** Zod schemas get unit tests (Vitest); TypeScript strict + build is the gate.
  Eight committed browser journeys (puppeteer-core) cover lifecycle, accounts, file,
  requests, webhooks, terminal states, mobile widths and axe accessibility.
- **No tautological tests.** Assert on responses, Redis state, and error codes — not on
  mocks created in the same example.
- **Red → green.** Add a failing spec for the bug first, then fix it. If a test was never
  seen failing, say so in the handoff.

## 2. Commands

**One command for a running deployment.** With the stack up in `AUTH_MODE=simple`, this runs
the health/config probes, the six dependency-free SDK examples (three quickstarts + three advanced flows) against a throwaway stack,
seven browser journeys and the a11y gate, with optional mobile, metrics and restore-drill
steps. No CI or external service is required.

```bash
BASE_URL=http://127.0.0.1:3000 script/verify-deployment.sh
# optionally: SITE_URL=http://127.0.0.1:6431 METRICS_TOKEN=... OTS_VERIFY_RESTORE=1
```

Native (once Ruby is installed):

```bash
bundle install
bundle exec rspec                     # full suite
bundle exec rspec spec/unit           # fast unit suite
bundle exec rspec spec/integration/secrets_api_spec.rb:42
```

Frontend:

```bash
npm --prefix frontend ci
npm --prefix frontend run test        # vitest: 35 tests (schema, errors, components, views, formatter, static CTA)
npm --prefix frontend run typecheck
npm --prefix frontend run build       # also the gate for the SPA shell in Rack
```

SDK examples (boots a throwaway stack, runs all six examples, cleans up):

```bash
script/test-examples.sh               # curl/TS/Python: quickstart + advanced (passphrase, file, burn)
```

Docker path on a host without Ruby (this is the command that was run):

```bash
docker run --rm --network=host \
  -v "$PWD":/app -v ots-bundle:/bundle -e BUNDLE_PATH=/bundle -w /app \
  ots-dev bundle exec rspec
```

`spec_helper` defaults to `REDIS_URL=redis://127.0.0.1:6399/15`, so start Redis first:

```bash
# with a local redis-server, or without one installed:
docker run -d --rm --name ots-test-redis -p 6399:6379 redis:7.4-alpine
```

**DB 15 only.** `spec_helper` calls `FLUSHDB` on DB 15, refuses a URL that is not DB 15,
and refuses to run at all when another client is already attached to DB 15 — so a stray
server or a second suite can neither be flushed nor make a run under-report. Never use
`FLUSHALL`. The `ots-dev` image and `ots-bundle` volume are built once (see
[README.md](README.md)).

## 3. Current backend coverage (M1–M2, verified)

| Spec | Examples | Covers |
| --- | --- | --- |
| `spec/unit/crypto_spec.rb` | 11 | round-trip (incl. binary), wrong key, tamper, salt swap, unique IV/salt, no plaintext |
| `spec/unit/ids_spec.rb` | 4 | length/uniqueness/index normalization |
| `spec/unit/limiter_spec.rb` | 3 | ceiling, window reset, scope isolation |
| `spec/unit/password_spec.rb` | 5 | Argon2id, malformed hashes, bcrypt legacy |
| `spec/unit/store_spec.rb` | 7 | atomic win/lose, mismatch, empty expectation |
| `spec/unit/session_spec.rb` | 9 | digest-only storage, TTL refresh, destroy, revoke-all with exception, full revocation, per-customer isolation |
| `spec/unit/config_spec.rb` | 14 | boot validation, auth mode, proxy CIDRs, Redis URL scheme + password folding |
| `spec/unit/migration_spec.rb` | 6 | schema marker starts at 0, dry-run writes nothing, idempotent apply, no record rewrite, corrupt/newer marker refused |
| `spec/unit/ops_spec.rb` | 26 | audit events/redaction, dropped-write correlation + counter, key rotation (re-encrypt, old key fails, TTL preserved, request submissions, CAS races), backup export/restore incl. request+webhook namespaces and session denial, owner index |
| `spec/unit/metrics_spec.rb` | 7 | exposition format, counters by family/status, duration, Redis up + memory ratio, `METRICS_ENABLED` gate |
| `spec/unit/request_logger_spec.rb` | 4 | request fields, secret-key redaction, asset skip |
| `spec/integration/web_spec.rb` | 16 | health + Redis-down 503, datastore-outage 503 on both API versions (including a full Redis, not just a dropped one), config, CSP/HSTS, typed 404, no-store/Pragma on error paths, SPA shell, HEAD |
| `spec/integration/secrets_api_spec.rb` | 30 | v3 create/reveal/gone, at-rest, passphrase, race, expiry, corrupted-record tamper survives, undecryptable record survives, v1 form+JSON, validation, 413 (declared and undeclared bodies), exact-size boundary, empty passphrase and the 7/8-byte floor, 429 and the literal `Retry-After: 7` budget window, proxy trust, auth-disabled fail-closed, full-mode 501 |
| `spec/integration/accounts_spec.rb` | 30 | signup/cookie/at-rest, duplicate email, validation, signin/401, session TTL/deletion, signout, CSRF, owner isolation, password change, other-session revocation, atomic account deletion, audit trail, disabled/full gates |
| `spec/integration/metrics_spec.rb` | 8 | `/metrics` off by default (`404`), text exposition when enabled, no secrets in the output |
| `spec/integration/openapi_spec.rb` | 23 | valid 3.1 doc, `$ref`s resolve, mounted-path gate + bogus-path negative control, v1 error schemas and status coverage, legacy `message` required, v1 form body, `/metrics`, 3.1 null types, cookie scheme |
| `spec/integration/security_hardening_spec.rb` | 8 | metadata MAC tamper + strict v3 downgrade, post-consume cleanup failure still delivers the value, HEAD 405 hardening headers |
| `spec/integration/qa_defect_regression_spec.rb` | 10 | QA-found defects: TTL-zero request submission refused, non-string passphrase rejected without spending the budget, v1 passphrase gate, tampered preview, immortal-backup refusal (zero **and missing** TTL), owner alias session gate, oversized passphrase, TTL-less receipt/delivery refusal |
| `spec/integration/receipt_lifecycle_spec.rb` | 7 | 30-day retained receipt after reveal/burn with no payload, preview status without consuming, TTL pruning from the owner index, owner-only burn (replay/non-owner/CSRF/rate limit) |
| `frontend/src/lib/api.test.ts` | 17 | conceal/reveal payloads, typed errors, malformed responses, network failure, delete-account, burn, non-consuming peek, scoped deliveries, receipt lifecycle status, `Retry-After` |
| `frontend/src/views/DashboardView.test.ts` | 2 | request-link copy reports success only when the clipboard accepts it; honest failure state otherwise |
| `e2e/journey.mjs` | 1 journey | create → reveal → gone, wrong/correct passphrase (auto-clear asserted), 5-byte passphrase refused by the app, 9-byte multi-byte passphrase accepted and revealed, both web storages empty, no console errors |
| `e2e/accounts.mjs` | 1 journey | signup → owner receipt → reload → signout → signed-out prompt → signin → two-step account deletion → 18-byte CJK password signup; both storages empty |
| `e2e/mobile.mjs` | 20 checks | create → reveal → gone at 375/320 px, passphrase path, signup → dashboard → request → responder at 375 px, static skip link; asserts no overflow and no browser errors |
| `e2e/states.mjs` | 2 journeys (1280/375) | non-consuming preview twice, reveal once, replay gone, invalid key, owner burn → destroyed, burned link gone, already-viewed receipt state with no retained plaintext; zero page errors |
| `e2e/file.mjs` | 1 journey | binary fixture round-trip, exact downloaded bytes, filename/type UI, replay `404` |
| `e2e/requests.mjs` | 1 journey | owner creates link → responder answers → owner reveals once, `409` on second answer |
| `e2e/webhooks.mjs` | 1 journey | endpoint create, one-time signing secret, list/signing-secret redaction, metadata event |
| `e2e/a11y.mjs` | 40 states | axe-core WCAG 2.2 AA over 7 routes × 4 viewports + 5 reveal phases + 7 dark-theme states; 0 violations, no rule excluded |

Backend total: **307 examples, 0 failures**; frontend: **35 Vitest tests, 0 failures**
(17 API-client, 11 component/formatter/view tests plus 2 Dashboard copy-result tests under jsdom).
Accessibility is gated separately by `e2e/a11y.mjs` (axe-core, WCAG 2.2 AA, 40 states across
320/375/768/1280 px, including 7 dark-theme states, 0 violations) — see §3.3.
Tampering is covered two ways: the real one over HTTP (a flipped ciphertext byte in Redis →
`500`, no plaintext, record intact, then readable again once the bytes are put back) and a
stubbed decrypt for the rotated-`SECRET` case. The exact size boundary is covered, and so is
the body cap on a chunked request that carries no `Content-Length`.

Operational checks that run outside RSpec:

```bash
ruby script/loadtest.rb 400 40          # single-use invariant under load
bundle exec bundler-audit check --update
npm --prefix frontend audit --audit-level=high
```

The first two are CI-only on this host (no native Ruby/Bundler). Docker equivalents, with a
stack already running for the load test:

```bash
docker run --rm --network=host -v "$PWD":/app -w /app ruby:3.3-slim \
  ruby script/loadtest.rb 400 40
docker run --rm -v "$PWD":/app -v ots-bundle:/bundle -e BUNDLE_PATH=/bundle -w /app ots-dev \
  bundle exec bundler-audit check --update
```

## 3.1 Frontend and browser evidence (M2)

- `npm --prefix frontend run build` → `vue-tsc --noEmit` clean, Vite build to
  `public/app` (≈253.72 kB JS, ≈23.00 kB CSS).
- Rack: `/` → `200 text/html`; `/assets/index-*.js` → `200 text/javascript`; deep links
  → the SPA shell; unknown API paths remain JSON `404`.
- Headless Chrome (puppeteer-core) completed: conceal → link → reveal → reload → gone,
  with `localStorage === "{}"` and no plaintext in the URL. The passphrase path was
  exercised with a wrong attempt (secret preserved) then the correct one, and a 5-byte
  passphrase was refused twice: the field reports `tooShort` and no link appears, while a
  direct `fetch` of the conceal route answers `422 validation_error` (D-014).
- Responsive DOM audit: no horizontal overflow at 375, 768, or 1280 px.

All eight journeys are committed (`e2e/*.mjs`, puppeteer-core); the primary ones run in CI
against a live Compose stack; `lib/api.ts` has Vitest coverage. Owner journeys (accounts,
requests, webhooks) require `AUTH_MODE=simple`. Sizes above are
from the current build (`index-*.js` ≈ 253.72 kB, `index-*.css` ≈ 23.00 kB).

## 3.2 TLS rehearsal (T-70, repeatable)

`script/tls-rehearsal.sh` boots the production Compose stack behind a real TLS
terminator (Caddy) using a throwaway local CA, then runs `script/preflight.sh` against
it with the certificate verified. It proves the app side of the TLS gate without owning
a domain: HSTS under `SSL=true`, hardening headers surviving the proxy, `Secure`/`HttpOnly`/
`SameSite` cookies, and the plain-HTTP → HTTPS redirect.

```bash
script/tls-rehearsal.sh                # TLS checks only (fast default)
script/tls-rehearsal.sh --with-redis   # adds the Redis isolation checks
```

The default run ends in `PREFLIGHT PASSED (1 skipped)` with a reminder that DNS and the
real certificate chain remain the operator's to prove. `--with-redis` also checks host
isolation from the fixed backend subnet; the result is **host-dependent** — on a host with
the T-71 rule applied it passes with 0 skips, on one without it correctly fails with
`host can reach Redis`. The current recorded run is in
[PRODUCTION_READINESS.md](PRODUCTION_READINESS.md); `script/preflight_selftest.sh` supplies
the pass/fail negative controls independently of the host state.

The rehearsal is not a substitute for the real run: with no DNS and a local CA it cannot
check name resolution or a public chain. Ports default to `13457`/`18443`/`18088`
(`APP_PORT`/`HTTPS_PORT`/`HTTP_PORT`); the stack, CA and proxy container are removed on exit.

### 3.3 Accessibility gate (WCAG 2.2 AA)

`e2e/a11y.mjs` injects `axe-core` through CDP (`evaluateOnNewDocument`) so the app's strict
CSP does not block it, then audits seven static routes plus five live reveal phases
(idle, revealed, gone, passphrase, passphrase-error) with tags `wcag2a`, `wcag2aa`, `wcag21a`,
`wcag21aa`, `wcag22aa`, `best-practice`. The QA pass added a `prefers-color-scheme: dark` pass
over the text-heavy routes at 320/1280 px and the reveal-idle phase at 320 px. Any violation
exits non-zero; no rule is excluded to make the gate pass (D-016).

```bash
BASE_URL=http://127.0.0.1:3000 CHROME_PATH=/usr/bin/google-chrome npm --prefix e2e run test:a11y
# observed: 40 states (7 routes x 4 viewports + 5 reveal phases + 7 dark states), 0 violations
```

Negative control: injecting an `<img>` without `alt` into the home page makes the same
runner report `image-alt:1`, so the gate is not vacuous. jsdom component tests cover
`AppButton` variants/busy state and `CopyButton` success/fallback/failure; they cannot
replace the real-browser axe run for contrast, target size and reflow.

`e2e/mobile.mjs` complements this gate by driving the full journeys at phone widths and
asserting `scrollWidth <= clientWidth` plus ≥44 px targets on the main controls:

```bash
# serve site/ at 6431 so root-relative /styles.css resolves, then:
BASE_URL=http://127.0.0.1:3100 SITE_URL=http://127.0.0.1:6431 \
  CHROME_PATH=/usr/bin/google-chrome npm --prefix e2e run test:mobile
# observed: 20 checks, 0 overflow, 0 browser errors
```

It also verifies the static pages' skip link is the first tab stop and moves focus to `<main>`
(WCAG 2.4.1), which axe cannot assert.

## 4. Required test cases

### Lifecycle (integration)

| Case | Assertion |
| --- | --- |
| Create → reveal | `201` then `200` with the exact plaintext |
| Reveal twice | second call `404`, body has `not_found`, no plaintext |
| GET never consumes | `GET …/secret/:key` twice → both `200` metadata, no `secret_value`; `POST …/reveal` → `200`; then `GET` → `404` (K-35) |
| Expiry | create with `ttl=1`, sleep past it, reveal `404`; Redis `TTL` was positive before |
| Concurrent reveal | N=2..10 parallel requests → exactly one `200`, rest `404`; Redis key gone |
| Wrong passphrase | `401 invalid_passphrase`; record still present; correct passphrase then succeeds |
| No passphrase supplied | `401 passphrase_required`; record preserved |
| Encryption at rest | read `secret:object:<key>` from Redis; plaintext substring absent; `ciphertext` present |
| Tamper | flip a ciphertext byte in Redis; reveal returns `500` generic, no partial output, and the record is left in place (decrypt precedes the consume, D-013) |
| Expired key reuse | re-creating the same key is impossible (IDs are random); no resurrection |
| TTL validation | value not in `TTL_OPTIONS` → `422`; negative/zero → `422` |
| Oversized secret | > 1 MiB → `413 payload_too_large`; no Redis key written. Applies with or without a `Content-Length` header: the bytes actually read are capped, so a chunked form body cannot allocate past the ceiling |
| Unknown key | `404`, identical shape to consumed |
| Rate limit | exceed conceal ceiling → `429` with `Retry-After`; reveal ceiling likewise |
| Health | Redis up → `200`; stopped Redis → `503` (test with a separate connection stub or compose) |

### Unit

| Module | Cases |
| --- | --- |
| `Crypto` | round-trip UTF-8/binary; wrong `SECRET` fails; tampered tag/ciphertext fails; unique IV/salt per call; empty string round-trips |
| `Ids` | length ≥ 22, URL-safe, unique across 10k; `opaque_index` stable and case-insensitive |
| `Password` | Argon2id verify true/false; legacy bcrypt verify (once gem added); malformed hash returns false, never raises |
| `Limiter` | allows up to limit, rejects limit+1, window expiry resets, separate scopes/IDs independent |
| `Config` | missing/short `SECRET` raises; TTL parsing/dedup; auth mode fallback; defaults |

### Frontend

- Zod schema rejects a malformed conceal response instead of rendering `undefined`.
- Reveal view never writes plaintext to `localStorage`/`sessionStorage`.
- Error mapping shows `passphrase_required` as a prompt, `not_found` as a terminal state.

## 5. Test data rules

- Use synthetic values (`"spec-secret-value"`, `"correct horse"`), never real credentials.
- Fixed `SECRET` for specs (`test-only-secret-not-a-real-deployment-key` in
  `spec/spec_helper.rb` is a test fixture, not a deployment secret) so ciphertext is deterministic per run input.
- Generate unique emails per example; flush DB 15 between examples.
- Do not assert on ciphertext bytes (random IV/salt makes them unstable); assert on
  decryptability and absence of plaintext.

## 6. Quality gates

A change is not done until:

- [ ] New/changed behavior has a spec that fails without the change (or the gap is stated).
- [ ] `npm --prefix frontend test` passes for API-client changes.
- [ ] `bundle exec rspec` passes locally (or Docker fallback output is pasted).
- [ ] `npm --prefix frontend run typecheck && npm --prefix frontend run build` passes for
      UI changes.
- [ ] `docker compose config` validates and `SECRET=... docker compose up` is healthy for
      deployment changes.
- [ ] No secret key appears in request logs (`<redacted>` expected).
- [ ] `script/brand-sweep.sh` exits 0 for anything that touches `site/`, `frontend/`,
      `lib/`, `bin/`, `config/` or user-visible copy. It scans tracked non-prose files;
      `*.md` prose and `replica/` are out of scope by design (AGENTS.md explains why).
- [ ] No spec depends on execution order, sleeps longer than needed, or hits DB ≠ 15.
- [ ] No test logs request bodies containing secrets.

## 7. Coverage expectations

- `lib/onetime/crypto.rb`, `password.rb`, `ids.rb`, `limiter.rb`: every branch covered.
- `store.rb`: consume winner/loser and JSON helpers.
- API: every documented status code has at least one spec.
- Coverage percentage is not a gate; untested security invariants are.

### Browser E2E

```bash
# start the stack first (Compose or dev container)
BASE_URL=http://127.0.0.1:3000 npm --prefix e2e test
# account journey requires AUTH_MODE=simple
BASE_URL=http://127.0.0.1:3000 npm --prefix e2e run test:accounts
```

`e2e/journey.mjs` launches Chrome/Chromium (`CHROME_PATH` overrides), creates a secret,
reveals it once, reloads to confirm it is gone, and repeats with a wrong-then-correct
passphrase. It fails on any page/console error, plaintext in the URL, or localStorage use.

## 8. CI (implemented, T-54)

`.github/workflows/ci.yml`: Redis 7 service → `bundle exec rspec`; Node 24 → `npm ci`,
`typecheck`, `build`; container job builds the image, boots Compose for a
create → reveal → gone smoke test, runs the committed browser E2E, runs the load test,
then runs `script/preflight_selftest.sh` so the go-live gate keeps failing on bad
configs. The self-test proves the gate both ways: it passes on a good stack and fails on a
bad certificate, a plain-HTTP 200, and a host-reachable Redis. That last case needs a
reachable Redis, so the self-test stack gets its own subnet (`PF_REDIS_SUBNET`, default
`172.30.99.0/24`) — on a hardened host the production subnet is denied to every host
process, which would otherwise make the case pass for the wrong reason. CI runs on every push (K-32 closed; the first real run found the load-test env
bug). CI currently runs `test`, `test:accounts`, `test:file`, `test:requests`, `test:webhooks`,
`test:states`, `test:mobile` and `test:a11y` — all eight committed journeys run in CI (the
`test:mobile` line is duplicated in `ci.yml`, a harmless protected-path wart). The SDK examples
**are** a CI step (`ci.yml:131-134`, `OTS_APP_IMAGE=oneshotlink-web bash script/test-examples.sh`);
`script/restore-drill.sh` remains a local gate — run `script/verify-deployment.sh` (§2) to cover
it. Adding further steps to CI requires editing `.github/workflows/`, a protected path, so it
needs operator approval. The security job also installs the rebrand sweep at the pinned replica-skill SHA
`77c9436` and runs `script/brand-sweep.sh`; the container job runs
`docker compose config --quiet` before building (T-109). Tests must not require network
access beyond gem/npm installs, image pulls, and that one pinned tool clone.
Future goal (not enabled): fail the build on any unhandled promise rejection or Ruby warning
promoted by `.rspec`. The current `.rspec` sets only `--require spec_helper`, `--format
documentation` and `--color`; adding `--warnings` today would flood the run with gem warnings.
