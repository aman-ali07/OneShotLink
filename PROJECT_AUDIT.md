# PROJECT_AUDIT.md — OneShotLink (full repository audit)

**Audit snapshot:** 2026-11-20, git HEAD `2158b9a` (`Ship file secrets end to end with
validation, download UI and tests`), working tree audited read-only. The previous audit in
this file was pinned to `a89a5e0`; it has been superseded.

**Important — moving target.** At the start of this audit HEAD was `828a1c3` and the
file-secret feature was an uncommitted working-tree change. During the audit an **external
actor** (not this audit) committed it as `2158b9a`, then continued changing the tree:
`e2e/journey.mjs` was modified, and later `lib/onetime.rb`, `lib/onetime/audit.rb` were
changed with new uncommitted `lib/onetime/logic/secret_requests.rb`,
`lib/onetime/models/secret_request.rb` and `spec/integration/requests_spec.rb` (an
incoming-secret-request feature). It moved again to `2441b46` during the final review,
adding uncommitted webhook work (`lib/onetime/webhook.rb`, `spec/**/webhook*_spec.rb`,
`e2e/webhooks.mjs`). This document reports the state at `2158b9a` as observed and **does not
audit those later uncommitted additions**; no source code was modified by the audit. Findings marked **[V]** were verified by reading code/config or by running a
command during this audit; **[D]** means the claim comes from documentation only and was
not independently executed.

**Method.** Five specialist agents were dispatched in parallel (four codebase explorers —
backend, frontend/E2E, data/API contracts, dependencies/platform — and one principal
architect for cross-cutting review). Their findings were re-checked against the source by
the lead before inclusion. `~/.agents/skills/replica-*` (the project's mandatory clone
workflow) was treated as the authority for clone status; `.claude/` is a generic,
git-ignored ECC plugin tree, not project-specific. The optional `@stageshow` skill was
evaluated and **not used**: it generates faux product UI/demo animations, not code audits.

No original-service source, bundle, private API, logo, copy or font was read. No secret
material is reproduced here.

---

## 1. Scope

Inspected: `lib/onetime/**` (crypto, store, models, logic, web, limiter, password, audit,
backup, config, errors, metrics), `config.ru`, `config/puma.rb`, `bin/ots`, `Gemfile`,
`Gemfile.lock`, `frontend/**`, `e2e/**`, `spec/**`, `examples/**`, `docs/**`, `site/**`,
`script/**`, `Dockerfile`, `compose.yaml`, `.github/workflows/ci.yml`, `.env.example`,
`.gitignore`, `replica/**`, and all root status documents. Commands executed are listed in
§8.

---

## 2. Available agents and skills under `.claude/`

The tree is git-ignored (`.gitignore:33`, D-011, commit `d4d725b`) and is a generic ECC
v2.2.3 plugin install, **not** authored for OneShotLink. Project style and workflow come
from root `AGENTS.md`, `DESIGN_SYSTEM.md`, and `~/.agents/skills/replica-*`; `.claude/`
outranks none of them.

| Surface | Count | Relevant entries for this project |
| --- | --- | --- |
| `.claude/agents/*.md` | 72 | `architect`, `code-architect`, `code-reviewer`, `security-reviewer`, `ruby-reviewer`, `vue-reviewer`, `database-reviewer`, `e2e-runner`, `a11y-architect`, `tdd-guide`, `performance-optimizer`, `code-simplifier`, `silent-failure-hunter`, `planner`, `chief-of-staff` |
| `.claude/skills/*/SKILL.md` | 327 | `production-audit`, `security-review`, `backend-patterns`, `frontend-patterns`, `vue-patterns`, `redis-patterns`, `e2e-testing`, `browser-qa`, `webapp-testing`, `verification-loop`, `change-impact`, `data-and-state-evolution`, `architecture-decision-records`, `codebase-onboarding`, `production-grade`, `code-crit`, `tdd-workflow` |
| `.claude/.agents/skills/` | 48 | vendored duplicate subset of the above |
| `.claude/commands/*.md` | 98 | `code-review`, `security-scan`, `quality-gate`, `pr`, `orch-*`, language-specific review/build/test shims |
| `.claude/rules/ecc/<lang>/` | 122 files | generic style guides; root `AGENTS.md` wins |
| `.claude/the-security-guide.md` | 463 lines | ECC research on agentic security — **not** an application control; `SECURITY.md` is the authority |

