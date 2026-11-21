# Architecture

**Status:** v1 implemented and verified; this document defines the product scope, the target architecture of the **next increment**, and the boundaries that must not regress. Where this file and code disagree, the code wins and this file is corrected in the same change.

**Evidence standard:** every factual statement carries a file:line reference, a spec, or a command result. Status counts quoted here were executed on 2026-11-21: `307 examples, 0 failures` (RSpec in `ots-dev`, Redis DB 15), Vitest 35/35, `vue-tsc` clean, Vite build clean. Git HEAD is `741e71f` (T-118); `git diff --shortstat` now reports **227 staged files changed, 16086 insertions(+), 1576 deletions(-)** across hardening, research and planning work (working tree, not committed), so the descriptions below reflect the **working tree**, not HEAD. Four parallel reviews (architecture, database, backend/API, security) grounded in `.claude/agents/` informed this document.

Companion documents: [DATABASE.md](DATABASE.md) (key catalogue), [API.md](API.md) (contract), [SECURITY.md](SECURITY.md) and [SECURITY_AUDIT.md](SECURITY_AUDIT.md) (controls and findings), [FEATURE_MATRIX.md](FEATURE_MATRIX.md) (competitor comparison and priorities), [docs/DECISIONS.md](docs/DECISIONS.md) (why), [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) (execution).

## 1. Product scope

### 1.1 MVP — what OneShotLink already is (shipped, verified)

A self-hostable, single-use secret service with eight committed browser journeys and 307 backend specs:

- **Core loop:** create → opaque link → reveal once → gone, for text and a single file. `app.rb:832-857`, `e2e/journey.mjs:45-63`, `e2e/file.mjs:29-80`.
- **Confidentiality:** AES-256-GCM at rest with HKDF-derived per-record keys, random salt/IV, 16-byte tag, server-held `SECRET`. `crypto.rb:24-64`, `models/secret.rb:38-59`.
- **Single-use invariant:** atomic Lua compare-and-delete, verified before deletion; 8-way race yields one winner. `store.rb:43-63`, `secrets_api_spec.rb:134-147`.
- **Passphrase:** Argon2id access gate with 8-byte floor, wrong guess never consumes. `conceal_secret.rb:12,91-93`, `reveal_secret.rb:31-39`, `e2e/journey.mjs:65-88`.
- **TTL:** Redis expiry only; defaults 30 min / 12 h / 1 d / 3 d. `config.rb:18`, `models/secret.rb:107-122`.
- **Anonymous + simple accounts:** opaque SHA-256-digested sessions, owner receipts, dashboard, CSRF/origin proof. `app.rb:405-481,682-748`, `models/session.rb`.
- **Two API versions:** frozen v1 (form/JSON, `{"message":...}` errors, destructive GET) and native-JSON v3 (GET preview, POST reveal). `app.rb:532-563,606-628,832-892`.
- **Operations:** non-root read-only image, Compose with authenticated Redis on an internal network, fail-closed boot config, redacted logs, 16 rate-limit scopes, `/metrics`, audit stream, backup/restore, in-place key rotation, signed webhook queue with an external worker, inbound secret requests, OpenAPI document and SDK examples. `compose.yaml`, `bin/ots`, `webhook.rb`, `backup.rb`, `audit.rb`, `openapi.rb`, `docs/SDK.md`.

### 1.2 Next increment — scope (from FEATURE_MATRIX §5)

**P0 — contract and data safety (no new product surface):**
1. OpenAPI fidelity: complete `LegacyError` coverage for v1 429/503, document `/metrics`, fix the bidirectional mount gate, document the v1 form body and missing status codes. `openapi.rb:344,352,358,364-379,397-408,431-434`; `openapi_spec.rb:25-36`.
2. Backup/restore coverage for `request:object:*`, `request:secret:*`, `webhook:endpoint:*`, `webhook:delivery:*`; narrow the restore allowlist; bump format with backward compatibility. `backup.rb:18-25,102-118`.
3. Migration substrate — **DONE 2026-11-21:** `Onetime::Migrate` owns `schema:version`; `bin/ots migrate [--dry-run]` applies idempotently. `lib/onetime/migrate.rb`, `DATABASE.md` §8.
4. Bounded security defects — **partial:** post-consume cleanup and the dropped-audit counter landed (`reveal_secret.rb:41-50`, `audit.rb:52-62`, `metrics.rb`); endpoint-scoped deliveries are still open (`webhook.rb:193-212`, protected `app.rb` needs approval).

