# PRD — OneShotLink

The brand is OneShotLink (R-09, `replica/brand.md`); this document still describes the
clean-room clone of the original one-time secret service and keeps that provenance.

Status: **M2 + production packaging implemented.** The secret lifecycle, browser
vertical slice, hardened image, simple-mode accounts, and the Compose stack are live; the
"Impl." column below is updated to the 2026-11-12 state. Evidence lives in `lib/onetime/`, `frontend/`, the
integration specs, a headless browser journey, and a Compose smoke test; unbuilt areas
are called out explicitly.

## 1. Problem

People need to send passwords, API keys, and private notes over channels they do not
trust (chat, email, tickets). Deleting the message later does not remove copies, and
screenshots/forwarding are outside the sender's control. A useful mitigation is a link
that can be opened once and then no longer exists.

The product provides that link: the sender pastes a secret, gets a URL, and the
recipient views it exactly once. The service stores only encrypted content, enforces a
TTL, and optionally requires a passphrase that travels over a different channel.

## 2. Target users

| Persona | Need | Success looks like |
| --- | --- | --- |
| Individual sender | Share a credential without leaving it in chat history | Paste, copy link, share; recipient opens once |
| Recipient | View without creating an account | Opens link, reads/copies, link is dead afterwards |
| Small team / self-hoster | Keep sensitive traffic in-house | Compose stack on own host, encrypted at rest |
| Operator / admin | Manage accounts, abuse, and health | CLI user creation, health endpoints, rate limits |
| Developer | Automate secret creation/retrieval | Stable v1/v3 API with documented errors |

## 3. Goals and non-goals

**Goals (v1)**

- Create, reveal-once, and auto-expire text secrets end to end.
- Encryption at rest with an instance-wide key that is never persisted with secrets.
- Atomic one-time reveal under concurrency.
- Guest use with no account, plus an optional simple account mode.
- Legacy-shaped API v1 and native-JSON API v3 used by the Vue UI.
- One-command self-hosting with Docker Compose and documented environment variables.
- Tests that prove the lifecycle, the crypto round-trip, expiry, and the reveal race.

**Non-goals (v1)**

- Full Rodauth/PostgreSQL/RabbitMQ auth (MFA, WebAuthn, magic links, SSO). Deferred; see
  [docs/DECISIONS.md](docs/DECISIONS.md) D-003.
- Organizations, custom domains, billing.
- File uploads (the data model reserves `kind`/`filename`, but no upload path ships).
- Email delivery and expiration-warning jobs.
- 27-language i18n. English-only strings; the i18n gem is declared but unused.
- Public SaaS operation, multi-region, or horizontal-session replication beyond Redis.

## 4. Functional requirements

Priority: P0 = v1 must ship, P1 = next, P2 = later. "Impl." reflects the repository
today (2026-11-11), not intent.

| ID | Requirement | Priority | Impl. |
| --- | --- | --- | --- |
| FR-1 | `POST /api/v1/share` creates a secret from form fields `secret`, optional `passphrase`, `ttl`; returns `secret_key` and receipt metadata (the UI builds the link from `HOST`). | P0 | Yes: form + JSON |
| FR-2 | `GET`/`POST /api/v1/secret/:key` reveals once and deletes the record. Second call returns 404. | P0 | Yes |
| FR-3 | `POST /api/v3/guest/conceal` and `/api/v3/secret/conceal` accept JSON (`secret`, `ttl`, `passphrase`, `kind`), return `{secret_key, receipt, links}` (`receipt.secret_ttl`). | P0 | Yes (owner alias anonymous only while auth disabled) |
| FR-4 | Reveal through `GET /api/v3/.../secret/:key` (no passphrase) or `POST .../:key/reveal` (passphrase). Passphrase failure returns 401 and does **not** consume. | P0 | Yes |
| FR-5 | Content is AES-256-GCM encrypted with a key derived from `SECRET`; Redis contains no plaintext. | P0 | Yes |
| FR-6 | Every secret has a TTL from `TTL_OPTIONS` (defaults 30 min, 12 h, 24 h, 3 d) and Redis expires it. | P0 | Yes |
| FR-7 | Reveal is atomic: exactly one of N concurrent requests wins, the rest get 404. | P0 | Yes: 8-way race spec |
| FR-8 | Creation and reveal are rate limited per client (defaults 30/min and 60/min). | P0 | Yes: `429` + `Retry-After` |
| FR-9 | Optional passphrase is hashed with Argon2id; legacy bcrypt hashes verify and rehash on use. | P0 | Partial: gate + Argon2id + bcrypt verify; rehash-on-login is M3 |
| FR-10 | IDs are opaque (≥128 bits from a CSPRNG); no sequential identifiers. | P0 | Yes: `ids.rb` |
| FR-11 | UI has conceal and reveal views, shows the one-time link, warns before reveal, and handles passphrase prompts. | P0 | Yes: browser journey verified; no auto-reveal |
| FR-12 | `AUTH_MODE=disabled` runs with Redis only and no sessions. | P0 | Yes |
| FR-13 | `AUTH_MODE=simple` adds signup/signin/signout with Redis-stored opaque sessions; owners can list active receipts. | P1 | Yes: account specs + `e2e/accounts.mjs` |
| FR-14 | `AUTH_MODE=full` returns 501 with a clear message (not implemented). | P1 | Yes: owner routes return `501 not_configured` |
| FR-15 | `GET /health` and `/api/v3/health` report app + Redis status; no secrets. | P0 | Yes |
| FR-16 | `bin/ots customers create --email ...` seeds an account; password is hidden/`OTS_PASSWORD`. | P1 | Partial: create/reset implemented; role/list/health flags still T-43 |
| FR-17 | OpenAPI 3.1 document served at `/api/v3/openapi.json` and written to `docs/openapi.json` on build. | P1 | No |
| FR-18 | CLI can list/retry dead-letter jobs in full mode. | P2 | No |
| FR-19 | Organizations, custom domains, SSO, MFA, WebAuthn, magic links. | P2 | No |
| FR-20 | File secrets (upload/download, encrypted, one-time). | P2 | No |
| FR-21 | Localized UI/emails (target 27 locales). | P2 | No |

