# Changelog

All notable changes to this project will be documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

Entries marked **verified** were exercised by a passing spec or a live request. The M0 and
M1 core runs in this file were executed on 2026-11-11; unbuilt areas are marked planned.

## [Unreleased]

### Security (Redis network policy, 2026-11-11) — verified

- **Redis can no longer reach the internet (T-71).** Compose now puts Redis on an
  `internal: true` network (`backend`) and `web` on both `backend` and a `frontend`
  network that carries the published port. An internal network has no gateway, so Redis
  has no egress and cannot be reached from outside that network. Verified live: from the
  Redis container `nc 1.1.1.1:443` fails and DNS does not resolve, and the port is
  unreachable from a container on an unrelated bridge network — while create, reveal,
  the passphrase path, and backup/restore all still work. The `web` container now drops
  all Linux capabilities (`cap_drop: ALL`).
- **Residual, documented:** Docker attaches the host to the bridge, so a host process can
  still route to the container IP; `AUTH` is enforced there, and DEPLOYMENT.md §4.0 gives
  an nftables/ufw rule to block it.

### Added (metrics, 2026-11-11) — verified

- **Prometheus metrics endpoint (T-73).** `GET /metrics` (behind `METRICS_ENABLED`,
  default off) serves Prometheus text: `onetime_up`, `onetime_redis_up`,
  `onetime_version_info`, per-family request counters and duration sum/count,
  `onetime_errors_total`, and `onetime_redis_memory_used_ratio` (for the >=80% alert).
  The `family` label is a fixed set, so a secret key or raw path can never explode
  cardinality. Built on a new `Onetime::Metrics` module (no new dependency, no background
  thread) and a `Store.memory_stats` Redis INFO call. Verified live in the container and
  by 10 new specs (suite now 104). Alert thresholds are documented in DEPLOYMENT.md §5.1.

### Verified (restore drill, 2026-11-11)

- **Measured RTO (T-72).** Ran a real restore-into-clean-volume drill with 81 stored
  secrets: `bin/ots backup` 1.5 s, `docker compose down -v` + `up` to `/health = 200`
  10.5 s, `bin/ots restore` 1.7 s — **total RTO ≈ 12.4 s**. A sentinel secret returned
  `404` while the volume was gone and its value with the original TTL after the restore.
- **Fixed the documented backup path.** `/backups` did not exist under the read-only
  root filesystem, so the documented `bin/ots backup --out /backups/dump.json` failed with
  `ENOENT`/`EACCES`. Added a `backup-data` named volume and made the image create
  `/backups` owned by the app user, so the volume inherits that ownership and the command
  works as the normal (non-root) user and `docker cp` can read it back.

### Verified (TLS path, 2026-11-11)

- **App-side TLS behavior proven (T-70).** The app was run behind a real TLS terminator
  (Caddy with a local CA) using `SSL=true`, `HOST`, and `TRUST_PROXY`. Confirmed over
  HTTPS/2: `200` on `/health` with a valid chain, HSTS
  `max-age=31536000; includeSubDomains`, session cookie
  `secure; httponly; samesite=lax`, `201` create, and the full hardening header set.
  Negative controls with `SSL=false` dropped HSTS and the `Secure` flag, so both are
  config-driven rather than hardcoded.
- **`X-Forwarded-For` spoofing blocked.** With `TRUST_PROXY=false`, rotating the header
  did not reset the limiter (429 on the 4th request). With a trusted proxy, distinct XFF
  values got distinct buckets, while varying the leftmost value with a constant real
  client stayed in one bucket and 429'd on the 4th — the right-to-left walk stops at the
  first untrusted hop. A DEPLOYMENT.md §4.1 checklist covers the remaining live-domain
  checks.

### Fixed (CI, 2026-11-11) — verified

- **CI runs on GitHub (K-32):** the workflow now executes end to end. Its first real run
  (43060013486) passed dependency scanning, backend specs, and the frontend build, then
  failed in the container job: the load-test step opened with a bare
  `docker compose down -v`, and Compose interpolates `${SECRET}`/`${REDIS_PASSWORD}` on
  `down` as well as `up`, so the step aborted with "required variable SECRET is missing a
  value" before restarting the stack. The CI values moved to job level and the duplicated
  inline env was dropped. The rerun (43060570677) is green across all four jobs, and the
  load test reports **100/100 secrets revealed exactly once** on GitHub.

### Production hardening (2026-11-11) — verified