**P1 — needs a recorded product decision first:** separate receipt token/status/burn; per-secret passphrase attempt budget (revisits D-012); bearer API tokens; `ots conceal`/`ots reveal` calling the HTTP API.

**P2:** password generator + QR/`mailto:` share, larger/multi-file with sanitized previews, richer inbound requests, `/llms.txt` + generated types, i18n.

**Not in this increment:** FEATURE_MATRIX #9a (B9 clipboard fallback, B10 TTL source, B11 dark-mode doc/code contradiction, B14 focus/copy) and B12 (no HTTP/CLI read path for `Audit.recent`) are deliberately deferred; they are pure-frontend polish or operator tooling and do not gate the security/contract work above. The four-review pass also required **P0-5** (metadata-MAC downgrade + request-object signature): the secret-record half is **DONE 2026-11-21** (`verify_meta!` rejects `v != 3` and missing MACs); the request-object HMAC is also shipped (T-130), so no P1 work has started.

### 1.3 Future roadmap and explicit non-goals

Sequenced by dependency: contract fidelity → backup/migrations → product decisions → P1 features → P2 polish → repeat the go-live gate. `IMPLEMENTATION_PLAN.md` owns dates, milestones and acceptance criteria.

**Non-goals (do not silently implement):** full auth/SSO/MFA/RBAC/IP allowlisting (D-003/T-60; `AUTH_MODE=full` stays 501); organizations, custom domains, billing; client-side encryption or any "zero-knowledge" copy (D-012); a second datastore or ORM (D-002); discussions, Markdown formats, JSON-LD client compatibility, public SaaS/multi-region; view-count/multi-view budgets until semantics are decided; 27-locale i18n.

## 2. Runtime shape

```
Browser (Vue 3 SPA, Zod client)
   │  JSON v3 / form+JSON v1
   ▼
TLS-terminating proxy (OPERATOR, not bundled — T-70)
   ▼
Puma ── HeadRequests ── RequestLogger ── Roda App (one class)
   │       405 for v1 secret HEAD   redacted log   routes/auth/limits/errors
   │
   ├── Logic objects (lib/onetime/logic/*) — domain validation + orchestration
   │      ConcealSecret RevealSecret SignUp SignIn DeleteAccount RotateKey
   │      Create/Submit/RevealSecretRequest
   ├── Models (lib/onetime/models/*) — key builders, Redis shapes, atomic ops
   │      Secret Customer Session SecretRequest
   ├── Store (redis-rb 5) — Lua CAS consume / rewrite / hash-field rewrite
   └── Crypto · Password · Ids · Limiter · Audit · Metrics
          │
          ▼
      Redis 7 (secrets, receipts, sessions, limits, audit, webhook queue)
          ▲
          └── bin/ots webhooks:work — EXTERNAL worker, operator-scheduled (K-46)

CLI bin/ots (operator, inside trust boundary): customers, health, backup,
restore, rotate-key, webhooks:work — no secret create/reveal command today.
```

There is **no in-process scheduler**: `webhook.rb:136-191` implements queue/claim/deliver, `bin/ots:136-144` invokes it, and the operator must schedule it. Redis TTL handles expiry (D-008), so no sweeper is needed. The web process is stateless: all state in Redis, Puma workers reset the client on fork (`config/puma.rb:9-16`).

## 3. Component map (verified against working tree)

