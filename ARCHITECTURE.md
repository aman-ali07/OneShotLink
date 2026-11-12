# Architecture

Status: v1 architecture implemented — secret lifecycle, simple-mode accounts, the Vue
vertical slice and production packaging. Where this file and the code disagree, the code
wins and this file gets fixed. Cross-check [DATABASE.md](DATABASE.md), [API.md](API.md) and
[docs/DECISIONS.md](docs/DECISIONS.md).

## 1. Shape

```
Browser (Vue 3 SPA)
   │  JSON (v3) / form (v1)
   ▼
Puma ── Rack 3 ── HeadRequests ── RequestLogger ── Roda app
   │                ├─ static UI (public/app)
   │                ├─ API v1 + v3 (one Roda class; split only if it grows)
   │                └─ health, config, metrics, /api/v3/openapi.json
   │
   ├── Logic objects (lib/onetime/logic/*): ConcealSecret, RevealSecret, SignUp,
   │   SignIn, DeleteAccount, RotateKey
   │
   ├── Models (lib/onetime/models/*): Secret (record + receipt), Customer, Session
   │      └── Onetime::Store (redis-rb 5)  ── Redis (secrets, sessions, limits)
   │
   └── Crypto (AES-256-GCM), Limiter (Lua), Password (Argon2id)

HTTP edge → Roda routes validate input, apply rate limits, map errors to JSON.
```

There is no background worker in v1. Expiry is Redis TTL; nothing needs a job.
A future full mode adds PostgreSQL + RabbitMQ behind the same logic objects.

## 2. Components

| Component | Responsibility | Status |
| --- | --- | --- |
| `lib/onetime/config.rb` | Env-driven settings, validation, derived values | Implemented |
| `lib/onetime/errors.rb` | Typed errors with HTTP status + stable code | Implemented |
| `lib/onetime/crypto.rb` | AES-256-GCM encrypt/decrypt, HKDF, constant-time compare, record format | Implemented + tested |
| `lib/onetime/store.rb` | Redis client, JSON helpers, atomic consume script | Implemented + tested |
| `lib/onetime/limiter.rb` | Fixed-window rate limiting in Lua | Implemented + tested |
| `lib/onetime/password.rb` | Argon2id create/verify, bcrypt legacy verify | Implemented + tested |
| `lib/onetime/ids.rb` | Opaque IDs, hashed indexes, session tokens | Implemented + tested |
| `lib/onetime/models/secret.rb` | Persist/consume secret object + receipt; owner index | Implemented + tested |
| `lib/onetime/models/customer.rb` | Customer create/find/auth/password update; atomic email uniqueness | Implemented + tested |
| `lib/onetime/models/session.rb` | Opaque session token, SHA-256 Redis key, sliding TTL | Implemented + tested |
| `lib/onetime/logic/sign_up.rb`, `sign_in.rb` | Validation and credential check; session issuance | Implemented + tested |
| `lib/onetime/logic/conceal_secret.rb`, `reveal_secret.rb` | Validation and verify→consume→decrypt ordering | Implemented + tested |
| `lib/onetime/web/app.rb` | Routes, limits, error mapping, headers, static SPA, fallback | Implemented + tested |
| `lib/onetime/web/request_logger.rb` | One redacted request log line per request | Implemented + unit-tested |
| `lib/onetime/web/head_requests.rb` | Serve HEAD through GET routes, strip body | Implemented + tested |
| `frontend/` | Vue 3 SPA, Zod API client, conceal/reveal views, design tokens | Implemented + browser-verified |
| `spec/` | RSpec unit + rack-test integration against Redis DB 15 | Implemented (94 examples) |
| `lib/onetime/models/organization.rb`, `receipt.rb` | Organizations and a separate receipt model | Deferred; receipt lives in `secret.rb` for now |
| `apps/api/v1.rb`, `apps/api/v3.rb` | Roda sub-apps | Not needed yet; one app class |
| `bin/ots` | CLI: customers (create/list/show/set-role/reset-password), health, backup, restore, rotate-key, version | Implemented and shipped in the image |
| `frontend/` | Vue SPA (see §6) | Implemented (M2) |
| `Dockerfile`, `compose.yaml`, `.github/workflows/ci.yml` | Self-host packaging and CI | Implemented + smoke-tested |

