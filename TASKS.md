# TASKS

Status legend: `DONE` = code present and reviewed; `DONE*` = code present but **not yet
executed or tested**; `IN PROGRESS` = partly landed with evidence; `TODO` = planned;
`BLOCKED` = depends on something missing.
Keep this file current when planning or landing work. IDs are stable; do not renumber.

Checkpoint date: 2026-11-11. **M0, M1, M2, production packaging, and M3 simple-mode accounts are complete.**
Ruby/Bundler are not installed on the host, so every Ruby check runs in Docker
(`ruby:3.3-slim` + build tools); **68 specs pass** against Redis DB 15. The app runs in a
non-root production image with a two-worker Puma cluster, Redis persistence, hardened
headers, trusted-proxy handling, redacted logs, Compose packaging, and CI. A headless-Chrome
journey completed create → copy link → reveal once → gone, including the passphrase path,
with no plaintext in the URL or localStorage. A second browser journey covers signup →
owner receipt → signout → signin. **68 backend specs pass.** Several operational controls
remain (see `PRODUCTION_READINESS.md`).

## Completed (code present)

| ID | Task | Status | Evidence | Notes |
| --- | --- | --- | --- | --- |
| T-01 | Declare runtime/test dependencies | DONE | `Gemfile`, `Gemfile.lock` | Lockfile generated in Docker; `bcrypt` and `base64` declared |
| T-02 | Configuration module (env, TTLs, auth modes, limits) | DONE | `lib/onetime/config.rb` | Exercised by `/api/v3/config` spec; boot validation in `config.ru` |
| T-03 | Typed error hierarchy with HTTP status/code | DONE | `lib/onetime/errors.rb` | Error envelope exercised by the 404 spec |
| T-04 | AES-256-GCM + HKDF crypto layer | DONE | `lib/onetime/crypto.rb`, `spec/unit/crypto_spec.rb` | 6 specs: round-trip, empty, fresh IV/salt, wrong key, tamper, no plaintext |
| T-05 | Opaque IDs and hashed indexes | DONE | `lib/onetime/ids.rb`, `spec/unit/ids_spec.rb` | Length, uniqueness (1k), case-insensitive index, no raw value |
| T-06 | Redis access + atomic compare-and-delete | DONE | `lib/onetime/store.rb`, `spec/unit/store_spec.rb` | Consume win/lose/mismatch/empty covered; string record constraint enforced |
| T-07 | Fixed-window rate limiter | DONE | `lib/onetime/limiter.rb`, `spec/unit/limiter_spec.rb` | Ceiling, scope isolation, window reset covered; HTTP wiring + `Retry-After` landed in T-26 |
| T-08 | Argon2id passwords + bcrypt legacy verify | DONE | `lib/onetime/password.rb`, `spec/unit/password_spec.rb` | Argon2id params fixed (m_cost 16 = 64 MiB); bcrypt legacy verify covered |
| T-20 | `Secret` model on the frozen record schema | DONE | `lib/onetime/models/secret.rb`, `spec/integration/secrets_api_spec.rb` | Encrypted JSON string + receipt hash written in one MULTI with matching TTL; no plaintext at rest |
| T-21 | `ConcealSecret` logic object | DONE | `lib/onetime/logic/conceal_secret.rb` | TTL allowlist, 1 MiB cap, passphrase 1–256; Argon2id hash only, never logged |
| T-22 | `RevealSecret` logic object | DONE | `lib/onetime/logic/reveal_secret.rb` | Verify → atomic consume → decrypt; wrong passphrase leaves the record intact |
| T-23 | Roda app + helpers + error handling + security headers | DONE | `lib/onetime/web/app.rb`, `spec/integration/web_spec.rb` | JSON errors, request IDs, `no-store`/`Pragma`, nosniff/frame/referrer headers, SPA fallback |
| T-24 | API v1 (`/api/v1/share`, `/api/v1/secret/:key`) | DONE | `spec/integration/secrets_api_spec.rb` | Legacy shape; form **and** JSON create; GET/POST reveal; second call `404` |
| T-25 | API v3 guest routes (conceal/reveal) | DONE | `spec/integration/secrets_api_spec.rb` | `201` create / `200` reveal; passphrase flow; owner aliases fail closed until sessions (M3) |
| T-26 | Rate limits on conceal/reveal with `Retry-After` | DONE | `lib/onetime/web/app.rb`, integration spec | `429` + `Retry-After` on v1 and v3; rejected reveals do not consume; client IP honors `TRUSTED_PROXIES` (K-16 closed) |
| T-27 | Integration specs: lifecycle, TTL, encryption-at-rest, concurrent reveal | DONE | `spec/integration/secrets_api_spec.rb` | Create/reveal/gone, expiry, ciphertext-only Redis, 8-way race → exactly one `200`; 68 specs total today |
| T-42 | `/api/v3/config` endpoint (TTL options, auth mode, UI flags) | DONE | `lib/onetime/web/app.rb`, `spec/integration/web_spec.rb` | Response verified live; UI can render options without duplication |
| T-48 | Decide passphrase-model parity | DONE | `docs/DECISIONS.md` D-012, `SECURITY.md`, `KNOWN_ISSUES.md` K-21 | Keep instance-key encryption + Argon2 gate; no zero-knowledge claim; deliberate parity gap |
| T-45 | Security headers (CSP, HSTS when SSL, nosniff, frame deny) | DONE | `lib/onetime/web/app.rb`, `spec/integration/web_spec.rb` | CSP/COOP/CORP/Permissions-Policy on every response; HSTS only under `SSL=true`; verified live |
| T-46 | Structured logging with correlation IDs, redaction checks | DONE | `lib/onetime/web/request_logger.rb`, `spec/unit/request_logger_spec.rb` | One line per request; secret keys and UI paths redacted; no body/query/cookies |
| T-50 | Multi-stage Dockerfile (node UI build → Ruby runtime) | DONE | `Dockerfile`, `ots-prod:local` | Non-root UID 10001, read-only rootfs, healthcheck; image built and run |
| T-51 | Minimal Compose stack (web + Redis 7, AOF, healthchecks) | DONE | `compose.yaml` | Two workers; Redis AOF/noeviction; lifecycle verified through the container |
| T-52 | `.env.example` + DEPLOYMENT env contract | DONE | `.env.example`, `DEPLOYMENT.md` | Proxy, Redis timeout, Puma, and SSL semantics documented |
| T-54 | CI: rspec, frontend tests/typecheck/build, container smoke | DONE | `.github/workflows/ci.yml` | Redis DB 15 service; Vitest; Compose lifecycle + committed browser E2E; not yet executed on GitHub |
| T-75 | Committed frontend unit/E2E tests | DONE | `frontend/src/lib/api.test.ts`, `e2e/journey.mjs` | 9 Vitest tests; puppeteer journey covers create/reveal/gone and wrong/correct passphrase; verified locally |
| T-30 | Vite 6 + Vue 3 + TS + Tailwind 4 scaffold; dev proxy | DONE | `frontend/`, `vite.config.ts`, `package-lock.json` | `npm run build` passes typecheck and emits `../public/app`; dev proxies `/api` |
| T-31 | Zod schemas + API client + typed errors | DONE | `frontend/src/lib/api.ts` | Config/conceal/reveal/account/receipt schemas; `ApiError` carries status/code; no `any` |
| T-28 | Persist owner receipts when signed in (simple mode only) | DONE | `models/secret.rb`, `web/app.rb`, `spec/integration/accounts_spec.rb` | Owner zset written on conceal; reveal removes it; dashboard lists newest 50 and prunes stale entries |
| T-34 | Session views + dashboard (simple mode) | DONE | `SignInView.vue`, `SignUpView.vue`, `DashboardView.vue`, `e2e/accounts.mjs` | Signup/signin/signout; receipts list; disabled mode shows a sign-in prompt, never a fake account |
| T-40 | Simple-mode customers: signup/signin/signout/me | DONE | `models/customer.rb`, `logic/sign_up.rb`, `logic/sign_in.rb`, `spec/integration/accounts_spec.rb` | Argon2id at rest; bcrypt legacy rehash on login; duplicate email `409`; generic `401`; cookie flags verified |
| T-41 | Session store + auth helper + owner scoping | DONE | `models/session.rb`, `web/app.rb` | Opaque token, SHA-256 Redis key, sliding TTL; absent/expired session `401`; CSRF proof required for cookie mutations; owner isolation verified |
| T-32 | Secret conceal view | DONE | `frontend/src/views/ConcealView.vue` | Config TTL options, byte cap, optional passphrase, copy link, plaintext cleared after create |
| T-33 | Secret reveal view | DONE | `frontend/src/views/RevealView.vue` | No auto-reveal; passphrase prompt on 401; gone on 404; secret only in memory |
| T-35 | A11y + responsive pass on conceal/reveal | DONE | views/components; headless DOM audit | Keyboard flow, labels, focus move to result heading, AA tokens, no horizontal overflow at 375/768/1280 |
| T-36 | Wire built SPA into Rack static serving | DONE | `lib/onetime/web/app.rb` (`r.public`, `INDEX_PATH`) | `/` and `/assets/*` served with correct MIME; deep links return the shell; `X-Robots-Tag` set |

