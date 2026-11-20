# PROJECT_AUDIT.md — OneShotLink

Audit snapshot: 2026-11-20, commit `a89a5e0`. Method: local repository inspection plus
clean-room public documentation only. No original-service source, bundle, private API,
logo, copy or font was read. This file records what exists and what is verified; it is not
a launch decision.

## Scope and method

Inspected: manifests/lockfiles, `lib/onetime/**`, `bin/ots`, `config.ru`, `compose.yaml`,
`Dockerfile`, `.github/workflows/ci.yml`, `script/*.sh`, `frontend/**`, `e2e/**`, `spec/**`,
and the status documents (`AGENTS.md`, `ARCHITECTURE.md`, `DATABASE.md`, `API.md`,
`SECURITY.md`, `TESTING.md`, `PRODUCTION_READINESS.md`, `KNOWN_ISSUES.md`, `TASKS.md`,
`docs/DECISIONS.md`, `docs/GO_LIVE_HANDOFF.md`, `replica/*`). Claims below are tied to
files or to commands executed during this audit; the distinction is stated.

## Stack

| Layer | Technology | Evidence |
| --- | --- | --- |
| Backend | Ruby 3.3 (Gemfile `>= 3.2`), Roda 3.109.0 on Rack 3.2.8, Puma 7.2.3 | `Gemfile`, `Gemfile.lock` |
| Datastore | Redis 7.4 (`redis` gem 5.4.1), one DB, TTL-driven expiry | `compose.yaml`, `DATABASE.md` |
| Crypto | AES-256-GCM + HKDF-SHA256, Argon2id (argon2 2.3.3), bcrypt legacy verify | `lib/onetime/crypto.rb`, `lib/onetime/password.rb` |
| Frontend | Vue 3.5, vue-router 4.5, Vite 6, TypeScript 5.7, Tailwind 4, Zod 4.6 | `frontend/package.json` |
| E2E | puppeteer-core 24.10 driving `/usr/bin/google-chrome` | `e2e/package.json` |
| Delivery | multi-stage Dockerfile (Node build → ruby:3.3-slim runtime), Compose with `frontend` + internal `backend` networks, GitHub Actions (4 jobs) | `Dockerfile`, `compose.yaml`, `.github/workflows/ci.yml` |

Deliberate omissions from the reference stack: no Rails, no ORM, no Rodauth, no
PostgreSQL/RabbitMQ, no background worker (D-001, D-003).

## Architecture

Layered functional core / imperative shell. Middleware order is
`HeadRequests → RequestLogger → App` (`config.ru:21-23`). Roda validates input, applies
rate limits and maps errors; `logic/*.rb` holds use cases; `models/*.rb` owns Redis key
builders and record shapes; `lib/onetime/store.rb` is the single Redis access layer.

- **Create** (`POST /api/v3/guest/conceal`): rate limit → bounded JSON parse →
  `ConcealSecret` validation → `Models::Secret.create` generates an opaque ID, encrypts
  with a fresh salt/IV, hashes an optional passphrase with Argon2id, and writes the JSON
  string record, receipt hash and owner ZSET in one `MULTI` with matching TTLs
  (`models/secret.rb`). Plaintext is neither persisted nor echoed.
- **Reveal** (`POST /api/v3/.../reveal`, the only consuming route): fetch → verify
  passphrase → `Crypto.decrypt` → atomic Lua compare-and-delete of the exact serialized
  bytes (`store.rb:46-60`) → receipt/index cleanup (`logic/reveal_secret.rb:22-48`).
  Verification and decryption both precede the consume, so a wrong passphrase, rotated
  `SECRET` or corrupt record leaves the secret intact (D-013).
- `GET /api/v3/.../secret/:key` is a non-consuming preview (K-35); the frozen v1 `GET`
  still consumes by contract, and `HEAD` on that route is refused with `405` (K-39).

## Implementation status

Verified present: secret lifecycle with single-use race coverage, at-rest encryption,
TTL/expiry, passphrase gate with an 8-byte floor, fixed-window rate limits with
`Retry-After`, v1 and v3 APIs, simple-mode accounts/sessions/receipts/dashboard, CSRF and
origin checks, redacted request logging, audit stream, `/metrics`, OpenAPI document, CLI
(`bin/ots`: health, backup/restore, key rotation, customer management), hardened
non-root image, Compose packaging, and four CI jobs.

Deferred by explicit decision, **not** missing by accident: `AUTH_MODE=full` (501),
organizations/custom domains, file secrets, email jobs, MFA/WebAuthn/SSO, i18n locales,
API v2, distributed tracing. See `docs/DECISIONS.md` and `KNOWN_ISSUES.md:68-74`. They stay
`no`/`skip` in `replica/features.csv` until a human decides otherwise.

## Verification evidence (commands executed in this session family)

| Check | Result |
| --- | --- |
| `docker run … ots-dev bundle exec rspec` | **138 examples, 0 failures** at the file-secret tree (counts moved 119 → 120 → 132 → 133 → 134 → 138 as features landed) |
| `npm --prefix frontend test` / `run typecheck` / `run build` | 11 Vitest pass; clean `vue-tsc`; Vite build clean |
| `BASE_URL=… npm --prefix e2e test` and `test:accounts` | both journeys pass, `errors: []`, zero console errors |
| live HTTP probes | GET ×3 non-consuming → POST reveals once → 404; HEAD v1 → 405 with secret intact |
| `script/brand-sweep.sh` | clean |
| `docs/SDK.md` + three examples (curl/TypeScript/Python) | all three executed against live Puma: `ok: create=… preview=no-content reveal=match replay=404`; passphrase flow returned the documented codes. No new dependencies |
| `parity.py replica/features.csv` | 63.0/100, must-haves 11/11 |
| GitHub Actions | green through `43498af`; T-111 run in progress at audit time |

## Risks and gaps

1. **The passphrase is an access gate, not a second key (D-012).** The instance `SECRET`
   can decrypt every record. "Zero-knowledge" and "the server cannot decrypt" are
   prohibited in copy.
2. **Instance-wide key.** Compromise of `SECRET` exposes all stored records; rotation is
   an explicit offline CAS operation (`bin/ots rotate-key`, K-42) and backups remain
   sensitive because they contain passphrase hashes and session digests.
3. **Documentation drift.** `replica/features.csv` still marks several shipped
   capabilities `clone: no`; spec counts disagree across `ARCHITECTURE.md` (94),
   `API.md` (133) and `TESTING.md` (134); `TESTING.md` still describes the Redis TLS
   rehearsal as a negative control. The handoff explicitly requires a human decision
   before flipping matrix rows, so this audit does not change them.
4. **Per-process metrics.** Counters are in-memory per Puma worker; each worker must be
   scraped separately. No distributed tracing.
5. **No schema migration tooling and no live host.** `schema:version` is planned (T-66);
   T-70 (real hostname/TLS), T-71 (per-host firewall), B2/B4/B5/B6 remain operator work.

## What this audit does not claim

It does not claim the deployment is "production ready" — `AGENTS.md:150` forbids that
while T-70/T-71 are open. It does not claim parity with the original service beyond the
must-have features proved by specs and live requests, and it does not claim that any
deferred feature is implemented.