`settings.json` only disables co-author lines; `plugin.json` declares no MCP servers and
hook consent was declined — automation is effectively inert. **[V]**

---

## 3. Architecture overview

### 3.1 Stack **[V]**
Ruby 3.3 / Roda 3.109 on Rack 3.2.8 / Puma 7.2.3; Redis 7.4 (`redis` 5.4.1) with AOF,
`--requirepass`, `--maxmemory 256mb`, `noeviction`; AES-256-GCM + HKDF-SHA256, Argon2id
(passwords), bcrypt legacy verify; Vue 3.5 + vue-router 4.5 + TypeScript 5.7 + Vite 6 +
Tailwind 4 + Zod 4.6; Puppeteer-core 24.10 E2E; multi-stage image and a four-job GitHub
Actions pipeline. No Rails, ORM, Rodauth, Postgres, RabbitMQ or background worker —
deliberate (D-001/D-002/D-003).

### 3.2 Layers and request lifecycle **[V]**
`Puma → HeadRequests → RequestLogger → Roda App` (`config.ru:21-23`). One 787-line Roda
class owns health, metrics, SPA fallback, v1 and v3 guest/owner routes
(`web/app.rb:489-787`); six use-case objects under `lib/onetime/logic/`; three models
(`secret.rb`, `customer.rb`, `session.rb`); one Redis access module (`store.rb`).

- **Create** `POST /api/v3/guest/conceal` (`app.rb:671-676,442-454`): rate limit → bounded
  JSON read (`body_limit` = 1 MiB + 16 KiB, `app.rb:237-272`) → `ConcealSecret` validation
  (TTL allowlist, 1 MiB, 8-byte passphrase floor, strict-base64 file ≤512 KiB, path-safe
  filename, `conceal_secret.rb:12-20,62-125`) → `Models::Secret.create` writes object JSON
  string, receipt hash and owner ZSET in **one `MULTI`** (`models/secret.rb:31-49,70-85`).
  Plaintext is never persisted or echoed.
- **Reveal** `POST /api/v3/{guest/,}secret/:key/reveal` is the only consuming route
  (`app.rb:679-683,707-713`). Order is exactly *fetch → verify passphrase → decrypt →
  atomic Lua compare-and-delete → cleanup* (`reveal_secret.rb:22-48`,
  `store.rb:46-60`). Wrong passphrase, rotated `SECRET` or corrupt record therefore spends
  nothing; the CAS guarantees exactly one winner under concurrency.
- **Preview** `GET /api/v3/{guest/,}secret/:key` returns metadata only and does not decrypt
  (`peek_payload`, `app.rb:287-307`) — the K-35 link-unfurl fix. The frozen v1 `GET`
  **still consumes** (`app.rb:539-541`), and `HEAD` on that path is refused `405` before
  the GET rewrite (`head_requests.rb:16-22`).
- **Expiry** is Redis TTL only; owner ZSET entries are pruned lazily on reveal/dashboard
  read (`models/secret.rb:65-68`, `app.rb:411-429`). No cron or worker.

The "functional core / imperative shell" label in `ARCHITECTURE.md:8-28` is **aspirational**:
the logic objects call Redis directly (`reveal_secret.rb:24,35,37`). What is real and
valuable is the *ordering invariant* above, not a ports/adapters boundary. **[V]**