- **CLI completed (T-43):** `bin/ots` now ships in the image with `customers create`,
  `reset-password` (revokes all sessions), `list`, `show`, `set-role`, `health`,
  `backup`, `restore`, `rotate-key`, and `version`. All executed inside the production
  container. Passwords are never accepted in argv.
- **Key rotation (T-65):** `bin/ots rotate-key` re-encrypts every stored secret under a new
  `SECRET` while preserving TTLs. Verified live: 21 secrets rotated, a pre-rotation secret
  still decrypts under the new key, and the old key fails.
- **Backup/restore (T-72):** `bin/ots backup`/`restore` export and reload encrypted records
  (no plaintext, sessions excluded, TTLs preserved). Verified live: a deleted secret (404)
  decrypts again after restore.
- **Dependency scanning (T-74):** new `security` CI job runs `bundler-audit` and
  `npm audit --audit-level=high`. It surfaced real issues, now fixed: **Puma 6.6.1 →
  7.2.1** (2 high CVEs) and **zod 3 → 4.6.7** (1 high advisory). Both audits report 0
  vulnerabilities.
- **Audit trail (K-34):** append-only `audit:events` Redis stream records signup, signin,
  failed signin, signout, password change, session revocation, and reveal events. Only
  identifiers, request ids, and IPs — never emails, passwords, or secret values.
- **Load test (T-76):** `script/loadtest.rb` proves the single-use invariant under
  concurrency. Verified: 400 secrets, 40 threads, 8-way race, **0 double reveals**
  (~240 creates/s). Wired into CI.
- **OpenAPI 3.1 (T-44):** served at `/api/v3/openapi.json`; a spec asserts every documented
  path is mounted and every `$ref` resolves.
- **Exact boundary specs (T-47):** accepts exactly `MAX_SECRET_BYTES`, rejects one byte
  more; covers empty and one-character passphrases.
- **Redis auth (T-71):** Compose requires `REDIS_PASSWORD` (`--requirepass`), the web folds
  it into the URL via `Config.validated_redis_url`, and the healthcheck authenticates.
  Verified: unauthenticated `PING` returns `NOAUTH`. `rediss://` enables TLS.
- **Incident runbook (T-77):** `RUNBOOK.md` covers key compromise, Redis loss, reveal
  regression, rate-limit lockout, full-mode, rollback, and first-response checks.
- **Packaging fix:** `bin/` and `script/` are now copied into the runtime image, so the CLI
  and load test are available in production.

### Security (2026-11-11) — verified

- **Password change now revokes other sessions.** Sessions are recorded in a
  per-customer index (`customer:sessions:<id>`); changing a password deletes every other
  live session and keeps the caller signed in. Verified live in the production container
  (second device `401`, caller `200`) and covered by `spec/unit/session_spec.rb` (K-34).
- **Rate-limit visibility.** Every rate-limited response and every success within a limit
  now carries `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset`, in
  addition to the existing `Retry-After` (K-26). Verified over HTTP: `201` with
  `remaining: 1`, then `429` with `remaining: 0`.
- Removed the unused `Crypto.data_key`; record keys derive from `SECRET` plus a per-record
  salt through a single function (K-09).

### Added (M3 simple-mode accounts, 2026-11-11) — verified

- Customer records backed by Redis: `customer:<id>` hash plus
  `customer:index:<sha256(normalized email)>` for uniqueness. Raw emails never appear in
  Redis keys; passwords are Argon2id hashes (bcrypt verified then rehashed on legacy login).
- Signup, signin, signout, `account/me`, `account/receipts`, and password change; signup
  and signin share `RATE_LIMIT_SIGNIN` (default 10/window). Duplicate email is `409
  email_taken`; login failures are a uniform `401 invalid_credentials`.
- Opaque session tokens stored under SHA-256-digest Redis keys with a sliding TTL.
  Cookie is `HttpOnly`, `SameSite=Lax`, `Secure` when `SSL=true`, path `/`.
- CSRF defense for cookie-authenticated mutations: `Sec-Fetch-Site: same-origin` or an
  `Origin` host matching `Host`; cross-site requests get `403 forbidden`.
- Owner receipts: authenticated conceal writes the owner sorted set; atomic reveal removes
  it. Dashboard lists the newest 50 receipts and prunes stale index entries.
- Vue views for signup, signin, and dashboard (receipts + password change), plus header
  Account link. Dashboard never receives or renders secret plaintext.
- `bin/ots customers create` / `customers reset-password`; hidden TTY prompt or
  `OTS_PASSWORD`. CLI does not accept passwords in argv and prints only id/email.