## 3. Folder layout (as built)

```
config.ru                   # boots Config.validate! then the Roda app
config/puma.rb              # PORT, workers, threads, worker timeout
Gemfile / Gemfile.lock
lib/onetime.rb              # single entrypoint: requires everything
lib/onetime/
  audit.rb backup.rb config.rb crypto.rb errors.rb ids.rb limiter.rb
  metrics.rb password.rb store.rb version.rb
  logic/                    # one class per use case
    conceal_secret.rb reveal_secret.rb sign_up.rb sign_in.rb
    delete_account.rb rotate_key.rb
  models/                   # Redis shapes; key builders live here
    secret.rb customer.rb session.rb
  web/
    app.rb                  # all Roda routes, for both API versions
    openapi.rb              # /api/v3/openapi.json, asserted against the routes
    head_requests.rb request_logger.rb
bin/ots                     # operator CLI: health, backup, restore, rotate-key, customers
frontend/
  index.html vite.config.ts tsconfig.json package.json
  src/main.ts App.vue router.ts
  src/views/                # ConcealView RevealView DashboardView SignInView SignUpView NotFoundView
  src/components/           # AppHeader AppFooter AppButton AppAlert CopyButton
  src/lib/api.ts api.test.ts
  src/assets/styles.css
public/app/                 # Vite build output, served by Rack (git-ignored)
spec/
  spec_helper.rb            # DB 15 guard: refuses a shared Redis
  integration/              # web, secrets_api, accounts, metrics, openapi
  unit/                     # crypto, password, ids, limiter, store, session, config,
                            # metrics, ops, request_logger
site/                       # static marketing/legal pages + generated icons and og.png
script/                     # brand-sweep, build-assets, preflight, tls-rehearsal, loadtest
docs/DECISIONS.md
Dockerfile compose.yaml .env.example
```

`apps/api/v1.rb`, separate v1/v3 modules, `organization`/`custom_domain` models and a
`docker-compose.full.yml` were planned and are **not** in the tree: both API versions are
routes in `lib/onetime/web/app.rb`, organizations and custom domains are out of scope
(P2 in `TASKS.md`), and full mode is unimplemented by decision (D-012).

**Deviation from the original brief:** Otto 2 and Familia v2 are not publicly available
as documented for this stack, and bringing them in would couple the app to unavailable
internals. The project uses plain Roda on Rack 3 and a small explicit Redis mapping in
`lib/onetime/store.rb` + model modules. Rationale and consequences: D-001/D-002.

## 4. Data flows

### Create (conceal)

1. Client `POST /api/v3/guest/conceal` with `{secret, ttl, passphrase?, kind?}`.
2. Roda route validates size (≤ 1 MiB), TTL (must be in `TTL_OPTIONS`), passphrase
   length (if present), and applies the conceal rate limit (IP, or account when signed
   in).
3. `ConcealSecret` generates `objid = Ids.extid` (128 bits), hashes the passphrase with
   Argon2id (if any), encrypts the content with `Crypto.encrypt`, and writes:
   - `secret:object:<objid>` = JSON of the encrypted record, `EX ttl`
   - `secret:receipt:<objid>` = metadata record, `EX ttl`
   - ZSET entry for the owner (simple mode only)
4. Response: `201 {secret_key, receipt:{identifier, secret_ttl, passphrase_required, kind}, links:{secret}}`.
   The plaintext is never echoed. Exact shapes: [API.md](API.md) §5.1.

### Reveal (consume)

1. Client `GET /api/v3/guest/secret/:key` or `POST .../:key/reveal {passphrase}`.
2. Rate limit by IP.
3. Read the JSON record. Missing → `404` (same error for expired, consumed, unknown, so
   callers cannot enumerate).
4. If `passphrase_hash` is present: verify with `Password.verify`. Failure → `401`, and
   **no deletion**.
5. Decrypt with the instance `SECRET`. A tampered record or a rotated key makes this
   raise → `500` with a generic message and only the record ID logged; **nothing is
   deleted**, so rotating the key back makes the secret readable again.
6. `Store.consume(key, serialized_record)` runs the Lua compare-and-delete. If it
   returns 0, another request already consumed the record → `404`.