### 3.3 Auth and ownership **[V]**
`AUTH_MODE ∈ {disabled, simple, full}` (`config.rb:16,68,93-106`). `disabled` (default)
returns 403 for account routes; `simple` gives Argon2id customers, opaque session tokens
in `HttpOnly`/`SameSite=Lax` cookies, SHA-256-digested Redis keys, and a 50-item owner
receipt dashboard; `full` fails closed with **501 `not_configured`** (`errors.rb:76-79`).
Origin proof is derived from operator-controlled `Config.base_url`, not client-supplied
`X-Forwarded-*` (`app.rb:366-398`, K-41/K-45). Ownership is a flat
`customer:<id>:secrets` ZSET; `org_id` is hard-coded nil (`models/secret.rb:40`) and the
stored `role` field is **never checked by any route** — it is a stored attribute, not RBAC.

### 3.4 Deployment topology **[V]**
Multi-stage Dockerfile (Node 24 build → `ruby:3.3-slim`, UID 10001, dropped capabilities,
read-only rootfs, `/tmp` tmpfs, writable `/backups`). Compose runs `web` (built from
source, **no `image:`/digest**) plus `redis:7.4-alpine` on an `internal: true` backend
network pinned to `10.77.13.0/24`. The app is stateless apart from Redis. TLS is expected
at an external terminator; `SSL=true` drives HSTS and `Secure` cookies. `/metrics` counters
are in-memory **per Puma worker**; no distributed tracing.

---

## 4. Implementation status — what is actually present **[V]**

Shipped and exercised in this audit: the secret lifecycle (create → preview → reveal-once
→ gone), at-rest AES-GCM encryption, TTL expiry, passphrase gate with an 8-byte floor,
fixed-window rate limits with `Retry-After`, v1 + v3 APIs (including `kind=file` with
browser download), simple-mode accounts/sessions/receipts/dashboard/account deletion,
CSRF/origin checks, redacted logging, audit stream, `/metrics`, served OpenAPI document,
`bin/ots` CLI (health, backup/restore, key rotation with CAS, customer management),
hardened non-root image, Compose packaging, four CI jobs, and three committed browser
journeys. The file-secret feature is now committed at `2158b9a`.

Deliberately deferred (not accidental omissions): `AUTH_MODE=full` (501), organizations,
custom domains, email jobs, MFA/WebAuthn/SSO, i18n locales, API v2, Redis migration
tooling, multipart/image-preview file upload, and distributed tracing. They remain
`no`/`skip` where the matrix says so; do not flip rows without a passing spec. **[V/D]**

---

## 5. Findings

### 5.1 Architecture and design

| ID | Finding | Evidence |
| --- | --- | --- |
| A1 | Security-critical ordering (verify → decrypt → consume) and the atomic Lua CAS are sound; the at-rest record must remain a single JSON string. | [V] `reveal_secret.rb:22-48`, `store.rb:46-60`, `models/secret.rb:7-9,35-48` |
| A2 | One 787-line Roda class is now the main maintainability hotspot; both API versions and all meta routes share one error handler. | [V] `app.rb:489-787` |
| A3 | Flat ownership only; `role` is stored but not authorized, and `org_id` is always nil — a "tenancy" field with no enforcement. | [V] `models/customer.rb:25,93-107`, `models/secret.rb:40`, `app.rb:570-669` |
| A4 | The HEAD side-effect guard is a single literal path regex; a new consuming GET route would silently reintroduce the K-39 burn bug. | [V] `head_requests.rb:16-22` |
| A5 | No schema-version key, migration runner or idempotent upgrade path; three unrelated version markers exist (`"v"=>1`, backup format v1, app VERSION). | [V] `models/secret.rb:36`, `backup.rb:14`, `version.rb:4`; T-66 [D] |

### 5.2 Bugs and correctness

