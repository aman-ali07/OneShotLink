# TASKS

Status legend: `DONE` = code present and reviewed; `DONE*` = code present but **not yet
executed or tested**; `IN PROGRESS` = partly landed with evidence; `TODO` = planned;
`BLOCKED` = depends on something missing.
Keep this file current when planning or landing work. IDs are stable; do not renumber.

Checkpoint date: 2026-11-11. **M0–M3, production packaging, and the in-repo production-hardening gates are complete.**
Ruby/Bundler are not installed on the host, so every Ruby check runs in Docker
(`ruby:3.3-slim` + build tools); **113 specs pass** against Redis DB 15. The app runs in a
non-root production image with a two-worker Puma cluster (Puma 7.2.1), Redis persistence,
hardened headers, trusted-proxy handling, redacted logs, audit stream, Compose packaging,
CI, and dependency scanning. A headless-Chrome journey completed create → copy link →
reveal once → gone, including the passphrase path, with no plaintext in the URL or
localStorage. A second browser journey covers signup → owner receipt → signout → signin.
The CLI (`bin/ots`) ships in the image with health, backup/restore, key rotation, and
customer management. **113 backend specs pass.** Remaining items are infrastructure
(TLS, Redis auth) that cannot be closed from the repository; see `PRODUCTION_READINESS.md`.

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
| T-27 | Integration specs: lifecycle, TTL, encryption-at-rest, concurrent reveal | DONE | `spec/integration/secrets_api_spec.rb` | Create/reveal/gone, expiry, ciphertext-only Redis, 8-way race → exactly one `200`; 113 specs total today |
| T-42 | `/api/v3/config` endpoint (TTL options, auth mode, UI flags) | DONE | `lib/onetime/web/app.rb`, `spec/integration/web_spec.rb` | Response verified live; UI can render options without duplication |
| T-48 | Decide passphrase-model parity | DONE | `docs/DECISIONS.md` D-012, `SECURITY.md`, `KNOWN_ISSUES.md` K-21 | Keep instance-key encryption + Argon2 gate; no zero-knowledge claim; deliberate parity gap |
| T-45 | Security headers (CSP, HSTS when SSL, nosniff, frame deny) | DONE | `lib/onetime/web/app.rb`, `spec/integration/web_spec.rb` | CSP/COOP/CORP/Permissions-Policy on every response; HSTS only under `SSL=true`; verified live |
| T-46 | Structured logging with correlation IDs, redaction checks | DONE | `lib/onetime/web/request_logger.rb`, `spec/unit/request_logger_spec.rb` | One line per request; secret keys and UI paths redacted; no body/query/cookies |
| T-50 | Multi-stage Dockerfile (node UI build → Ruby runtime) | DONE | `Dockerfile`, `ots-prod:local` | Non-root UID 10001, read-only rootfs, healthcheck; image built and run |
| T-51 | Minimal Compose stack (web + Redis 7, AOF, healthchecks) | DONE | `compose.yaml` | Two workers; Redis AOF/noeviction; lifecycle verified through the container |
| T-52 | `.env.example` + DEPLOYMENT env contract | DONE | `.env.example`, `DEPLOYMENT.md` | Proxy, Redis timeout, Puma, and SSL semantics documented |
| T-54 | CI: rspec, frontend tests/typecheck/build, container smoke | DONE | `.github/workflows/ci.yml` | Redis DB 15 service; Vitest; Compose lifecycle + committed browser E2E; not yet executed on GitHub |
| T-80 | Icon set and social card from the logo brief (launch blocker B3) | DONE | `site/favicon.svg`, `site/app-icon.svg`, `site/og-card.html`, `script/build-assets.sh`, assets in `site/` and `frontend/public/` | Mark is one stroke in one colour with both seam gaps; generated set is favicon 16/32 + SVG, `apple-touch-icon.png` 180, `icon-512.png`, opaque `app-icon-1024.png`, `og.png` 1200×630; linked from all four HTML heads |
| T-82 | Datastore outage answers `503`, not `500` | DONE | `lib/onetime/errors.rb` (`Unavailable`), `web/app.rb` (`datastore_error?`), `spec/integration/web_spec.rb` | Redis connection errors map to `503 service_unavailable` with `Retry-After` on both API versions; v1 keeps its `message` shape; verified live by stopping Redis under the running Compose stack, then recovering without a restart |
| T-83 | Spec suite refuses a shared Redis DB | DONE | `spec/spec_helper.rb` | Before flushing, the suite counts clients attached to DB 15 and aborts with a clear message if another server or suite is using it; verified by attaching a second client (refused) and detaching it (110 → now 113 examples pass) |
| T-84 | Repeatable TLS rehearsal in front of the real preflight gate | DONE | `script/tls-rehearsal.sh`, `TESTING.md` §3.2 | Boots the production stack behind Caddy with a throwaway CA, then runs `script/preflight.sh --cacert` against it: 7 TLS assertions pass including `Secure`/`HttpOnly`/`SameSite` via a throwaway signup. `--with-redis` fails only on the unfixed host rule (T-71), which doubles as the negative control. Cleans up its stack, CA and proxy on exit |
| T-85 | Redis isolation on the host: fixed subnet + firewall rule | DONE (rule is per-host) | `compose.yaml` (`REDIS_SUBNET`), `DEPLOYMENT.md` §4.0, `script/tls-rehearsal.sh --with-redis` | Backend network pinned to `10.77.13.0/24` (outside Docker's default pool) so the rule survives redeploys; one narrow `nft` OUTPUT rule drops host→backend:6379. Verified: host connection times out, app create → reveal works, published test Redis on `:6399` unaffected, full preflight green with 0 skips (113 specs still pass). The durable form is ufw's `deny out to 10.77.13.0/24 port 6379`, persisted in `/etc/ufw/user.rules`; re-apply per deployment host |
| T-86 | A decryption failure must not destroy the secret | DONE | `lib/onetime/logic/reveal_secret.rb`, `spec/integration/secrets_api_spec.rb` | Decrypt now runs before the atomic consume, so a rotated/wrong `SECRET` or a corrupt record answers `500` and leaves the record intact instead of deleting it. Failing spec first (`404` on the second attempt), then verified live: old key live → `500`, `EXISTS` = 1, switch to the new key → the same secret reveals. Suite 113 examples |
| T-87 | Reconcile ARCHITECTURE.md and DATABASE.md with the code | DONE | `ARCHITECTURE.md` §1/§3/§4/§5/§7/§8, `DATABASE.md` §3/§6, `docs/DECISIONS.md` D-005/D-012/D-013 | Replaced the planned folder tree with the tree that exists (no `apps/`, no org/custom-domain models, no full-mode compose); reveal order corrected to verify → decrypt → consume; creation documented as one `MULTI` (it was described as sequential); failure-mode table now matches the 503/decrypt-survives behaviour; D-005 amended and D-013 added. Every claim checked against the code (receipt fields, session refresh, audit MAXLEN, limiter key shape, transactional writes) |
| T-79 | Account deletion (launch blocker B1) | DONE | `lib/onetime/logic/delete_account.rb`, `web/app.rb`, `DashboardView.vue`, `spec/integration/accounts_spec.rb`, `frontend/src/lib/api.test.ts`, `e2e/accounts.mjs` | `DELETE /api/v3/account` re-authenticates, then removes record + email index + sessions + receipts and clears the cookie; live secrets expire on their own TTL. 6 specs incl. an all-or-nothing failure case, 2 Vitest cases, and an E2E delete step; Roda has no `r.delete`, so the route uses `r.is(method: "DELETE")` |
| T-75 | Committed frontend unit/E2E tests | DONE | `frontend/src/lib/api.test.ts`, `e2e/journey.mjs` | 9 Vitest tests; puppeteer journey covers create/reveal/gone and wrong/correct passphrase; verified locally |
| T-78 | Build the landing page from `replica/launch/landing.md` | DONE (site; not deployed) | `site/index.html`, `site/privacy.html`, `site/terms.html`, `site/styles.css`, `site/favicon.svg` | Static site, not a Vue route (the instance is the product). Verified with headless Chrome at 1280/375px: all files 200, no page overflow, even 55–56px section gaps, rendered contrast 16.74:1 / 7.30:1 / 5.47:1, only decorative hairline rule below 3:1. No third-party requests |
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
| R-05 | backend | DONE | Limits/health/atomic reveal done; sessions shipped in M3 | Auth/session/rate-limit wiring; security checklist in SECURITY.md satisfied |
| R-06 | test | DONE | Lifecycle/v1/v3/race/expiry covered by integration specs; two committed browser journeys exercise create/reveal/gone and signup/receipt/signout/signin/delete | F01/F02 happy paths + reveal race, wrong passphrase, expiry covered |
| R-07 | diff | DONE | `replica/parity.md`: baseline 5.8, M1 54.8 (9/11), M2 60.6 (10/11), R-08 63.0 (11/11) | Baseline recorded at 5.8/100 with 0/11 must-haves; re-run after each milestone |
| R-08 | entrepreneur | DONE | `replica/fixes.md`, `replica/reviews.csv`, `replica/feedback.md`, `replica/themes-secrets.json` | 20 real linked records from 3 reachable sources (HN 17, Security SE 2, SO 1); Reddit 403 and no mobile app stated as unreachable; every theme flagged thin where <3 reviews or 1 source |
| R-09 | brand | DONE | `replica/brand.md`, `replica/brand.json`, rename across code/docs | Name **OneShotLink**; palette re-measured (12 pairs, 0 AA failures); sweep exits 0. Screening (2026-11-12): USPTO wordmark for `oneshotlink` returns no marks with a working control, both US stores return nothing exact, six domains `NXDOMAIN`/RDAP 404, npm/PyPI/RubyGems/GitHub free. Still unrun and not claimed: adjacent US marks, EUIPO/WIPO/Canada, X/Instagram/TikTok/YouTube/Reddit handles, open-web search — blockers listed in brand.md §2 |
| R-10 | launch | DONE (docs) | `replica/launch/landing.md`, `pricing.md`, `listing.json`, `launch-plan.md` | Angle A from `fixes.md`; pricing read from the original's public page + Bitwarden on 2026-11-11 (no billing complaints in the 20-record sample — stated as a gap, not a green light); `listing.py` exits 0. The landing page itself is built as a static site in `site/` (T-78), not as an app route; managed tier is unsellable until the preflight gate passes on a real host |
| R-11 | deploy | IN PROGRESS | `replica/deploy.md` (filled checklist). No go: **B2** legal pages written but no domain, **B3** placeholder favicon / no OG image, **B4** trademark screening unrun, **B5** preflight not yet green on a real host, **B6** host firewall rule unapplied (B1 account deletion landed with T-79). Nothing deployed; no live keys | Preflight green, user approval recorded, no live keys committed |

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
| T-43 | `bin/ots` CLI | DONE — `create`, `reset-password` (revokes sessions), `list`, `show`, `set-role`, `health`, `backup`, `restore`, `rotate-key`, `version`; all executed inside the production container | No password in argv or output; interactive hidden prompt or `OTS_PASSWORD` |
| T-44 | OpenAPI 3.1 served document | DONE — hand-maintained `lib/onetime/web/openapi.rb` served at `/api/v3/openapi.json`; spec asserts every documented path is mounted and every `$ref` resolves | Document validates; routes listed match implemented routes |
| T-47 | 413 oversized payloads; passphrase length bounds | DONE — exact `MAX_SECRET_BYTES` boundary (accepts N, rejects N+1) and empty/1-char passphrase specs added | 413 + 256-byte cap covered; exact boundary and edge specs present |

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
| T-65 | SECRET rotation / re-encryption tool | DONE — `bin/ots rotate-key` re-encrypts every record under `OTS_NEW_SECRET` preserving TTL; verified live (21 secrets rotated, pre-rotation secret still decrypts, old key fails) | Rotation no longer destroys secrets |
| T-66 | Redis migration tooling (schema version + idempotent scripts) | No data exists yet; add before first release |
| T-67 | Add MIT `LICENSE` and contributor docs | DONE | `LICENSE` added; MIT matches the brief |

## Phase 6 — Production hardening (P0, tracked in PRODUCTION_READINESS.md)

| ID | Task | Depends on | Acceptance criteria |
| --- | --- | --- | --- |
| T-70 | TLS termination, real hostname, Secure cookies | APP SIDE DONE — verified behind a real TLS terminator (Caddy, local CA) with `SSL=true`/`HOST`/`TRUST_PROXY`: HSTS `max-age=31536000; includeSubDomains` present, session cookie `secure; httponly; samesite=lax`, HTTPS 201 create, and all hardening headers sent. Negative control (`SSL=false`): no HSTS, no `Secure` flag. `X-Forwarded-For` spoofing blocked — rotating the leftmost value kept one bucket and 429'd on request 4; a trusted proxy's XFF is honored per client. Remaining: real hostname + certificate at the operator's proxy. **Automated gate:** `HOST=https://… script/preflight.sh` checks all of the above and exits non-zero on any failure | HTTPS-only deploy; HSTS verified; cookies `Secure`/`HttpOnly`/`SameSite` |
| T-71 | Redis auth + TLS + network policy | DONE (code) — compose requires `REDIS_PASSWORD` (`--requirepass`), web folds it into the URL via `Config.validated_redis_url`, healthcheck authenticates; verified live (`NOAUTH Authentication required` without it, `PONG` with it). TLS via `rediss://`. **Network policy:** Redis is on an `internal: true` network with no published port — verified no egress (`nc 1.1.1.1:443` fails, DNS dead) and unreachable from an unrelated bridge network, while the app still creates/reveals/restores. `web` drops all capabilities. Residual: the host can still route to the container IP (Docker attaches the host to the bridge); `AUTH` is enforced there and DEPLOYMENT.md §4.0 gives the nftables/ufw rule to close it | No unauthenticated Redis; documented in DEPLOYMENT |
| T-72 | Backup/restore drill with documented RPO/RTO | DONE — `bin/ots backup`/`restore` export/load encrypted records. **Clean-volume drill run 2026-11-11:** 81 secrets, sentinel `404` during outage and returned its value with TTL preserved after restore; backup 1.5 s, restart 10.5 s, restore 1.7 s, **RTO ≈ 12.4 s**. Fixed: the documented `/backups` path needed a writable named volume (read-only rootfs), added via `backup-data` + image `mkdir /backups` owned by the app user | Restore reproduces a secret until TTL |
| T-73 | Metrics, tracing, alerting | DONE (metrics) — `GET /metrics` serves Prometheus text behind `METRICS_ENABLED` (default off): `onetime_up`, `onetime_redis_up`, `onetime_requests_total{family,status}`, `onetime_errors_total`, request duration sum/count, and `onetime_redis_memory_used_ratio` for the >=80% alert. Verified live and by 10 specs (104 total). Distributed tracing is not included | Request/error latency visible; health alerts |
| T-74 | Dependency scanning in CI | DONE — `security` job runs `bundler-audit` and `npm audit --audit-level=high`; fixed the findings it surfaced (Puma 6.6.1→7.2.1 for 2 high CVEs, zod 3→4.6.7 for 1 high advisory). Both audits report 0 vulnerabilities | `bundler-audit`, `npm audit` gate |

| T-76 | Load/soak test | DONE — `script/loadtest.rb`; verified 400 secrets / 40 threads / 8-way race with 0 double reveals (~240 creates/s) against the Compose stack; wired into CI | Documented throughput; no lost or double reveals under load |
| T-77 | Incident runbook | DONE — `RUNBOOK.md` covers key compromise, Redis loss, reveal regression, rate-limit lockout, full-mode, rollback, first-response checks | Written and linked from README |

## Immediate next step

All in-repo tasks are done: CLI (T-43), OpenAPI (T-44), boundary specs (T-47), key
rotation (T-65), backup/restore (T-72), dependency scanning (T-74), load test (T-76), and
the incident runbook (T-77). What remains is **infrastructure**, not code: TLS termination
(T-70) and the host-side firewall rule for Redis (T-71 — Compose already isolates Redis on
an internal, egress-free network with no published port). Those require the operator's
host and certificates, so they are documented rather than claimed complete in
`PRODUCTION_READINESS.md`.

Manual evidence (2026-11-11): `npm run build` → typecheck + Vite build; production image
runs as UID 10001 with two Puma workers and Redis AOF; `/` and assets served with CSP;
lifecycle create → reveal → gone verified through Compose; OpenAPI served at
`/api/v3/openapi.json`; key rotation verified live (21 secrets, old key fails, new key
reads); backup/restore verified live (deleted secret 404 → restored → decrypts); load test
verified 400 secrets × 8-way race with 0 double reveals; `bundler-audit` and `npm audit`
report 0 vulnerabilities. Backend suite: `113 examples, 0 failures`; frontend: 11 Vitest
tests; both committed browser journeys (create/reveal/gone and
signup/receipt/signout/signin/delete) pass against a live Puma on Redis DB 15.