## Clone workflow (replica pack)

The pack lives at `~/.agents/skills/replica-*` and writes into `replica/`. Phases run in
order; each reads the previous output. See AGENTS.md for the clean-room rules.

| ID | Phase | Status | Artifact | Acceptance |
| --- | --- | --- | --- | --- |
| R-01 | recon | DONE | `replica/recon.md`, `replica/features.csv` | Public sources cited with URLs; 20 screens, 10 flows, 7 entities; evidence gaps stated |
| R-02 | architect | DONE | `replica/architecture.md` | Stack fixed to the brief; Redis schema referenced; build order starts with the vertical slice |
| R-03 | design | DONE | `replica/design/tokens.json`, `tokens.css`, `components.md` | 12 contrast pairs, 0 AA failures; no original assets/fonts; primitives land in M2 (`frontend/`) |
| R-04 | build | DONE | API + Vue vertical slice; headless browser journey verified | Create → link → reveal → gone works end to end before other screens |
| R-05 | backend | IN PROGRESS | Limits/health/atomic reveal done; sessions are M3 | Auth/session/rate-limit wiring; security checklist in SECURITY.md satisfied |
| R-06 | test | IN PROGRESS | Lifecycle/v1/v3/race/expiry covered by 12 integration specs; browser E2E is M2/M4 | F01/F02 happy paths + reveal race, wrong passphrase, expiry covered |
| R-07 | diff | IN PROGRESS | `replica/parity.md`: baseline 5.8, M1 54.8 (9/11), M2 60.6 (10/11); re-score after M3 | Baseline recorded at 5.8/100 with 0/11 must-haves; re-run after each milestone |
| R-08 | entrepreneur | TODO | `replica/fixes.md` | Only real, linked reviews; no fabricated quotes or counts |
| R-09 | brand | TODO | `replica/brand.md`, `replica/brand.json` | New name/palette; `sweep.py` exits 0 before any launch work |
| R-10 | launch | TODO | `replica/launch/` | No fake proof; original's name absent from listing |
| R-11 | deploy | TODO | `replica/deploy.md` | Preflight green, user approval recorded, no live keys committed |