| Component | Responsibility | Evidence |
|---|---|---|
| `config.ru`, `config/puma.rb` | Fail-closed boot (`Config.validate!`), middleware order, workers/threads | `config.ru:8-23`, `config/puma.rb:5-19` |
| `lib/onetime.rb` | Single entrypoint; requires audit, webhook, secret_request(s) too | `lib/onetime.rb:5-27` |
| `config.rb`, `errors.rb` | Env validation, 16 rate scopes, typed errors (incl. uniform 404, 501) | `config.rb:45-178`, `errors.rb:16-89` |
| `crypto.rb`, `password.rb`, `ids.rb` | AES-256-GCM + HKDF, Argon2id/bcrypt legacy, 128-bit IDs + digests | `crypto.rb:24-72`, `password.rb:13-32`, `ids.rb:12-23` |
| `store.rb`, `limiter.rb` | Bounded Redis client; Lua consume/rewrite CAS; fixed-window limiter | `store.rb:13-95`, `limiter.rb:14-47` |
| `models/secret.rb` | Encrypted record + receipt + owner index; v3 metadata MAC | `secret.rb:11-123` |
| `models/customer.rb`, `session.rb` | Atomic customer create, dummy hash; digest-only sliding sessions | `customer.rb:12-118`, `session.rb:15-110` |
| `models/secret_request.rb` | Request object + `SET NX` submission + owner zset | `secret_request.rb:12-76` |
| `logic/*` | One class per use case; pure rules; webhook emission at the edge | `logic/conceal_secret.rb:31-61`, `logic/reveal_secret.rb:22-54`, `logic/secret_requests.rb:6-115` |
| `web/app.rb` | One Roda class; routes `636-1010`, error handler `1012-1055`; limits, body caps, headers, envelopes | `app.rb:636-1055` |
| `web/openapi.rb`, `openapi_spec.rb` | Served OpenAPI 3.1 (paths `37-542`, components `544-908`, 909 lines total) + mount gate | `openapi.rb:14-909`, `openapi_spec.rb:25-36` |
| `web/head_requests.rb`, `request_logger.rb` | HEAD safety; one redacted log line per request | `head_requests.rb:15-51`, `request_logger.rb:9-56` |
| `audit.rb`, `metrics.rb`, `webhook.rb`, `backup.rb` | Audit stream, Prometheus text, signed webhooks, export/restore | respective file headers |
| `frontend/` | Vue 3 + TS + Vite + Zod; 7 routes; no localStorage/sessionStorage | `router.ts:12-19`, `lib/api.ts:3-290` |
| `bin/ots` | Operator CLI; no conceal/reveal command | `bin/ots:183-247` |
| `spec/`, `e2e/`, `script/`, `site/` | RSpec DB-15 guard, eight committed journeys, ops scripts, static site | `spec_helper.rb:28-48`, `e2e/*.mjs` |

**Historical reconciliation (T-87…T-93) is complete.** `TASKS.md` is the status of record; current claims in this document have been re-checked against source and executed gates (307 specs / 35 Vitest / 8 journeys).

## 4. Layer boundaries and responsibility split

- **HTTP edge (`web/app.rb`)** owns media type (`application/json` exact, `app.rb:248-259`), body caps on JSON and form/chunked paths (`:241-283`), auth gates (`:430-481`), CSRF/origin proof (`:437-474`), rate limits and `X-RateLimit-*`/`Retry-After` (`:204-239`), response shaping and error envelopes (`:59-74,1012-1055`). It emits audit identifiers only (`:199-202`).
- **Logic (`logic/*`)** owns domain values: TTL allowlist, size/passphrase/file validation, passphrase verification and the reveal ordering. It raises `Onetime::Error` subclasses; it does not write Redis directly except through models. Webhook emit is the one side effect and is best-effort (`webhook.rb:113-134`).
- **Models + Store** own key builders, serialization, TTLs and atomic Lua scripts. No ORM, no generic repository (D-002).
- **Do not** move decryption after consume, add an in-process job thread, or introduce a second datastore. Side effects that can fail after the consume must be wrapped or moved before it (SA-06).

## 5. Data architecture

Redis is the only datastore (D-002/D-004). Verified key catalogue — full field detail in [DATABASE.md](DATABASE.md):

