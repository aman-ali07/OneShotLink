# Known issues and gaps

Last reviewed: 2026-11-12. Severity: **S1** blocks use / security, **S2** blocks a
feature, **S3** quality/operability, **S4** documentation/process.

> The core has been executed: 119 backend specs pass in Docker against Redis DB 15, a live
> Puma run completed create → reveal → gone (including a four-way reveal race), a
> headless Chrome journey covered the built UI (including the passphrase path), and the
> production Compose stack passed a lifecycle smoke test. "Verified"
> below means a command was run, not file inspection. Ruby/Bundler are still absent on
> the host, so all Ruby commands run through the `ots-dev` image.

## Blocking (the app cannot run)

| ID | Sev | Issue | Evidence | Fix |
| --- | --- | --- | --- | --- |
| K-01 | — | **Resolved 2026-11-11:** secret lifecycle routes exist for v1 and v3; live create/reveal/gone verified | `lib/onetime/web/app.rb`, integration specs | — |
| K-02 | — | **Resolved 2026-11-11:** `Gemfile.lock` generated and all gems installed in Docker; suite runs | `Gemfile.lock` | — |
| K-03 | — | **Resolved 2026-11-11:** `bcrypt` declared; legacy verification covered by a spec | `Gemfile`, `spec/unit/password_spec.rb` | — |
| K-04 | — | **Resolved (M3):** simple-mode accounts, sessions, owner receipts, dashboard, and CLI create/reset are implemented | `spec/integration/accounts_spec.rb`, `e2e/accounts.mjs` | — |
| K-33 | — | **Resolved 2026-11-11:** `bin/ots` supports create/reset-password/list/show/set-role/health/backup/restore/rotate-key/version, ships in the image, and was executed in the production container | `bin/ots`, `Dockerfile` | — |
| K-34 | — | **Resolved 2026-11-11:** sessions are now indexed per customer (`customer:sessions:<id>`); changing a password calls `Session.revoke_all(keeping the caller)`, so every other live session is deleted. Verified live in the production container (other device → 401, caller → 200) and by `spec/unit/session_spec.rb`. Auth audit trail remains open (tracked separately). | `models/session.rb`, `web/app.rb`, `spec/unit/session_spec.rb` | — |
| K-35 | — | **Resolved 2026-11-12:** a GET used to consume the secret, so a chat client's link preview burned it. `GET /api/v3/{guest/,}secret/:key` now returns metadata only (`passphrase_required`, `kind`, `created_at`, `ttl`) and **`POST …/reveal` is the only consuming route**; the SPA already used POST, so only API clients change. Verified over HTTP: three GETs in a row left the key intact, POST revealed it once, the next GET was `404`, and a protected secret reported `passphrase_required: true` without leaking content. The frozen v1 GET still consumes (API.md §4) | `lib/onetime/web/app.rb`, `spec/integration/secrets_api_spec.rb`, API.md §5.2 | — |
| K-05 | — | **Resolved:** the repository is a git repo with history on `main`, an `origin` remote, and a `.gitignore` covering `.env` and build output | `git status`, `.gitignore` | — |
| K-06 | — | **Resolved:** `LICENSE` exists, is MIT ("Copyright (c) 2026 Aman Ali"), and is tracked | `git ls-files LICENSE` | — |

## Correctness / design risks