## 5. User stories and acceptance criteria

**US-1 — Send a secret (guest)**
As a sender, I paste a secret, pick a TTL, and get a link I can share.

- Given I submit 1–1,048,576 bytes of text with a TTL from `TTL_OPTIONS`
- Then I receive `201` with an opaque `secret_key` (≥ 22 URL-safe chars) and a link
- And no plaintext appears in Redis or in the response body beyond what I submitted
  (the response contains metadata, not the secret)
- And an invalid/negative/non-allowed TTL returns `422` with `validation_error`

**US-2 — Reveal once**
As a recipient, I open the link and see the secret exactly once.

- Given a valid unviewed key, revealing returns the plaintext with `200`
- And the Redis record is deleted before the response is written
- And a second reveal returns `404 not_found`
- And two simultaneous reveals yield exactly one `200` and one `404`

**US-3 — Passphrase**
As a sender, I protect a secret with a passphrase.

- Given a secret created with a passphrase, reveal without it returns `401`
- And the record still exists afterwards (a failed attempt does not burn it)
- And the correct passphrase returns the plaintext once

**US-4 — Expiry**
As an operator, I rely on TTLs rather than cleanup jobs.

- Given a secret created with `ttl=60` (allowed only when configured), after expiry
  reveal returns `404`
- And Redis `TTL` reflects the remaining lifetime, not an epoch timestamp

**US-5 — Abuse control**
As an operator, I want brute-force and spam resistance.

- The 31st conceal request within a minute from one IP returns `429`
- The 61st reveal attempt within a minute from one IP returns `429`
- Limits are configurable through `RATE_LIMIT_*` and survive process restart (Redis)

**US-6 — Self-hosting**
As a self-hoster, I can run the stack with Docker.

- `docker compose up` starts web + Redis with AOF enabled
- The UI loads on `http://localhost:3000`
- `GET /health` returns `200` with `{"status":"ok","redis":"ok"}`
- Restarting the web container does not lose secrets (Redis persists)

**US-7 — Accounts (simple mode)**
As a small-team operator, I can enable accounts without PostgreSQL.

- `AUTH_MODE=simple` exposes signup/signin/signout
- Passwords are stored as Argon2id hashes
- Session cookies are `HttpOnly`, `SameSite=Lax`, and `Secure` when `SSL=true`
- Secret creation while signed in records an owner and the dashboard lists the receipt

## 6. Non-functional requirements

| ID | Requirement | Target |
| --- | --- | --- |
| NFR-1 | Reveal latency (p50, Redis on same host) | < 50 ms |
| NFR-2 | Secret size | ≤ 1 MiB, enforced with 413 above |
| NFR-3 | Cryptographic integrity | Tampered records fail closed, never decrypt partially |
| NFR-4 | Availability | Health check distinguishes app and Redis failure |
| NFR-5 | Logging | No plaintext, passphrase, ciphertext, token, or cookie values |
| NFR-6 | Compatibility | v1 responses stable; v3 additive-only within a major |
| NFR-7 | Accessibility | WCAG 2.1 AA for the two primary views (labels, focus, AA tokens checked; no formal audit yet) |
| NFR-8 | Deployment | Single image; env-only configuration; no secrets baked in |

## 7. Success criteria (verified, not assumed)

1. ✅ Create → reveal → second reveal 404, proven by an automated spec.
2. ✅ TTL expiry proven by a spec with a 1-second TTL.
3. ✅ Encryption proven by inspecting Redis in a spec (no plaintext substring).
4. ✅ Concurrent reveal proven by 8 parallel requests with exactly one success.
5. ✅ `docker compose up --build` serves the UI and `/health` on port 3000.
6. ✅ `bundle exec rspec` and `npm --prefix frontend run build` pass locally/Docker; the
   same steps run in CI, which is green on GitHub (K-32 closed).
7. ✅ Simple-mode signup → owner receipt → signout → signin verified in a browser;
   dashboard contains no secret plaintext.

Criteria 1–4 were verified on 2026-11-11 (94 specs at the time; the suite is now 118, 0
failures) plus a live Puma run.
The browser vertical slice, headless journey, and the production Compose stack also
passed. Strict production status still depends on the operational items in
[PRODUCTION_READINESS.md](PRODUCTION_READINESS.md); see [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

## 8. Assumptions and open questions

- **Assumption:** Redis is the only datastore in v1; secrets are JSON strings (see D-004).
- **Assumption:** the UI is served by Rack from `public/app` in production, Vite dev
  server proxies `/api` in development.
- **Open:** does the product need file secrets in v1? Currently deferred.
- **Decided (D-012):** passphrase attempts are limited per IP only; there is no
  per-secret attempt budget. The passphrase is a gate, not zero-knowledge.
- **Open:** which exact 27 locales are required, and are emails in scope?
- **Open:** is legacy API v2 compatibility needed? The spec mentions v2 only in the
  OpenAPI sentence; v1 + v3 are the implemented surface.
- **Open:** retention of receipts after reveal (currently: deleted with the secret).