- Committed browser test `e2e/accounts.mjs` covering signup → owner receipt → reload →
  signout → signed-out prompt → signin.
- Backend suite grew to **68 examples, 0 failures**; Vitest remains 9 passing; production
  build emits 176.66 kB JS / 14.21 kB CSS.

### Added (production packaging, 2026-11-11) — verified

- Multi-stage `Dockerfile`: Node builds the SPA, Ruby runtime runs as UID 10001 with a
  read-only rootfs, no secrets in layers, and a `/health` HEALTHCHECK.
- `compose.yaml`: web + Redis 7.4 with AOF (`everysec`), `noeviction`, healthchecks,
  named volume, `no-new-privileges`; two Puma workers with post-fork Redis reset.
- CI workflow: backend RSpec against Redis DB 15, frontend typecheck/build, container
  build + Compose lifecycle smoke test.
- Boot-time `Config.validate!` fails closed on short/missing `SECRET`, invalid TTL/auth
  config, malformed proxy CIDRs, and non-positive limits.
- CSP, HSTS under `SSL=true`, Permissions-Policy, COOP, CORP, and
  `X-Permitted-Cross-Domain-Policies` on every response.
- Trusted-proxy client IP resolution: `X-Forwarded-For` is ignored unless the immediate
  peer is in `TRUSTED_PROXIES`; integration specs cover spoofing and trusted hops.
- Redacted request logging (`RequestLogger`): method/path/status/duration/request ID only;
  secret keys in API and UI paths become `<redacted>`.
- Vitest coverage for the Zod API client (9 tests); CI runs it before typecheck/build.
- Committed puppeteer E2E (`e2e/journey.mjs`) for create → reveal → gone and the
  wrong/correct passphrase path; CI runs it against the Compose stack.
- Immutable caching for hashed assets; `no-cache`/noindex for the SPA shell and deep
  links; HEAD served through GET with an empty body.
- HEAD served through GET routes with an empty body (`HeadRequests`).
- Redis connect/read/write timeouts and reconnect attempts from env.
- `PRODUCTION_READINESS.md` with verified gates, open ops items (T-70–T-77), and the
  minimum deployment checklist.
- Verified: image and Compose stack booted, non-root check, create → reveal → gone through
  the container, CSP headers on live responses, logs redacted; suite **55 examples, 0
  failures**.

### Added (M2 UI vertical slice, 2026-11-11) — verified

- `frontend/`: Vue 3 + TypeScript + Vite 6 + Tailwind 4 scaffold, strict `vue-tsc`
  typecheck, Vite build to `public/app`, dev proxy for `/api` and `/health`.
- Zod-validated API client (`config`, `conceal`, `reveal`) with typed `ApiError`.
- Conceal view: config-driven TTL, byte counter/cap, optional passphrase, copyable
  one-time link; plaintext is cleared after creation.
- Reveal view: explicit reveal action (no auto-reveal), passphrase prompt on 401,
  wrong-passphrase retry without consuming, destroyed state on 404, in-memory secret only.
- Accessible primitives (button, alert, copy, header/footer), skip link, focus moved to
  result headings, responsive layout at 375/768/1280 px.
- Rack serves the built SPA (`r.public`) with correct asset MIME and deep-link fallback;
  `X-Robots-Tag: noindex, nofollow` and `robots.txt` for secret paths.
- Verified: `npm run build` passes; headless Chrome completed create → reveal → gone and
  the wrong/correct passphrase path with `localStorage === "{}"`; backend suite now
  **41 examples, 0 failures**.
- Parity re-scored: **60.6/100, 10/11 must-haves**; the remaining must-have is the
  deliberate D-012 passphrase divergence. Report in `replica/parity.md`.
- Docs refreshed for M2.

### Added (M1 secret lifecycle, 2026-11-11) — verified

- Secret model + logic objects: encrypted JSON object and receipt hash written in one
  `MULTI`; verify → atomic consume → decrypt ordering; receipt/index cleanup on reveal.
- API v1 `POST /share`, `GET|POST /secret/:key` (form and JSON) and v3 guest
  `conceal` / `secret/:key[/reveal]`; owner aliases fail closed with `401` until sessions.
- Passphrase gate (Argon2id), TTL allowlist, 1 MiB cap, 413, per-IP limits with
  `Retry-After`, uniform 404s, request IDs, `no-store` and nosniff/frame/referrer headers.