| ID | Sev | Issue | Evidence | Fix |
| --- | --- | --- | --- | --- |
| K-07 | — | **Resolved 2026-11-11:** `consume` now requires a non-empty expected value and raises otherwise; specs cover match/mismatch/empty | `lib/onetime/store.rb`, `spec/unit/store_spec.rb` | — |
| K-08 | — | **Resolved 2026-11-11:** the model writes one JSON string and `Store.consume` uses its exact bytes; an at-rest spec asserts ciphertext-only storage | `lib/onetime/models/secret.rb`, integration spec | — |
| K-09 | — | **Resolved 2026-11-11:** removed the unused `Crypto.data_key`; per-record keys derive from `SECRET` + per-record salt via one function (`Crypto.derive`). | `lib/onetime/crypto.rb` | — |
| K-10 | S3 | `Crypto.secure_compare` raises on non-string input (returns false first, so safe) but `OpenSSL.fixed_length_secure_compare` availability depends on the OpenSSL version | `crypto.rb:77` | Covered by unit spec T-14 on the pinned Ruby image |
| K-11 | S3 | `Onetime::NotFound#message` ignores any passed message, so route-specific context is lost (intentional for uniformity) | `lib/onetime/errors.rb:21` | Keep uniform; document if per-route messages are ever needed |
| K-12 | S3 | **Accepted 2026-11-12:** `Config` reads ENV lazily. In production the environment is fixed for the life of the process and `config.ru` validates it at boot, so a mid-process change cannot happen; the laziness is what lets the suite reshuffle ENV per example. Snapshotting at boot would buy nothing operationally and would break that test pattern | `lib/onetime/config.rb`, `config.ru` | Revisit only if config ever becomes reloadable at runtime |
| K-13 | — | **Resolved 2026-11-11:** max payload is enforced, `UI_ENABLED` is consumed, and the unused `CORS_ORIGINS` was removed from the env contract | `config.rb`, `app.rb` | — |
| K-14 | S3 | Limiter keys are `limiter:<client>:<scope>` and `...:counter`; the brief named `limiter:ID:object`/`limiter:ID:counter`. No functional issue, but docs/ops queries must use the real names | `lib/onetime/limiter.rb:23` | Documented in DATABASE.md §2 |
| K-15 | S3 | **Accepted 2026-11-12:** rejected requests do increment the fixed-window counter. That is what makes the window a limiter rather than a counter of successful work: a client cannot buy extra attempts by failing. `Retry-After` tells it when the window resets | `limiter.rb`, `app.rb`, verified live: 29 allowed then `429` with `retry-after: 60` | Keep fixed-window semantics; revisit only if a token bucket is chosen |
| K-16 | — | **Resolved 2026-11-11:** client IP now comes from `REMOTE_ADDR` unless that peer is in `TRUSTED_PROXIES`; spoofed and trusted-hop cases have integration specs | `app.rb#client_id`, DEPLOYMENT.md §4 | — |
| K-17 | — | **Resolved 2026-11-12:** the client is created with `timeout`, `connect_timeout`, `read_timeout`, `write_timeout` and `reconnect_attempts` from config, and redis-rb 5 is thread-safe, so one shared client is correct for a Puma thread pool. Verified under load: 200 secrets / 20 threads, 135.9 creates/s, every secret revealed exactly once, and a Redis outage surfaces as `503` + `Retry-After` (T-82) | `lib/onetime/store.rb`, `script/loadtest.rb` output | Revisit only if a per-thread pool is measured to be faster |
| K-18 | — | **Resolved 2026-11-11:** explicit `require "json"` plus a single `lib/onetime.rb` entrypoint with ordered requires | `lib/onetime.rb`, `store.rb` | — |
| K-19 | — | **Resolved 2026-11-11:** removed the swallowing `Config.secret` accessor; callers can only use `secret!` or `validate!` | `config.rb` | — |
| K-20 | S4 | Docs describe planned endpoints and UI; a reader who skips the banner may assume they exist | API.md, DESIGN_SYSTEM.md | Keep banners; link KNOWN_ISSUES in PR descriptions |
| K-21 | S3 | **Decided 2026-11-11 (D-012):** passphrase is an access gate, not a second encryption key. The original claims the server cannot decrypt without it; this clone can, by design. This is a deliberate parity gap | `crypto.rb`, `password.rb`, `docs/DECISIONS.md` D-012 | Keep copy honest ("extra access check"); revisit only as opt-in client-side v2 |
| K-22 | S4 | Recon evidence is partial: no browser/screenshot tool, no account access, sign-in/up pages not fetched; 16 of 20 screens are inferred | `replica/recon.md` sources table | Capture S01–S06 with the user present; mark verification per row |
| K-23 | — | **Resolved 2026-11-11 (R-09):** the key-derivation domain separator is `info: "ots-secret"` with a fresh random salt per record, so no stored record carries the brand and renaming cannot orphan a secret. The earlier note about a brand-named HKDF salt was stale: no such string exists in `crypto.rb` | `lib/onetime/crypto.rb:63` | Keep `info` stable; a change needs a re-encryption migration (T-65) |
| K-24 | S4 | Design tokens were derived from DESIGN_SYSTEM.md, not measured from the original: no screenshot tool/account was available. Contrast passes AA, but spacing/type parity is unverified | `replica/design/tokens.json`, K-22 | Validate against captured screens in M4; do not claim pixel parity |
| K-25 | — | **Resolved 2026-11-11:** the Vue build is served from `public/app`; `/`, `/assets/*`, and deep links verified over HTTP | `app.rb`, `frontend/` | — |
| K-26 | — | **Resolved 2026-11-11:** every rate-limited response and every success within a limit carries `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset`; verified live over HTTP and by integration spec. | `lib/onetime/limiter.rb`, `web/app.rb`, API.md §1 | — |
| K-27 | — | **Resolved 2026-11-12:** the exact 1 MiB boundary is asserted (`MAX_SECRET_BYTES` = 16: 16 bytes `201`, 17 bytes `413`) and the 0/1-character passphrase edges are covered | `spec/integration/secrets_api_spec.rb` | — |
| K-28 | — | **Resolved 2026-11-11:** Vitest covers the API client and `e2e/journey.mjs` is a committed puppeteer journey (create → reveal → gone + passphrase); CI runs it against the Compose stack | `frontend/src/lib/api.test.ts`, `e2e/`, `ci.yml` | — |
| K-29 | — | **Resolved 2026-11-11:** strict CSP, HSTS (under SSL), COOP/CORP, and Permissions-Policy are sent on every response and verified in the browser | `app.rb`, `web_spec.rb` | — |
| K-30 | S4 | Visual parity is unmeasured: no original screenshots exist (K-22), so token values and layout were not compared | `replica/design/`, K-22 | Capture reference screens with the user present; use `/replica-diff` |
| K-31 | S2 | Operational controls mostly closed: backup/restore, dependency scanning, key rotation, audit trail, Redis auth, `/metrics` (T-73), and the Redis host firewall (T-71) are done and verified. Remaining: **TLS termination on the real domain** (operator/host action, T-70 — the app side is rehearsed by `script/tls-rehearsal.sh`) and distributed tracing, which is not implemented | `PRODUCTION_READINESS.md`, `RUNBOOK.md` | T-70 |
| K-36 | — | **Resolved 2026-11-12:** a Redis at its memory ceiling reported `500 internal_error` and, because `compose.yaml` never set `--maxmemory`, `noeviction` enforced nothing and `onetime_redis_memory_used_ratio` was never exported. Now the OOM condition is a `503` + `Retry-After` like any other datastore outage, and Compose sets `--maxmemory` (`REDIS_MAXMEMORY`, default `256mb`). Measured on a 6 MB stack: the crossing write got `503`, and earlier secrets revealed intact once the ceiling was raised | `lib/onetime/web/app.rb#datastore_error?`, `compose.yaml`, `spec/integration/web_spec.rb`, DEPLOYMENT.md §9 | — |
| K-37 | — | **Resolved 2026-11-12:** the v1 form path capped only the *declared* `CONTENT_LENGTH`, which a chunked request does not send — Rack then parsed the whole form body before any validation, so 128 KB was accepted with `MAX_SECRET_BYTES=16` and a real deployment could be made to allocate whatever a client sent. The bytes actually read are now capped on the form path too, through the same helper the JSON path uses (`413` + nothing written; live proof: a 2 MB chunked form post answers `413`, a normal form post and v1 JSON still answer `200`) | `lib/onetime/web/app.rb#read_body_within_limit!`, `spec/integration/secrets_api_spec.rb` | — |
| K-32 | — | **Resolved 2026-11-11:** CI executed on GitHub across all four jobs. The first run failed in the container job: the load-test step ran a bare `docker compose down -v` with no env, and Compose interpolates `${SECRET}`/`${REDIS_PASSWORD}` on `down` too, so it aborted before restarting the stack. Fixed by hoisting the CI values to job level; the rerun (43060570677) is green and the load test reports 100/100 secrets revealed exactly once. | `.github/workflows/ci.yml` | — |

## Missing product behavior (planned, not bugs)

Accounts (simple mode), the dashboard, the admin CLI, OpenAPI generation, Docker packaging,
and CI **shipped** — see the resolved rows above; they were listed here long after they
existed. What is still missing: organizations, custom domains, file secrets, email jobs
(password reset, receipt notifications), MFA / WebAuthn / SSO, i18n locales, API v2, and
`AUTH_MODE=full` (D-003).

## Unanswered questions

1. Are file secrets required for v1, or is text-only acceptable at launch?
2. Which 27 locales are actually required, and do email templates need translation?
3. Is API v2 compatibility needed (the brief mentions it only once)?
4. Should consumed receipts be retained for owner audit, or deleted with the secret?
5. Should a wrong passphrase count against a per-secret attempt budget in addition to the
   per-IP reveal limiter? v1 answer: no per-secret budget (D-012).
6. What is the maximum acceptable TTL (currently 3 days by default options)? Longer TTLs
   increase blast radius if Redis leaks.
7. Is `AUTH_MODE=full` a launch requirement or explicitly post-v1? Current decision:
   post-v1 (D-003).
