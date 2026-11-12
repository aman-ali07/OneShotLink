# Testing

> **Status: 118 backend examples, 0 failures (2026-11-12), plus two verified headless
> browser journeys and a Compose smoke test.** Ruby/Bundler are not installed on the
> host, so backend tests run in the `ots-dev` Docker image against Redis DB 15. Lifecycle,
> passphrase, TTL, at-rest encryption, concurrency, v1, rate limits, and simple-mode
> accounts are implemented. The Vue build/typecheck passes, Vitest covers the API client,
> and `e2e/journey.mjs` plus `e2e/accounts.mjs` are the committed browser journeys.

## 1. Strategy

- **Integration-first for the lifecycle.** The product's contract is HTTP behaviour, so
  specs drive Roda through `rack-test` and a real Redis (DB 15). No mocking of Redis:
  the atomic consume script *is* the behavior under test.
- **Unit specs for pure logic.** Crypto, IDs, password hashing, limiter math, config
  parsing. No network.
- **Frontend:** Zod schemas get unit tests (Vitest); TypeScript strict + build is the gate.
  Two committed browser journeys (puppeteer-core) cover the lifecycle and the account flow.
- **No tautological tests.** Assert on responses, Redis state, and error codes — not on
  mocks created in the same example.
- **Red → green.** Add a failing spec for the bug first, then fix it. If a test was never
  seen failing, say so in the handoff.

## 2. Commands

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
npm --prefix frontend run test        # vitest: 11 tests (schema + error mapping)
npm --prefix frontend run typecheck
npm --prefix frontend run build       # also the gate for the SPA shell in Rack
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
| `spec/unit/crypto_spec.rb` | 6 | round-trip, wrong key, tamper, unique IV/salt, no plaintext |
| `spec/unit/ids_spec.rb` | 4 | length/uniqueness/index normalization |
| `spec/unit/limiter_spec.rb` | 3 | ceiling, window reset, scope isolation |
| `spec/unit/password_spec.rb` | 4 | Argon2id, malformed hashes, bcrypt legacy |
| `spec/unit/store_spec.rb` | 4 | atomic win/lose, mismatch, empty expectation |
| `spec/unit/session_spec.rb` | 6 | digest-only storage, TTL refresh, destroy, revoke-all with exception, full revocation, per-customer isolation |
| `spec/unit/config_spec.rb` | 8 | boot validation, auth mode, proxy CIDRs, Redis URL scheme + password folding |
| `spec/unit/ops_spec.rb` | 8 | audit events/redaction, key rotation (re-encrypt, old key fails, TTL preserved), backup export/restore, sessions excluded |
| `spec/unit/metrics_spec.rb` | 7 | exposition format, counters by family/status, duration, Redis up + memory ratio, `METRICS_ENABLED` gate |
| `spec/unit/request_logger_spec.rb` | 3 | request fields, secret-key redaction, asset skip |
| `spec/integration/web_spec.rb` | 12 | health + Redis-down 503, datastore-outage 503 on both API versions (including a full Redis, not just a dropped one), config, CSP/HSTS, typed 404, SPA shell, HEAD |
| `spec/integration/secrets_api_spec.rb` | 23 | v3 create/reveal/gone, at-rest, passphrase, race, expiry, corrupted-record tamper survives, undecryptable record survives, v1 form+JSON, validation, 413 (declared and undeclared bodies), exact-size boundary, empty/1-char passphrase, 429, proxy trust, auth-disabled fail-closed, full-mode 501 |
| `spec/integration/accounts_spec.rb` | 23 | signup/cookie/at-rest, duplicate email, validation, signin/401, session TTL/deletion, signout, CSRF, owner isolation, password change, other-session revocation, atomic account deletion, audit trail, disabled/full gates |
| `spec/integration/metrics_spec.rb` | 3 | `/metrics` off by default (`404`), text exposition when enabled, no secrets in the output |
| `spec/integration/openapi_spec.rb` | 4 | valid 3.1 doc, `$ref`s resolve, documented paths are mounted, cookie scheme on owner/account routes |
| `frontend/src/lib/api.test.ts` | 11 | conceal/reveal payloads, typed errors, malformed responses, network failure, delete-account |
| `e2e/journey.mjs` | 1 journey | create → reveal → gone, wrong/correct passphrase, no console errors |
| `e2e/accounts.mjs` | 1 journey | signup → owner receipt → reload → signout → signed-out prompt → signin → delete account |

Backend total: **118 examples, 0 failures**; frontend: **11 Vitest tests, 0 failures**.
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

## 3.1 Frontend and browser evidence (M2)

- `npm --prefix frontend run build` → `vue-tsc --noEmit` clean, Vite build to
  `public/app` (≈208 kB JS, ≈14 kB CSS).
- Rack: `/` → `200 text/html`; `/assets/index-*.js` → `200 text/javascript`; deep links
  → the SPA shell; unknown API paths remain JSON `404`.
- Headless Chrome (puppeteer-core) completed: conceal → link → reveal → reload → gone,
  with `localStorage === "{}"` and no plaintext in the URL. The passphrase path was
  exercised with a wrong attempt (secret preserved) then the correct one.
- Responsive DOM audit: no horizontal overflow at 375, 768, or 1280 px.

Both journeys are committed (`e2e/journey.mjs`, `e2e/accounts.mjs`, puppeteer-core) and
run in CI against a live Compose stack; `lib/api.ts` has Vitest coverage. Sizes above are
from the current build (`index-*.js` ≈ 208 kB, `index-*.css` ≈ 14 kB).

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

Expected: `PREFLIGHT PASSED (1 skipped)`, then the reminder that DNS, the real certificate
chain and the Redis host firewall rule (T-71) remain the operator's to prove. `--with-redis`
currently ends in `FAIL: host can reach Redis` — that is the unfixed host rule, not a bug,
and it is the negative control showing the gate can still fail.

The rehearsal is not a substitute for the real run: with no DNS and a local CA it cannot
check name resolution or a public chain. Ports default to `13457`/`18443`/`18088`
(`APP_PORT`/`HTTPS_PORT`/`HTTP_PORT`); the stack, CA and proxy container are removed on exit.

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
- Fixed `SECRET` for specs (the 64-hex value above is a test fixture, not a deployment
  secret) so ciphertext is deterministic per run input.
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
bug). Tests must not require network access beyond gem/npm installs and image pulls.
Fail the build on any unhandled promise rejection or Ruby warning promoted by `.rspec`
(`--warnings` once clean).