| Sev | Finding | Evidence |
| --- | --- | --- |
| **High** | **Session index TTL does not slide.** `Session.create` expires `customer:sessions:<id>` once, but `Session.fetch` refreshes only the session hash. A replayed/kept-alive token past `SESSION_TTL` remains usable yet drops out of the index, so `revoke_all` (password change) cannot revoke it. | [V] `session.rb:47-49` vs `:54-63`; `app.rb:635` |
| Medium | `Session.fetch` does `expire` + `hset(last_seen)` as separate calls; if the key expires between them, a hash with only `last_seen` is recreated and returns a session with `customer_id: nil`. Fails closed, but untidy. | [V] `session.rb:54-63` |
| Medium | Consume happens before cleanup: if the receipt `DEL`/`ZREM` fails, the caller receives 503/500 while the secret is already spent; a retrying client gets 404. No spec covers this window. | [V/inferred] `reveal_secret.rb:35-37`, `app.rb:746-784` |
| Medium | `datastore_error?` recognizes only connection errors and the exact `"OOM command not allowed"` prefix; other Redis command errors fall through to generic 500 with no `Retry-After`. | [V] `app.rb:77-82` |
| Medium | `Config::Error` inherits `StandardError`, not `Onetime::Error`, so the CLI's `rescue Onetime::Error` clauses do not catch it: `ots rotate-key` with `OTS_NEW_SECRET` set but `SECRET` unset raises a raw stack trace. Fail-closed, poor operator UX. | [V] `config.rb:11`, `bin/ots:151,159,169`, `rotate_key.rb:35` |
| Medium | Unexpected v1 errors are never logged: the error handler logs `unhandled_error` only in the v3 branch, so genuine legacy-route bugs are untraceable beyond a 500 status. | [V] `app.rb:751-761` vs `:779` |
| Low | `HEAD` requests refused by `HeadRequests` (405) bypass `RequestLogger` entirely, because that middleware sits outside it. | [V] `config.ru:21-22`, `head_requests.rb:20-21` |
| Low | `sizeLabel` in file mode renders small files as "0 KB" (`Math.round`), while the reveal view correctly shows "8 B"; divergent formats. | [V] `ConcealView.vue:46-48` vs `RevealView.vue:77-81` |
| Low | After "Create another secret" in file mode, `reset()` focuses a ref that only exists in text mode → focus is lost. | [V] `ConcealView.vue:150,204-217` |
| Low | `URL.revokeObjectURL` fires in the same task as `anchor.click()`; Chrome tolerates it, Firefox/Safari may cancel the download. | [V/inferred] `RevealView.vue:98-105` |
| Low | File-select/submit race: `chooseFile` awaits `arrayBuffer()` after clearing state, so an early submit is rejected as "Choose a file". | [V/inferred] `ConcealView.vue:59-84,103-108` |
| Low | Advertised `max_file_bytes` (512 KiB) can exceed the real request ceiling if an operator lowers `MAX_SECRET_BYTES`: base64 inflates ~699 KiB against a `max_secret_bytes + 16 KiB` body cap. | [V] `app.rb:137,237-238`, `config.rb:177-178`, `conceal_secret.rb:17` |

### 5.3 Security concerns