| Prefix | Type | TTL | Writer → Reader |
|---|---|---|---|
| `secret:object:<objid>` | string (JSON, `v=3`, MAC) | secret ttl | `secret.rb:107-121` → `reveal_secret.rb:24`, `backup.rb:120-130` |
| `secret:receipt:<objid>` | hash | secret ttl | `secret.rb:110-119` → `app.rb:488-503` |
| `customer:<id>:secrets` | zset | none | `secret.rb:120` → `app.rb:488` |
| `customer:<id>`, `customer:index:<sha256(email)>` | hash / string | none | `customer.rb:18-28` → `customer.rb:61-68` |
| `session:<sha256(token)>`, `customer:sessions:<id>` | hash / set | 14 d sliding | `session.rb:22-31,53-110` |
| `request:object:<key>`, `request:secret:<key>`, `customer:<id>:requests` | string / string(NX) / zset | request ttl | `secret_request.rb:22-76` |
| `webhook:endpoint:<id>`, `webhook:owner:<id>`, `webhook:queue`, `webhook:delivery:<id>`, `webhook:seen:*`, `webhook:inflight:*` | hash / zset / zset / hash / string / string | endpoint none; queue/delivery 7 d; seen 7 d; inflight 120 s | `webhook.rb:55-212` |
| `limiter:<client>:<scope>`(+`:counter`), `audit:events` | string / stream | 60 s; MAXLEN ~100k, no TTL | `limiter.rb:14-24`, `audit.rb:12-56` |

**Invariants that must not regress** (each has a passing spec): object records stay JSON strings for exact-byte CAS (`store.rb:43-63`; D-004); the Lua comparison is unconditional (`store.rb:52`); verify → decrypt → consume (`reveal_secret.rb:31-39`; D-005/D-013); metadata MAC covers `v kind filename owner_id created_at ttl passphrase_hash ciphertext` (`secret.rb:21,78-95`) and is re-signed on rotation (`rotate_key.rb:66`); `SET NX` for one-answer requests (`secret_request.rb:66`); `KEEPTTL`/`HSET` for CAS rewrites (`store.rb:69-89`); multi-key writes in one `MULTI`/Lua (`secret.rb:107-122`, `customer.rb:18-28`, `delete_account.rb:24-52`); no plaintext at rest or in logs; DB-15-only test isolation (`spec_helper.rb:28-48`).

**Historical gaps from the four-review pass, all closed:** format-2 backups now include request/webhook namespaces; restore uses a namespace allowlist; `Onetime::Migrate` owns `schema:version`; owner zsets and webhook queue/delivery carry TTLs; audit has a dropped-write counter; `request:object` MACs are verified and renewed on rotation (SA-41). No expand→migrate→contract work is pending.

### 5.1 Corrections from the four-review pass (2026-11-21)

The architecture/database/backend/security reviewers added these repository-evidenced findings; they refine, not replace, the map above:

