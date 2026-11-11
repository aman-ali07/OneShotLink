# Architecture

Status: v1 architecture with M1 (secret lifecycle), M2 (Vue vertical slice), and
production packaging implemented. Pieces not marked "implemented" remain planned. Cross-check [DATABASE.md](DATABASE.md),
[API.md](API.md), and [docs/DECISIONS.md](docs/DECISIONS.md).

## 1. Shape

```
Browser (Vue 3 SPA)
   │  JSON (v3) / form (v1)
   ▼
Puma ── Rack 3 ── HeadRequests ── RequestLogger ── Roda app
   │                ├─ static UI (public/app)
   │                ├─ API v1 + v3 (one Roda class; split only if it grows)
   │                └─ health + config (OpenAPI planned)
   │
   ├── Logic objects (lib/onetime/logic/*): ConcealSecret, RevealSecret,
   │   SignUp, SignIn, CreateOrganization, ...
   │
   ├── Models (lib/onetime/models/*): Secret, Receipt, Customer, Organization
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

## 3. Target folder layout

```
config.ru
Gemfile / Gemfile.lock
Rakefile
apps/
  api/v1.rb
  api/v3.rb
lib/
  onetime.rb                # requires everything; single entrypoint
  onetime/
    config.rb crypto.rb errors.rb ids.rb limiter.rb password.rb store.rb
    models/{secret,receipt,customer,organization,custom_domain}.rb
    logic/{conceal_secret,reveal_secret,sign_up,sign_in,...}.rb
    web/{app,helpers,security_headers}.rb
    openapi.rb
    version.rb
  tasks/                    # rake tasks
bin/ots
frontend/
  index.html vite.config.ts tsconfig.json package.json
  src/{main.ts,App.vue,router.ts}
  src/apps/{secret,workspace,colonel,session}/
  src/components/{base,forms,layout}/
  src/{composables,schemas,services,stores}/
  src/assets/styles.css
public/app/                 # Vite build output, served by Rack (git-ignored)
spec/
  spec_helper.rb
  integration/{secrets_api_spec.rb,health_spec.rb,auth_spec.rb}
  unit/{crypto_spec.rb,limiter_spec.rb,password_spec.rb,ids_spec.rb}
  support/{app_helper.rb,redis_helper.rb}
docs/
  DECISIONS.md openapi.json
Dockerfile docker-compose.yml docker-compose.full.yml
.env.example .dockerignore .gitignore
```

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
5. `Store.consume(key, serialized_record)` runs the Lua compare-and-delete. If it
   returns 0, another request already consumed the record → `404`.
6. Decrypt with the instance `SECRET`; delete receipt/index; return plaintext once.
7. If decryption fails after consuming (tampered record/key rotation), return `500` with
   a generic message and log only the record ID.

The order (verify → consume → decrypt) is deliberate: a wrong passphrase must not burn
the secret, and the decrypt happens on data we have already won the race for. See
D-005.

### Expiry

Redis removes `secret:object:*` and `secret:receipt:*` at TTL. Owner ZSET entries are
pruned lazily when the dashboard lists receipts (missing records are dropped). No cron.

## 5. Concurrency and consistency

- **One writer wins:** the Lua script in `Store.consume` compares the full serialized
  value and deletes only on an exact match. Any concurrent mutation (not expected)
  also loses, which is the safe direction.
- **Multi-key updates are not transactional.** Creation writes the secret, receipt, and
  owner index in sequence. Crash windows can leave orphaned receipts; they expire with
  the same TTL and are ignored when the secret is gone. Documented, accepted.
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
- `SECRET` is instance-wide: rotating it invalidates existing secrets (no re-encryption
  tool yet). Documented in DEPLOYMENT.md.
- No plaintext ever crosses the Redis boundary; logs carry IDs only.

## 8. Failure modes

| Failure | Behavior |
| --- | --- |
| Redis down | `/health` 503; API returns 500 `internal_error`; no partial writes |
| Missing/invalid `SECRET` | Boot fails fast in `config.ru` (verified) |
| Wrong passphrase | 401, record preserved |
| Tampered ciphertext | Consume wins, decrypt fails, 500 generic, record gone |
| Duplicate reveal | One 200, others 404 |
| `AUTH_MODE=full` | 501 `not_configured` on auth-dependent routes |
| Oversized secret | 413 `payload_too_large` (verified; exact 1 MiB edge pending) |
| Rate limit exceeded | 429 `rate_limited` with `Retry-After` (verified) |