Recon limits to keep in mind: no screenshot capture tool and no account access were
available, so 16 of 20 screens are inferred and marked as such. Do not upgrade their
confidence without new public evidence.

## Phase 0 — Make it runnable

| ID | Task | Depends on | Acceptance criteria |
| --- | --- | --- | --- |
| T-10 | Add `lib/onetime.rb` entrypoint, `lib/onetime/version.rb`, generate `Gemfile.lock` | T-01 | **DONE** — lockfile generated; `require` + 26 specs run in Docker |
| T-11 | Initialize git repo, add `.gitignore`, `.dockerignore`, `.env.example` | DONE | Repo initialized; initial commit made after the human's "take care of everything" approval; `.env` ignored |
| T-12 | Boot-time config validation in `config.ru` | T-10 | **DONE** — short `SECRET` exits 1 with `onetime: cannot boot: SECRET must be at least 32 bytes...`; valid boot verified on :3100 |
| T-13 | Test harness: RSpec, `rack-test`, Redis DB 15 helper, `.rspec` | T-10 | **DONE** — DB-15 guard, flush per example, randomized order |
| T-14 | Unit specs for crypto, ids, limiter, password | T-13 | **DONE** — 21 unit examples + 5 web examples (26 total), all green |

## Phase 1 — lifecycle