- 14 new integration examples (40 total): create/reveal/gone, ciphertext-only Redis,
  wrong-passphrase preservation, 8-way reveal race, TTL expiry, v1 form+JSON, 413,
  429 (v1 + v3), full-mode 501, auth-disabled fail-closed.
- Design tokens (`replica/design/tokens.json`, `tokens.css`) and component specs; 12
  contrast pairs, 0 AA failures.
- `docs/DECISIONS.md` D-012: passphrase is an access gate, not zero-knowledge; K-21 is a
  documented parity gap. T-48 closed.
- Re-scored parity with `replica-diff`: **54.8/100, 9/11 must-haves** (from 5.8, 0/11);
  report in `replica/parity.md`.
- Verified live: Puma `:3100`, health `200`, create `201`, reveal `200`, second `404`;
  four parallel reveals → one `200`, three `404`. Suite: **40 examples, 0 failures**.
- Full docs refresh: README, API, DATABASE, SECURITY, TESTING, AGENTS, ROADMAP, TASKS,
  KNOWN_ISSUES.

### Added (documentation, 2026-11-11)

- `AGENTS.md` with OpenCode workflow, security rules, and definition of done.
- `README.md`, `PRD.md`, `ARCHITECTURE.md`, `TASKS.md`, `TECH_STACK.md`,
  `DESIGN_SYSTEM.md`, `DATABASE.md`, `API.md`, `SECURITY.md`, `TESTING.md`,
  `DEPLOYMENT.md`, `KNOWN_ISSUES.md`, `docs/DECISIONS.md`, `CHANGELOG.md`.
- `.env.example` (placeholders only) and `.gitignore`.

### Added (M0 runnable core, 2026-11-11) — verified

- `lib/onetime.rb`, `lib/onetime/version.rb`, `config.ru`, `config/puma.rb`, and a
  minimal Roda app serving `/health` and `/api/v3/config` with security headers,
  request IDs, typed JSON errors, and a no-store policy.
- Boot fails fast with an actionable message when `SECRET` is missing or shorter than
  32 bytes (verified: exit 1).
- `Gemfile.lock` (Docker/gems), `bcrypt` + `base64` declared, `.rspec`, RSpec harness
  pinned to Redis DB 15, 26 unit/integration examples.
- Hardened `Store.consume` to require the expected value, explicit `require "json"`,
  Argon2id parameters corrected (m_cost 16 = 64 MiB, p_cost 2), UTF-8 decrypt output.
- Verified: `bundle exec rspec` → **26 examples, 0 failures**; Puma boot + `/health`,
  `/api/v3/config`, and JSON 404 exercised with curl.

### Added (clone workflow, 2026-11-11)

- Installed the MIT `replica-*` skill pack (11 skills) under `~/.agents/skills/` and
  documented the mandatory clean-room workflow in `AGENTS.md`; pack's own tool tests
  pass (57).
- `replica/recon.md` and `replica/features.csv`: public-source recon of the Onetime
  Secret core loop, 20 screens (4 verified, 16 inferred), 10 flows, 7 entities, 27
  features. Baseline parity **5.8/100**, 0/11 must-haves.
- `replica/architecture.md`: v1 stack/schema/API/build order, adapted to Redis (no SQL).
- Recon gaps and the passphrase-parity discrepancy recorded (K-21, K-22, T-48).

### Added (scaffold, unverified)

- `Gemfile` declaring Roda, Rack 3, Puma, Redis, OJ, Argon2, dry-cli, i18n,
  SemanticLogger, and RSpec/rack-test. No lockfile yet.
- `lib/onetime/config.rb`: environment-driven settings, TTL parsing, auth-mode gate.
- `lib/onetime/crypto.rb`: AES-256-GCM with HKDF-derived per-record keys and
  constant-time comparison.
- `lib/onetime/store.rb`: Redis client, JSON helpers, atomic compare-and-delete Lua.
- `lib/onetime/limiter.rb`: fixed-window rate limiting in Lua.
- `lib/onetime/password.rb`: Argon2id hashing with bcrypt legacy verification.
- `lib/onetime/ids.rb`: opaque identifiers and hashed index keys.
- `lib/onetime/errors.rb`: typed errors with HTTP status and stable codes.

### Not yet present

HTTP server, API routes, models, logic objects, CLI, frontend, Docker packaging, tests,
OpenAPI document, LICENSE. See [TASKS.md](TASKS.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

## [0.1.0] — 2026-11-11

Initial scaffold checkpoint. No runtime behavior is verified; do not deploy.

[Unreleased]: https://example.invalid/onetime-secret/compare/v0.1.0...HEAD