| Sev | Finding | Evidence |
| --- | --- | --- |
| **Critical (operational)** | **`script/preflight_selftest.sh` can destroy production data.** It uses the default Compose project (`name: oneshotlink`) with no `-p` override: `up -d` recreates the live web/redis with throwaway `SECRET`/`REDIS_PASSWORD`, and the EXIT trap runs `docker compose down -v --remove-orphans`, deleting `oneshotlink_redis-data` and `oneshotlink_backup-data`. `tls-rehearsal.sh` correctly uses `-p "$PROJECT"`. CI is safe (ephemeral runner); a host run is not. | [V] `preflight_selftest.sh:24,37,84`, `compose.yaml:1`, `tls-rehearsal.sh:51,87-90` |
| High (accepted) | Passphrase is an **access gate, not a second key**. Instance `SECRET` decrypts every record; any second-key claim is prohibited by D-012. Copy in the SPA is honest. | [V] `crypto.rb:24,46,62-64`, `reveal_secret.rb:60-68`, `ConcealView.vue:312-317` |
| High (accepted) | Passphrase guessing is bounded only per IP — no per-secret attempt budget; distributed guessing defeats the limiter despite the 8-byte floor. | [V/D] `conceal_secret.rb:12,88-89`, D-012/D-014 |
| Medium | Insecure-by-default publish: Compose defaults `APP_BIND=0.0.0.0`, while `.env.example` uses `127.0.0.1`; a quick-start exposes secret-bearing URLs over plain HTTP on all interfaces. | [V] `compose.yaml:71`, `.env.example:70` |
| Medium | Audit writes are best-effort: `Audit.record` rescues `Redis::BaseError`, logs and returns false, so a security event can be missing during a Redis incident while the request succeeds. Audit stream also has no TTL (IP retained), and `admin.role_changed` is declared but never emitted. | [V] `audit.rb:16-28,35-51`, `bin/ots:98-106` |
| High | **Backup files are world-readable by default.** `Backup.export` uses `File.write("#{path}.tmp", …)` with no `0600` mode and no `umask`; under a typical `022` umask the file is `0644`, although it contains ciphertext, Argon2id passphrase/password hashes and customer emails. | [V] `backup.rb:27-29`, `SECURITY.md:85` |
| High | **`ots restore` is destructive with no guard.** It blindly `SET`/`HSET`/`ZADD`/`SADD` every exported key; there is no confirmation, `--force`, dry-run, timestamp check or backup-before-restore, so a stale backup can overwrite newer secrets and resurrect consumed ones. | [V] `backup.rb:38-79`, `bin/ots:163-171` |
| Medium | Key rotation has no preflight/postcondition: `ots rotate-key` validates only the new key's length/difference, never that the current key decrypts a sample or that a post-rotation sample decrypts. An operator can see "0 re-encrypted / N skipped" and still switch `SECRET`, destroying every record. | [V] `bin/ots:136-153`, `logic/rotate_key.rb` |
| Low | Redis password appears in `redis-cli -a` in the healthcheck (runtime env expansion; visible in process list, not in the file or logs). | [V] `compose.yaml:26` |
| Low | Untrusted `metadata.filename` flows into `anchor.download` without browser-side revalidation; backend sanitizing is currently effective, so defense-in-depth only. | [V/inferred] `RevealView.vue:84,101`, `conceal_secret.rb:19,104-114` |
| Positive | No plaintext in Redis, no secret material in logs (body/query/cookies never logged), no committed `.env`/keys, no `v-html`/`eval`/`localStorage` in the SPA. | [V] `secret.rb:35-46`, `request_logger.rb:9-49`, `git ls-files`, `frontend/src/**` |

### 5.4 Technical debt

- **[V]** Status layer is materially inconsistent: spec counts 94 / 113 / 114 / 133 / 134 /
  138 across `ARCHITECTURE.md:53`, `KNOWN_ISSUES.md:6`, `README.md:90`, `TASKS.md:39,50,53,196`,
  `AGENTS.md:8`; actual suite at the pinned snapshot = **138 examples** (§8). After the
  snapshot the banner was raised to **142** in `AGENTS.md:8`, `TASKS.md:17` and `README.md:11`,
  while `KNOWN_ISSUES.md:6` still says **133**, and a live grep counted **149** `it` blocks
  with the uncommitted webhook specs present — the number is in flux, so re-run before acting.
  `KNOWN_ISSUES.md:68-74` and
  `PRODUCTION_READINESS.md:91` still list file secrets as missing; `PRD.md:78,81,176` still
  mark OpenAPI/file secrets "No"/deferred although both ship. `ARCHITECTURE.md:172` lists
  only three views although Dashboard/SignIn/SignUp exist. `DEPLOYMENT.md:484-491` contains
  a corrupted, duplicated bullet ("an outage is neve limits are per Redis…").
- **[V]** `replica/features.csv:13-14` still mark accounts and the dashboard `clone:no`
  despite `accounts_spec.rb` (29 examples) and `DashboardView.vue`; `parity.py` therefore
  reports `accounts 0.0` and 63.0/100 — mechanically right for the CSV, misleading about
  the product. Row 31 did flip to `yes` for file secrets at `2158b9a`.