| Finding | Evidence | Consequence for the plan |
|---|---|---|
| `DATABASE.md` catalogue covers roughly half the live keyspace: missing `request:object:*`, `request:secret:*`, `customer:<id>:requests` and all six `webhook:*` families. `viewed_at` in §4 is phantom (`secret.rb:110-118` writes only `viewed`). §7 wrongly says `Backup.export` contains session tokens — it explicitly excludes `customer:sessions:` (`backup.rb:148-153`); the AOF/RDB note is a different mechanism. | `secret_request.rb:12-14`, `webhook.rb:28-34`, `backup.rb:120-169` | Regenerate the key catalogue from code in the P0-2 change, not from prose. |
| Backup restore can make a near-expiry record permanent: export encodes `ttl.positive? ? ttl : 0` and restore with `ttl<=0` does a bare `SET` and skips `EXPIRE` (`backup.rb:63-67,74-75,127,142`). Restore is sequential, not transactional. | `backup.rb:59-93,120-169` | P0-2 must add an explicit `no_ttl` flag and a dry-run on a copy; a TTL-less restore breaks the TTL invariant. |
| A submitted answer gets the request's **full** TTL, not its remaining TTL, so it can outlive the request by up to one window. | `secret_requests.rb:72` uses `record["ttl"]` instead of `TTL request:object:<key>` | Bound submissions by remaining TTL in the same change that adds request backup coverage. |
| Per-process metrics with two Puma workers (`compose.yaml:73`) means a single scrape of one published port reaches an arbitrary worker, exposing a subset, not cluster totals. `/metrics` is now token-gated and rate-limited (`app.rb:676-683`). | `metrics.rb:4-8`, `app.rb:594-604`, `FEATURE_MATRIX.md:80,132` | Record a scrape/aggregation decision in `docs/DECISIONS.md` (P0 ops); do not add a metrics library. |
| `docs/DECISIONS.md:14-16` (D-001) claims "versioned sub-apps under `apps/api/`"; no `apps/` directory exists — all routes are in `app.rb:15`. | `docs/DECISIONS.md`, `app.rb:15,636-1010` | Historical note only: the ADR text was reconciled in T-87; the Roda decision stands. |
| `Webhook.emit` swallows all `StandardError` (`webhook.rb:131-134`); an orphan queue item is still recoverable because delivery state is HSET lazily. Delivery keys and owner zsets have no TTL. | `webhook.rb:28-35,113-134,193-212` | Include queue/delivery retention and queue-liveness alerting in the K-46 operator decision. |
| **The metadata MAC had a downgrade path (historical P0-5, now closed).** `verify_meta!` used to return early for `v < 2`; a Redis writer could strip `passphrase_hash`/`meta_mac` and reveal without a passphrase. | `models/secret.rb:119-137`, `reveal_secret.rb:27-36` | **Fixed:** strict `v == 3` gate with no legacy window (SA-41). Specs now expect a typed error for unsigned/downgraded/ciphertext-transplanted records. This row is kept as history, not as current state. |
| `peek_payload` reads metadata without `verify_meta!`, so a tampered `filename`/`kind` is displayed even when reveal would reject it (`app.rb:298-314`). | `app.rb:298-314`, `models/secret.rb:78-94` | Add MAC verification to the preview path in P0-5; no plaintext is returned either way. |
| Request capabilities are sent to owner webhooks (`secret_requests.rb:23,89,124`), while the audit stream stores only a truncated SHA-256 reference (`app.rb:232-234`). Read `webhook.rb:14-19` as "no plaintext, ciphertext, passphrases or signing tokens" — opaque identifier keys are included. | `app.rb:357,364`, `secret_requests.rb:23`, `webhook.rb:14-17` | Qualify the claim as "no plaintext, secret keys are included as identifiers"; decide whether to hash those identifiers in P0-2. |

## 6. API contracts

- **Versioning policy:** v1 is a frozen legacy contract (form **and** JSON input, `{"message":...}` errors, destructive GET, HEAD refused with 405). v3 is native JSON and the sole home of new work; additive optional response fields are allowed; a breaking change must use a **new major prefix decided at that time** (no `/api/v4` prefix is committed today). `AUTH_MODE=full` remains 501. Basis: `API.md:7` ("v1 must remain backward compatible") and `PRD.md:149` ("v3 additive-only within a major") — the earlier `API.md §7` citation was wrong (that section is OpenAPI). `app.rb:532-563,606-628,832-892`.
- **Source of truth:** the runtime OpenAPI document at `/api/v3/openapi.json` (`app.rb:641-644`, `openapi.rb:14-35`). The gate at `openapi_spec.rb:25-36` must become bidirectional: reject the generic catch-all **body** (not any 404 — domain 404s are legitimate for substituted `somekey`) and add a reverse "mounted ⇒ documented" check (FEATURE_MATRIX B3).
- **Historical contract defects (all closed):** v1 `LegacyError` envelopes, `/metrics`, the v1 form body with 413/422, the degraded-health schema, 429/501/503 coverage, and endpoint-scoped webhook deliveries are all implemented and spec-checked; `openapi_spec.rb` enforces the mount gate. Public request preview/respond in default disabled mode is an intentional C2 decision, not a defect.
- **No generated client types and no `/llms.txt`** today; `docs/DECISIONS.md:160-163` (D-011) only notes that adding an MCP server would require a minimal tool config — it is **not** an implemented or explicitly rejected feature; do not claim `/mcp`. PrivateBin JSON-LD client compatibility is infeasible without browser-side encryption (`COMPETITOR_RESEARCH.md:126`).

## 7. Authentication and authorization