7. Delete the receipt and the owner-index entry; return the plaintext once.

The order (verify → decrypt → consume) is deliberate: the two checks that can fail are
pure, so they run before the one irreversible step. A wrong passphrase, a wrong `SECRET`
or a corrupt record therefore costs nothing, while the atomic consume still guarantees
exactly one winner. See D-005.

### Expiry

Redis removes `secret:object:*` and `secret:receipt:*` at TTL. Owner ZSET entries are
pruned lazily when the dashboard lists receipts (missing records are dropped). No cron.

## 5. Concurrency and consistency

- **One writer wins:** the Lua script in `Store.consume` compares the full serialized
  value and deletes only on an exact match. Any concurrent mutation (not expected)
  also loses, which is the safe direction.
- **Creation is transactional.** `Secret.write` queues the encrypted record, its receipt
  and the owner-index entry in one `MULTI`/`EXEC`, so a crash cannot leave a receipt without
  its secret. Account deletion is transactional for the same reason
  (`Logic::DeleteAccount`). Owner-index pruning on the dashboard is still lazy.
- **Sessions:** opaque random token in an `HttpOnly`, `SameSite=Lax` cookie (`Secure`
  under SSL); Redis stores only `session:<sha256(token)>` with a sliding TTL. No signed
  cookies, no JWT. Account routes fail closed (`403` when disabled, `501` in full mode).
- **Owner receipts:** simple mode writes `customer:<id>:secrets` on conceal when a
  session is present; the atomic reveal removes the member. The dashboard never receives
  plaintext.
- **Rate limits:** fixed 60-second windows. Bursts at a window boundary are possible;
  rejected requests still increment the counter (fail-closed).

## 6. Frontend architecture

- Vue 3 Composition API + `<script setup>`, TypeScript strict with
  `noUncheckedIndexedAccess`.
- Current views: `views/ConcealView.vue`, `RevealView.vue`, `NotFoundView.vue`. Components
  are shared primitives (button, alert, copy, header/footer). Account/org views are M3+.
- `src/lib/api.ts` holds Zod schemas and is the only place that calls `fetch`; it parses
  every response, maps the server error envelope to a typed `ApiError`, and never logs
  payloads.
- State is local to each view; no Pinia yet. Secret plaintext stays in memory and is
  discarded on navigation. No auto-reveal on mount.
- Vite dev proxies `/api` and `/health` to `http://127.0.0.1:3100` by default
  (`VITE_API_PROXY` overrides).
- Production build is served by Rack from `public/app`; hashed assets are immutable,
  the shell is noindex and CSP-restricted.

## 7. Technical constraints

- Ruby ≥ 3.2 (declared by `Gemfile`); production image pins Ruby 3.3.
- Rack 3 + Roda; no Rails, no Sinatra, no ActiveRecord/Sequel.
- One Redis database for the app; tests use DB 15 only.
- HTTP only behind a TLS-terminating proxy; `SSL=true` makes cookies `Secure` and
  generates `https://` links.
- The app is stateless apart from Redis; any instance can serve any request.
- `SECRET` is instance-wide. Rotation is non-destructive: `bin/ots rotate-key` re-encrypts
  existing records under the new key and preserves TTLs (T-65, D-013). Deleting and
  regenerating `SECRET` instead would invalidate everything — don't.
- No plaintext ever crosses the Redis boundary; logs carry IDs only.

## 8. Failure modes

| Failure | Behavior |
| --- | --- |
| Redis down | `/health` 503 `degraded`; writes answer 503 `service_unavailable` with `Retry-After` on both API versions; no partial writes; recovers without a restart when Redis returns |
| Missing/invalid `SECRET` | Boot fails fast in `config.ru` (verified) |
| Wrong passphrase | 401, record preserved |
| Tampered ciphertext | Decrypt fails **before** the consume: 500 generic and the record is left in place (D-013) |
| Duplicate reveal | One 200, others 404 |
| `AUTH_MODE=full` | 501 `not_configured` on auth-dependent routes |
| Oversized secret | 413 `payload_too_large`, exact boundary verified (accepts N, rejects N+1) |
| Rate limit exceeded | 429 `rate_limited` with `Retry-After` (verified) |