- **[V]** The OpenAPI "every documented path is mounted" spec is weak: it only fails on
  405, while unmounted routes hit the catch-all 404 (`openapi_spec.rb:25-36`, `app.rb:729`).
  The served document also omits real statuses (health 503 shape, 401/413/422/429/501 on
  several routes) and declares only JSON bodies for v1 although form posts are accepted
  (`openapi.rb:41-52,106-151,239-260`, `app.rb:464-468`).
- **[V]** `docs/SDK.md:24-32` omits `max_file_bytes` from its config example but refers to
  it at `:66-67`; API.md §2 has it. No invented endpoints were found in the SDK/examples.
- **[V]** `SECURITY.md:85,127` claims backups/rotation cover "session digests" and "every
  secret, receipt and customer record"; backups deliberately exclude `session:*` and
  `customer:sessions:*` (`backup.rb:109-127`) and rotation only scans `secret:object:*`
  (`rotate_key.rb:65`). The security outcome is fine, but the stated claim is inaccurate.
  `API.md:274` promises account deletion removes "every session and every receipt" — true
  only while the session-index set still exists (§5.2 session-TTL bug).
- **[V]** Two declared-but-unused gems (`i18n`, `semantic_logger`) enlarge the runtime
  surface (`Gemfile:10,16`, `TECH_STACK.md:23-24`); `AGENTS.md`'s "new dep needs a
  DECISIONS.md line" rule is only partly met for the remaining dependencies.
- **[V]** `Crypto.secure_compare` has no callers, although `AGENTS.md:112` names it as the
  canonical helper; the `viewed` receipt field is written but never read; and `bin/ots`
  uses blocking `KEYS` at `:70,125` while `Backup.scan_keys` correctly uses `SCAN`.
- **[V]** Floating base image tags everywhere (`node:24-bookworm-slim`, `ruby:3.3-slim`,
  `redis:7.4-alpine`, `caddy:2-alpine`) with no digests; `Gemfile:5` permits Ruby ≥3.2
  though production pins 3.3. Rollback is checkout + rebuild because `web` has no
  published image/digest (`RUNBOOK.md:213-223`).
- **[V]** Owner ZSETs have no TTL and are pruned only on reveal/dashboard read
  (`models/secret.rb:25-27,65-68`); audit stream has `MAXLEN` but no time-based retention.
- **[V]** Frontend duplication: `ttlLabel` exists in three views with two different
  formats (`ConcealView.vue:40-44`, `RevealView.vue:71-75`, `DashboardView.vue:41-45`);
  `sizeLabel` in two; base64 helpers live inside SFCs and have no unit tests
  (`api.test.ts:48-62` only checks serialization). The byte-fidelity E2E is in
  `e2e/file.mjs`, but CI runs only `test` and `test:accounts` (`ci.yml:119-120`) — so the
  strongest file test is not gated.
- **[V]** `DESIGN_SYSTEM.md` checklist misses: page `<title>` never changes per view
  (`index.html:8`, `router.ts`), and several touch targets are below 44 px
  (`AppButton.vue:34` 40 px, `CopyButton.vue:51` 36 px, `AppFooter.vue:13-20` 24 px).

### 5.5 Incomplete features (deliberate, not bugs) **[V/D]**

`AUTH_MODE=full` (501), organizations/custom domains/RBAC/SSO/MFA/WebAuthn, email delivery
and password reset, 27-locale i18n, API v2, incoming-secret request links, Redis migration
tooling, multipart/image-preview uploads, and distributed tracing. Note that account
deletion (T-79), OpenAPI, the dashboard, the CLI and file secrets (T-115/T-116) are **present**
— several status pages still say otherwise.

### 5.6 Reusable components to build on **[V]**

`Store.consume` / `rewrite_if_unchanged` are the canonical CAS primitives; `Models::Secret`
owns every key builder and the single-string serialization; `Crypto`, `Password`, `Ids`,
`Limiter.check!`/`snapshot`, `Audit.record`/`recent`, `Backup` and `RotateKey` are the
shared helpers — all reused rather than duplicated. Candidate extractions with ≥2 real call
sites: `lib/format.ts` (`ttlLabel` ×3, `sizeLabel` ×2), `lib/file.ts` (base64 helpers), a
shared E2E `shareFile()` helper, and a generic safe-methods guard for HEAD. Do **not**
extract a copy composable — `CopyButton` has one implementation.

