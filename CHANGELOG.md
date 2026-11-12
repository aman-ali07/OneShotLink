# Changelog

All notable changes to this project will be documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

Entries marked **verified** were exercised by a passing spec or a live request. The M0 and
M1 core runs in this file were executed on 2026-11-11; unbuilt areas are marked planned.

## [Unreleased]

### Changed (production hardening pass, 2026-11-12) — verified

- **A datastore outage is now reported honestly.** Redis connection failures map to
  `503 service_unavailable` with a `Retry-After` hint on both API versions (v1 keeps its
  `message` shape) instead of a generic `500 internal_error`, so clients and load balancers
  back off rather than treating it as a bad request. The message is fixed text; the Redis
  error string and the secret never reach the response body.
- **The spec suite refuses a shared database.** Before flushing, it counts the clients
  attached to Redis DB 15 and aborts with an actionable message if another server or a
  second suite is using it — flushing a live database could otherwise corrupt its state and
  let a run report fewer examples than it should.
- **The loop-engineering scaffolding is gone.** `LOOP.md`, `STATE.md`, `loop-budget.md`,
  `loop-constraints.md`, `loop-run-log.md`, `gate.yaml`, `script/loop-free-pi.sh` and the
  `.claude/` loop skills/agent are removed, along with every reference to them. The binding
  rules they carried already live in `AGENTS.md`, `SECURITY.md`, `TESTING.md`, `RUNBOOK.md`
  and `TECH_STACK.md`.

Verified end to end against the shipped image and Compose stack: `docker compose up --build`
→ both browser journeys pass → container runs as UID 10001 with a read-only rootfs, `cap_drop:
ALL` and no published Redis port → Redis stopped: `/health` `503`, writes `503` +
`Retry-After`, static pages still `200` → Redis restarted: health `ok`, create → reveal →
second reveal `404` → rate limiter allows 29 then `429` with `retry-after: 60` and
`X-RateLimit-*` → load test 200 secrets / 20 threads, 135.9 creates/s, every secret revealed
exactly once → `/metrics` serves `onetime_up`/`onetime_redis_up`/request counters →
`script/preflight_selftest.sh` 5/5. Backend suite 112 examples / 0 failures; Vitest 11;
typecheck + Vite build clean; `bundler-audit` and `npm audit` clean.

- **The Redis plane has a stable subnet, and the host rule is proven.** `compose.yaml`
  pins the internal backend network to `10.77.13.0/24` (`REDIS_SUBNET`) instead of letting
  Docker assign one per project, so a host firewall rule keeps matching across redeploys
  and cannot be silently bypassed by a new random subnet. The documented `nft` OUTPUT rule
  was applied and verified: a host connection to `10.77.13.2:6379` now times out while the
  app still creates and reveals secrets, published test Redis on `:6399` is unaffected, and
  the full preflight ends **green with 0 skips** (`host cannot reach Redis` PASS). The
  rule lives in the host's own firewall (ufw `user.rules`, enabled at boot) rather than a
  temporary kernel table, so it survives reboot; the throwaway `nft` table used while
  proving it was removed, leaving exactly one mechanism.
- **`script/tls-rehearsal.sh` — the TLS gate is now repeatable without a domain.** It boots
  the production Compose stack behind a real TLS terminator (Caddy) with a throwaway local
  CA, then runs the real `script/preflight.sh` against it with certificate verification on.
  Result: 7/7 TLS assertions pass, including `Secure`/`HttpOnly`/`SameSite` on a session
  cookie obtained through a throwaway signup and the plain-HTTP → HTTPS redirect. With
  `--with-redis` the gate fails on exactly the one open item (`host can reach Redis`),
  which is the negative control proving the gate still has teeth. Documented in
  `TESTING.md` §3.2 and `PRODUCTION_READINESS.md`.

### Added (icons and social card, 2026-11-12) — verified

- **A real mark, drawn from the logo brief** (`replica/brand.md` §4): `site/favicon.svg` is
  one teal stroke, one colour, a link with both ends open at the seam — legible at 16px and
  scalable to the app icon. `site/app-icon.svg` is the opaque 72%-inset tile for icons that
  cannot carry transparency.