- **Session:** opaque 32-byte token in `ots_session` cookie (`HttpOnly`, `SameSite=Lax`, `Secure` under SSL, path `/`; `app.rb:18,405-414`); Redis stores only `SHA256("ots-session/v1:"+token)` (`session.rb:35-47`); sliding TTL via `EXISTS`-guarded `TOUCH_SCRIPT` (`session.rb:22-31`); revocation by `DEL`. No JWT, no signed cookies (D-007).
- **CSRF:** there is no CSRF token. `verify_csrf!` acts only when a session cookie exists, then requires full origin proof; applied to every cookie-authenticated mutation (`app.rb:437-474,674,698,728,756,775,781,798,819,835,863,870` — `:835` is the conditional `verify_csrf! if owner` on guest conceal). Headerless API clients bypass by design. Login/signup call `verify_request_origin!` derived from operator-controlled `Config.base_url`, so hostile `X-Forwarded-*` cannot steer it (`app.rb:442-466`; K-45).
- **Authorization:** owner scoping via `customer[:id]` from the session for receipts, requests and webhooks (`app.rb:487-506,319-383,752-830`); `Webhook.delete` checks `owner_id` (`webhook.rb:101-110`). Secret/request keys are 128-bit bearer **capabilities**, not API credentials. The `role` field is stored and returned (`customer.rb:25,88-100`) but **no `require_role!`, admin route or RBAC check exists** — treat it as inert data, not enforcement.
- **Not enforced:** RBAC/admin actions, IP allowlisting, SSO/MFA, bearer tokens, in-process worker, audit retention. The per-secret passphrase budget *is* enforced (D-012b: 5 guesses / 900 s, keyed by opaque secret id). Unlimited reads include `/metrics`, webhook deliveries GET, and several authenticated GETs (`account/me`, receipts, requests list/preview, webhook list — `app.rb:683-692,761-770,803-814`); the per-process metrics trade-off is recorded in `SECURITY_AUDIT.md` §14.3. `Config.rate_limit` raises for an unknown scope name rather than falling back — new scopes must be added to the whitelist explicitly (`config.rb:165-172`). Every new protected route must add least-privilege checks explicitly.

## 8. Security boundaries and invariants

Trust boundaries (evidence in [SECURITY_AUDIT.md](SECURITY_AUDIT.md) §1 and the security review):

1. **Browser ↔ TLS proxy (operator-owned).** No bundled terminator; HSTS only under `SSL=true` (`app.rb:567`); loopback bind (`compose.yaml:80`). Client IP is `REMOTE_ADDR` unless the peer is in `TRUSTED_PROXIES` (`app.rb:164-197`).
2. **Proxy → Puma/Roda.** Middleware order; redacted logs; exact media type; bounded bodies; typed errors; 9 Lua rate scopes.
3. **Roda → logic.** Domain validation in pure objects; typed errors; no request body in logs.
4. **Logic → models → Redis.** Encryption in one place; v3 metadata MAC (bound to ciphertext); atomic CAS; bounded timeouts; Redis auth/TLS/internal network (`compose.yaml:19-40,112-124`).
5. **CLI (trusted, privileged).** `bin/ots` has `SECRET` and Redis access; no HTTP boundary.
6. **Webhook worker (separate, operator-scheduled).** Creation-time + stored-IP validation, private-range check incl. mapped IPv6, `ipaddr` pinned before socket open, no redirects, HMAC-SHA256, metadata-only payloads (`webhook.rb:136-295`); escape hatch `WEBHOOK_ALLOW_PRIVATE=true`.

**Invariants any change must preserve:** verify→decrypt→consume; unconditional Lua CAS; no plaintext at rest/in **request logs** (capability identifiers are deliberately persisted in `audit:events` and webhook payloads — a separate, currently accepted sink that must never carry plaintext, passphrases or tokens); uniform 404; fail-closed config/boot; v3 MAC strictly rejects `v != 3` / missing MAC (P0-5 closed; there is no legacy early-return or downgrade window); D-012 copy rule (never "zero-knowledge"/"server cannot decrypt" — accurate copy: "AES-256-GCM at rest with an operator-held instance key; an optional Argon2id passphrase is an extra access check"); opaque IDs only; v3 GET never consumes; nothing irreversible before success.

**Open gates:** T-70 real TLS hostname, T-71 host Redis firewall, K-46 worker scheduling. SA-06 (cleanup alerting), SA-14/D-012b (per-secret budget), SA-16/D-retention (audit IPs) and SA-22 (backup coverage + schema marker) are closed; see `SECURITY_AUDIT.md` §13/§14. Public "production ready" copy is prohibited while T-70/T-71 are open.