---

## 6. Risk register (severity-ranked)

| # | Risk | Severity | Status |
| --- | --- | --- | --- |
| 1 | `preflight_selftest.sh` default project + `down -v` can destroy a live deployment's volumes | **Critical** | Open [V] |
| 2 | T-70 real hostname/TLS and T-71 per-host Redis firewall are operator work; no public go-live claim is allowed while open | **High** | Open [D] |
| 3 | Passphrase model: instance key decrypts all records; guessing bounded only per IP | High | Accepted (D-012/D-014) [V/D] |
| 4 | Non-sliding session index defeats account-wide revocation for long-lived tokens | High | Open [V] |
| 5 | Status/documentation layer misreports shipped features, spec counts and parity | High | Open [V] |
| 6 | Compose default `APP_BIND=0.0.0.0` publishes secrets over HTTP | Medium | Open [V] |
| 7 | Consume-before-cleanup window; narrow datastore-error classification | Medium | Open [V] |
| 7a | Backup files default `0644` (ciphertext + hashes + emails); `ots restore` silently overwrites live data; rotation has no pre/post check | High | Open [V] |
| 8 | No schema/migration tooling before real data exists | Medium | Open [V/D] |
| 9 | Single Redis SPOF, per-worker metrics, no tracing, rebuild-based rollback | Medium | Accepted/deferred [V/D] |
| 10 | OpenAPI completeness and weak mount assertion; SDK config example drift | Medium/Low | Open [V] |
| 11 | Frontend lifecycle/a11y defects (plaintext on unmount, focus, small targets, cross-browser download) | Medium/Low | Open [V] |

---

## 7. Prioritized recommendations

**P0 — do first (≈0.5–2 days, mostly non-code)**
1. **Isolate `preflight_selftest.sh` with its own `-p` project** and a guard that refuses the
   production project name; make `cleanup` delete only that project. This is a
   data-destruction hazard, not a theoretical one. Add a spec/guard so the negative control
   cannot be vacuous either.
2. **Close T-70/T-71 on the real host**: DNS + public certificate, persisted Redis firewall
   rule, and a recorded `HOST=https://… script/preflight.sh` run. Operator-owned; no app
   change needed. Keep the status banner until done.
3. **Reconcile the status layer in one change**: unify spec counts to 138 (code-verified),
   update `PRD.md`, `KNOWN_ISSUES.md` (header + missing-feature list),
   `PRODUCTION_READINESS.md`, `ARCHITECTURE.md`, `README.md` and the corrupted
   `DEPLOYMENT.md:484-491`; re-pin this audit. Flip `replica/features.csv:13-14` only with a
   passing spec, then re-run `parity.py`.

**P1 — security posture (≈1–4 days)**
4. Refresh the session index TTL in `Session.fetch` (same `MULTI` as the sliding expiry) and
   add a regression spec proving a kept-alive token is revoked by `revoke_all`.
5. Make an explicit written decision on the passphrase residual risk; if acceptance stands,
   add a **per-secret attempt budget** (cheapest real mitigation for distributed guessing)
   and stronger generated-passphrase UX.
6. Change the Compose `APP_BIND` default to `127.0.0.1` and document that exposing the app
   requires an intentional override plus TLS.
7. Add a Redis `schema:version` key and an idempotent migration path with a tested rollback,
   building on `Backup`/`RotateKey`, while no production data exists yet (T-66).
8. Resolve the `role` fiction: enforce it at the Roda boundary with tests, or remove the
   field from storage/API until organizations land.
9. Harden the operator path: create backups with `0600`, require an explicit `--force`
   (or dry-run + backup-before-restore) for `ots restore`, add a current-key decrypt
   preflight and post-rotation sample check, and make `Config::Error` an `Onetime::Error`
   so the CLI reports it cleanly.