- **`script/build-assets.sh`** renders the set from those sources plus `site/og-card.html`:
  `favicon-16.png`, `favicon-32.png`, `apple-touch-icon.png` (180), `icon-512.png`, opaque
  `app-icon-1024.png`, and a 1200×630 `og.png` card carrying the tagline "Share a secret
  once." Icons land in `site/` and `frontend/public/` (Vite copies the latter into the
  served root), so the landing site and the app cannot drift apart.
- **Metadata:** every HTML head now links the icon set, `apple-touch-icon` and
  `og:image`/`twitter:image` with width, height and alt. `og:image` stays relative because
  no domain is registered yet; `replica/deploy.md` B2/B5 records that the operator must make
  it absolute at deploy time.

Verified: sizes and colour modes checked with Pillow (16/32/180/512/1024/1200×630; icons
opaque `RGB`, favicons `RGBA`); Puma serves `/favicon.svg`, `/favicon-32.png`,
`/apple-touch-icon.png` and `/og.png` as 200 with the right MIME; every local reference in
`site/` returns 200; headless Chrome over `/`, `/privacy.html` and `/terms.html` reports no
failed requests, no console errors, no third-party hosts and no horizontal overflow; the
1200×630 card was read back by a vision model with the text intact and nothing clipped; the
account and journey browser tests still pass; `script/brand-sweep.sh` exits 0.

### Added (`script/brand-sweep.sh`, the rebrand gate, 2026-11-12) — verified

- **The launch sweep now scans what ships instead of the whole checkout.** The replica-brand
  tool walks the filesystem and ignores `.gitignore`, so running it from the repo root also
  scanned prose and local run artifacts; it reported hits for this checkout's own directory
  name in agent notes and transcripts while every shipped surface was clean. The wrapper
  copies the tracked, non-prose files (`*.md` and `replica/` excluded, since the original
  belongs there as a comparison) into a temp tree and sweeps that: 95 files, exit 0.
  Untracked artifacts can no longer colour the result.
- Exit codes are `0` clean, `1` hits, `2` tool missing, so it can block a deploy. `AGENTS.md`,
  `TESTING.md` (quality gates), `ROADMAP.md` (M5 gate) and `replica/deploy.md` now name the
  script instead of the raw command.

Verified: exit 0 from the repo root and from another cwd; **negative controls** — planting
`Onetime Secret` in `site/index.html` gives exit 1 naming `site/index.html:6`, the same
string in `TASKS.md` or in an untracked file gives exit 0; `SWEEP=/nope` gives exit 2.

### Changed (account deletion is atomic, 2026-11-12) — verified

- **`DeleteAccount` runs as one Redis `MULTI`/`EXEC` instead of a chain of single commands.**
  Receipts, the owner index, every session record, the session index and the customer keys
  are queued after the two set reads and applied together, so a crash part-way through can
  no longer leave a half-deleted account (some receipts gone, the account still signed in).
  `Models::Session.digest_key` now owns the `session:<digest>` key shape so the deletion path
  and `Session.revoke_all` cannot drift apart.
- Account deletion is covered on all three levels it was missing: a new integration spec
  proves nothing is removed when the transaction fails, two Vitest cases pin the client call
  (`DELETE` + password body + `same-origin`) and the typed `401`, and the committed browser
  journey now deletes the account and checks `/api/v3/account/me` returns `401` afterwards.

Verified: `bundle exec rspec` → 110 examples, 0 failures; `npm --prefix frontend test` →
11 passing; `node e2e/accounts.mjs` and `node e2e/journey.mjs` against a live Puma `ok`.

### Added (account deletion, 2026-11-11) — verified

- **`DELETE /api/v3/account`** deletes the signed-in account: it asks for the password again
  rather than trusting the session, then removes the customer record, its email index, every
  live session and every receipt, and clears the cookie. A wrong password is `401` and
  deletes nothing (audited as `customer.delete_failed`).