## 9. Concurrency, consistency and failure modes

- One writer wins: Lua GET/compare/DEL (`store.rb:49-55`); creation and account deletion are transactional (`secret.rb:107-122`, `delete_account.rb:24-52`); session touch is atomic (`session.rb:22-31`).
- Owner-index pruning is lazy on dashboard read (`app.rb:487-505`); entries older than the 50-window are not pruned — a known growth path.
- Redis outage → typed 503 + `Retry-After`; bad `SECRET`/tamper → 500 with record intact; wrong passphrase → 401 with record intact; duplicate reveal → one 200, rest 404; oversized body → 413; rate limit → 429. See [SECURITY.md](SECURITY.md) §8.

## 10. Frontend architecture

Vue 3 Composition API + `<script setup>`, TypeScript strict, Vite build into `public/app` served by Rack (D-006). Seven routes in `router.ts:12-19`. `src/lib/api.ts` is the only `fetch` site; Zod parses every response; typed `ApiError`; no payload logging. State is local per view; no Pinia; no `localStorage`/`sessionStorage`/`indexedDB`; reveal requires an explicit click and there is no auto-reveal on mount (`RevealView.vue:9-12,32-57`). Strict CSP, hashed immutable assets, `no-store` shell.

## 11. Constraints and decision index

Ruby **≥3.2** (`Gemfile:5`; production image pins 3.3) / Rack 3.2.8 / Roda 3.109.0 / Puma 7.2.3; Redis 7+ (EVAL, SET EX, INCR, ZADD); no Rails, Sinatra, ActiveRecord, second framework or ORM; Vue 3 / Vite 6 / TS 5.7 / Tailwind 4 / Zod 4; Docker + Compose; env-only config; no secrets in the image; one Redis DB in production, DB 15 only in tests. Decisions: D-001 Roda, D-002 no ORM, D-003 deferred full auth, D-004 JSON-string records, D-005/D-013 reveal ordering, D-006 SPA served by Rack, D-007 opaque sessions, D-008 TTL-only expiry, D-009 Argon2id, D-010 evidence-based status, D-011 no project tool config, D-012 passphrase gate, D-014 8-byte floor, D-015 patch-in-constraint. New gem/npm requires a `docs/DECISIONS.md` entry and canonical check (AGENTS rule 8).

## 12. Evidence appendix

| Claim | Command / artifact |
|---|---|
| Backend suite | `docker run --rm --network=host -v "$PWD":/app -v ots-bundle:/bundle -e BUNDLE_PATH=/bundle -e REDIS_URL=redis://127.0.0.1:6398/15 -w /app ots-dev bundle exec rspec` → `307 examples, 0 failures` |
| Frontend | `npm --prefix frontend run test` → 35 passed; `vue-tsc --noEmit` clean; `npm run build` clean |
| Atomic single-use | `spec/integration/secrets_api_spec.rb:134-147` (8 threads → one winner) |
| Reveal ordering | `spec/integration/secrets_api_spec.rb:113-131,189-206`, `security_hardening_spec.rb:32-79` |
| Rotation CAS | `spec/unit/ops_spec.rb:28-93` |
| Competitor research | [COMPETITOR_RESEARCH.md](COMPETITOR_RESEARCH.md) (VERIFIED/PARTIAL/UNKNOWN labels) |
| Priorities | [FEATURE_MATRIX.md](FEATURE_MATRIX.md) §5 |
| Product-engineering artifact | `docs/roadmap-posture.html` + `.png` (stageshow still, rendered 1030×560, 0 page errors) |
| Four-review verification (2026-11-21) | architecture / database / backend-API / security reviewers re-read this document against source; their corrections (MAC downgrade → P0-5, `no_ttl` + remaining-TTL steps → P0-2, body-based mount gate, D-metrics, protected-path/P2-3 approval, Ruby constraint, MCP citation) are applied in §1.2, §5.1, §6–§8 and `IMPLEMENTATION_PLAN.md`. No phase introduces Rails/Sinatra/ActiveRecord, a second datastore or a new gem without a `docs/DECISIONS.md` entry. |