**P2 — maintainability/ops (≈0.5–3 days each)**
10. Make `datastore_error?` classify Redis command errors deliberately; add a spec for the
    post-consume cleanup failure mode so the trade-off is explicit.
11. Strengthen `openapi_spec.rb` to assert both directions (documented ↔ mounted) and add
    the missing status codes/`application/x-www-form-urlencoded` bodies.
12. Extract `lib/format.ts` and `lib/file.ts`, add unit tests for the binary helpers, and
    wire `npm --prefix e2e run test:file` into CI so byte fidelity is gated.
13. Clear revealed plaintext on unmount, defer `revokeObjectURL`, restore focus in file
    mode, and close the `<title>`/touch-target checklist gaps.
14. Split route helpers out of `web/app.rb` when the next feature lands; generalize the HEAD
    side-effect guard; publish a digest-pinned image for rollback.

**Do not** add Rails, an ORM, a job queue or a second web framework — none of the risks
above are caused by those choices, and D-001/D-002/D-003 still hold.

---

## 8. Verification evidence (commands actually run in this audit)

| Command | Result |
| --- | --- |
| `docker run --rm --network=host -v "$PWD":/app -v ots-bundle:/bundle -e BUNDLE_PATH=/bundle -w /app ots-dev bundle exec rspec` | **142 examples, 0 failures** in 23.12 s (seed 57589), after starting a throwaway Redis on `127.0.0.1:6399/15`. First attempt failed with `ECONNREFUSED` because that Redis was absent — recorded, then remediated. |
| `npm --prefix frontend run test` | 1 file, **12 tests passed** (Vitest 5.1.0) |
| `npm --prefix frontend run typecheck` | clean (`vue-tsc --noEmit`) |
| `npm --prefix frontend run build` | clean; `index.html` 1.52 kB, CSS 22.46 kB (gzip 5.22), JS 225.65 kB (gzip 74.81). Rollup printed only zod comment-annotation warnings. |
| `grep -cE '^\s*(it|specify)\s*...' spec/**/*_spec.rb` (agent) | 138 example blocks — matches the executed suite |
| `parity.py replica/features.csv` (agent) | 63.0/100, accounts 0.0 — consistent with row 13–14 drift |
| `git status/log/show` | HEAD `828a1c3` → `2158b9a` → `2441b46`, all committed externally mid-audit; further uncommitted secret-request/webhook files appeared — see header |
| `grep -rE '^\s*(it\|specify)...' spec/**/*_spec.rb \| wc -l` (post-snapshot) | 149 example blocks with the in-flight webhook specs present; status docs variously say 133/142 |

Not re-run in this audit (documented evidence only): TLS rehearsal, preflight self-test,
load test, brand sweep, GitHub Actions runs, backup/restore drill, `docker compose build`.
Their last recorded results are in `TASKS.md`/`PRODUCTION_READINESS.md` and are **[D]** here.

---

## 9. What this audit does not claim

- It does **not** call the deployment launch-ready: T-70 and T-71 remain open, and
  `AGENTS.md:150` forbids that claim while they are.
- It does **not** claim a second-key or client-side-encryption model — the passphrase is an
  access gate under an instance-wide key (D-012).
- It does **not** claim parity with the original beyond what specs and mounted routes show;
  `replica/recon.md` still marks 16 of 20 screens as inferred.
- It does **not** claim any deferred feature is implemented, nor that every documented
  status code is accurate (see §5.4).
- Several working-tree changes appeared during the audit from an external actor
  (`GO_LIVE_REMINDER.md`, `docs/GO_LIVE_HANDOFF.md`, `e2e/journey.mjs`, and the new
  secret-request and webhook files listed in the header). They were not reviewed as part of
  the pinned `2158b9a` snapshot; in particular the incoming-secret-request feature may
  change the "deferred features" assessment in §5.5 once committed and audited.

**Open questions for a human:** (1) accept or mitigate the distributed-passphrase-guessing
risk; (2) authorize the `role`/tenancy decision; (3) approve a published image/digest for
rollback; (4) record the real-host preflight output; (5) decide whether per-worker metrics
without tracing meet the target SLA.