- **Dashboard:** a "Delete account" section with a password field and a danger button.
- **Secrets that have not expired are left alone on purpose.** A link may already be in
  someone's inbox; that handover is not the account's to cancel, and the secret still expires
  on its own TTL.
- `API.md`, the OpenAPI document and `site/privacy.html` updated; the privacy page no longer
  says account deletion is missing.

Verified: 109 specs (5 new) — wrong password leaves the account intact, no session is `401`,
re-registering the freed email returns `201`, a live secret still reveals after deletion, and
`customer.deleted` is recorded in the audit stream.

### Added (landing site + legal pages, 2026-11-11) — verified locally, not deployed

- **`site/`** — a standalone static landing page plus `privacy.html` and `terms.html`, built
  from `replica/launch/landing.md`. Plain HTML with one local stylesheet: no build step, no
  third-party request, no analytics. It is deliberately not a Vue route, because the
  instance is the product and a marketing page would otherwise ship inside every self-hosted
  deployment.
- The privacy page states what is actually stored (secret ciphertext, receipts, account email
  plus Argon2id hash, hashed session tokens, request logs with no IP or body) and that the
  server can read a revealed secret — the honest version of D-012, not a zero-knowledge
  claim.
- The terms page states pre-alpha state, MIT licence, no warranty and no SLA, and leaves the
  operating entity and jurisdiction blank on purpose rather than inventing them.

Verified by headless Chrome at 1280px and 375px: all pages return 200, no page-level
overflow, even 55–56px section gaps, one `h1` per page, no duplicate ids, rendered contrast
16.74:1 (body), 7.30:1 (muted) and 5.47:1 (button); the only sub-3:1 pair is a decorative
hairline rule. Not deployed, no logo, no OG image, no analytics.

### Changed (R-09 rebrand, 2026-11-11) — verified (sweep, build, specs)

- **The product is now OneShotLink.** The original working title is gone from the UI, page
  title, OpenAPI document, README/PRD headings, package names, the Compose project, the CI
  image tag and the preflight default network name. Reason and screening evidence:
  `replica/brand.md`. The rebrand sweep exits `0` (baseline was 19 hits).
- **Rebranded copy** on the create/reveal/404 surfaces: "Share a secret once", "Create the
  link", "Your link, ready to send", "It can be opened once. Opening it deletes it." The
  passphrase is still described as an access check, never as zero-knowledge (D-012).
- **Operational consequence:** the Compose project is renamed, so volumes and networks are
  prefixed `oneshotlink_`. An existing instance keeps its data only if addressed by the old
  project name; nothing is migrated automatically. See DEPLOYMENT.md §3.
- **Accessible-name change:** the header brand link and `<title>` no longer say "One-time
  secret". Anything scraping the old title will notice.

### Added (go-live gate, 2026-11-11) — verified

- **`script/preflight_selftest.sh`** proves the gate cannot rot: it stands the app up
  behind a throwaway TLS terminator and asserts that `preflight.sh` passes on a good
  config and fails on a self-signed cert, a plain-HTTP 200, a host-reachable Redis, and
  a missing `HOST` (5 assertions, all passing). Wired into CI after the load test.
- **`script/preflight.sh`** turns the two remaining host gates into one command that
  exits non-zero on failure: HTTPS `200` with a validating chain, HSTS (rejecting
  `max-age=0`), the hardening headers, the session cookie's `Secure`/`HttpOnly`/`SameSite`
  flags (opt-in, since it creates an account), a plain-HTTP→HTTPS redirect, the Redis
  network being `internal`, and the host being **unable** to reach `redis:6379`. Supports
  `--cacert` and `--resolve` for pre-DNS verification. Verified against a local
  TLS-terminated stack: the pass path exits `0`, and untrusted certs, missing HSTS, a
  plain-HTTP 200, an unreachable host, and a reachable Redis each exit `1` with a
  specific message.

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

[Unreleased]: https://github.com/aman-ali07/OneShotLink/compare/v0.1.0...HEAD