T-20 through T-28 landed in M1 and are listed under "Completed".

## Phase 2 — frontend

T-30 through T-36 landed in M2 and are listed under "Completed".

## Phase 3 — Accounts, limits, ops (P1)

| ID | Task | Status / depends on | Acceptance criteria |
| --- | --- | --- | --- |
| T-43 | `bin/ots` CLI | IN PROGRESS — `customers create` and `customers reset-password` verified; list/health/role flags remain | No password in argv or output; interactive hidden prompt or `OTS_PASSWORD` |
| T-44 | OpenAPI 3.1 generation + served document | T-24, T-25 | Document validates; routes listed match implemented routes |
| T-47 | 413 oversized payloads; passphrase length bounds | T-25 | 413 + 256-byte cap covered; add exact 1 MiB boundary and 0/1-char passphrase specs |

## Phase 4 — Deployment (P0/P1)

| ID | Task | Depends on | Acceptance criteria |
| --- | --- | --- | --- |
| T-53 | Full-mode compose (Postgres 17 + RabbitMQ 4.3) | T-51 | Documented as **not functional** until auth-full lands; must not imply support |
| T-55 | `CHANGELOG.md` release entry + git tag | T-54 | Version matches `Onetime::VERSION`; **tag deferred until M4** |

## Phase 5 — Deferred (P2, out of v1)

| ID | Task | Notes |
| --- | --- | --- |
| T-60 | Full auth (Rodauth: MFA, WebAuthn, magic links, SSO) | Requires Postgres + RabbitMQ; D-003 |
| T-61 | Organizations, custom domains, billing | Replaces flat team model |
| T-62 | Email delivery + expiration warnings via RabbitMQ | Needs worker process |
| T-63 | File secrets (multipart upload, encrypted blob) | Data model already reserves `kind`/`filename` |
| T-64 | i18n for UI and emails (27 locales) | `i18n` gem declared but unused |
| T-65 | SECRET rotation / re-encryption tool | Currently rotation destroys old secrets |
| T-66 | Redis migration tooling (schema version + idempotent scripts) | No data exists yet; add before first release |
| T-67 | Add MIT `LICENSE` and contributor docs | DONE | `LICENSE` added; MIT matches the brief |

## Phase 6 — Production hardening (P0, tracked in PRODUCTION_READINESS.md)

| ID | Task | Depends on | Acceptance criteria |
| --- | --- | --- | --- |
| T-70 | TLS termination, real hostname, Secure cookies | T-40 | HTTPS-only deploy; HSTS verified; cookies `Secure`/`HttpOnly`/`SameSite` |
| T-71 | Redis auth + TLS + network policy | T-51 | No unauthenticated Redis; documented in DEPLOYMENT |
| T-72 | Backup/restore drill with documented RPO/RTO | T-51 | Restore into a clean volume reproduces a receipt until TTL |
| T-73 | Metrics, tracing, alerting | T-46 | Request/error latency visible; health alerts |
| T-74 | Dependency/image scanning in CI | T-54 | `bundler-audit`, `npm audit`, image scan gate |

| T-76 | Load/soak test of rate limiter and Redis | T-26 | Documented throughput/latency; no lost or double reveals under load |
| T-77 | Incident runbook (key compromise, Redis loss, rollback) | T-70 | Written, reviewed, and linked from README |

## Immediate next step

M3 simple-mode accounts, sessions, owner receipts, dashboard, and the CLI create/reset
commands are done and verified. Next: finish T-43 (list/health/role flags), then close the
operational gates in `PRODUCTION_READINESS.md` (T-70–T-77) and run M4 verification.
Git initialization, the initial commit, and the MIT `LICENSE` gate are closed.

Manual evidence (2026-11-11): `npm run build` → typecheck + Vite build; the production
image runs as UID 10001 with two Puma workers and Redis AOF; `/` and assets served with
CSP; lifecycle create → reveal → gone verified through Compose; request logs redact secret
keys. Backend suite: `68 examples, 0 failures`; frontend: 9 Vitest tests; account E2E passes.
