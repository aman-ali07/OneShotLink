# Implementation plan — OneShotLink

**Date:** 2026-11-21. **Status legend:** `DONE` (executed and evidenced), `READY` (no decision or protected-path approval needed), `DECISION` (blocked on a recorded product decision), `APPROVAL` (blocked on human review of a protected path), `OPERATOR` (host action), `TODO`, `DEFER`.

Every phase ends with a verifiable command. No phase is called done on inspection alone. Architectural basis: [ARCHITECTURE.md](ARCHITECTURE.md); competitor basis: [COMPETITOR_RESEARCH.md](COMPETITOR_RESEARCH.md); priorities: [FEATURE_MATRIX.md](FEATURE_MATRIX.md) §5.

## 1. Current state (verified, not assumed)

| Evidence | Result |
|---|---|
| Git HEAD | `741e71f Ship signed, idempotent webhooks end to end (T-118)` |
| Working tree | `git diff --shortstat` → **47 files changed, 1636 insertions(+), 585 deletions(-)** (hardening + research + planning); descriptions in this plan reflect the working tree, not HEAD |
| Backend suite | **180 examples, 0 failures** — `docker run --rm --network=host -v "$PWD":/app -v ots-bundle:/bundle -e BUNDLE_PATH=/bundle -e REDIS_URL=redis://127.0.0.1:6398/15 -w /app ots-dev bundle exec rspec` (seed 58382, 50.9 s) |
| Frontend | Vitest 12/12, `vue-tsc --noEmit` clean, Vite build clean (239.75 kB JS / 22.77 kB CSS) |
| Parity tool | `python3 ~/.agents/skills/replica-diff/parity.py replica/features.csv` → `66.7/100`, 11/11 must-haves |
| Committed journeys | `e2e/journey.mjs`, `accounts.mjs`, `requests.mjs`, `file.mjs`, `webhooks.mjs` (five; the webhook one covers create/list only) |
| Protected paths | `crypto.rb`, `password.rb`, `models/session.rb`, `web/app.rb`, `compose.yaml`, `Dockerfile`, `config.ru`, `config/puma.rb`, `.github/workflows/`, `script/preflight*.sh`, plus anything under `auth/`, `payments/`, `secrets/`, credentials or `*.pem`/`*.key` — **human approval before editing** (AGENTS.md operating rule 4) |
| Open gates | T-70 TLS on real hostname, T-71 host Redis firewall, K-46 webhook worker scheduling; SA-06/14/16/22 from [SECURITY_AUDIT.md](SECURITY_AUDIT.md) §10 |

Documentation debt fixed by this plan's own phases: `PRD.md`, `ROADMAP.md`, `ARCHITECTURE.md`, `TASKS.md`, `API.md`, `KNOWN_ISSUES.md` still carry 94/133/149/178 spec counts and "file secrets/OpenAPI not implemented" statements contradicted by code. Code and executed commands are the source of truth.

## 2. Dependency graph

```
[OPERATOR, parallel, no code]  T-70 real TLS · T-71 host firewall · schedule webhooks:work (K-46)
        │ unblocks "production ready" claim; does not block code
        ▼
P0-1 Contract truth (openapi.rb + openapi_spec) ─┐
P0-2 Backup coverage + narrow allowlist ──────────┤ no new routes; prerequisite for record-shape work
P0-3 Migration substrate (schema:version, ots migrate --dry-run) ─┤
P0-4 Bounded defects (SA-06 wrap, SA-16 counter, B8 id-scope) ────┘
P0-5 Close the v1 metadata-MAC downgrade path (hard security gate) ─┘
        ▼
[PRODUCT DECISIONS → docs/DECISIONS.md]
  D-012b per-secret budget?  ·  receipt status/burn semantics?  ·  token model?  ·  request AUTH_MODE?
        │            │                 │                 │
 P1-1 receipt    P1-2 attempt    P1-3 API tokens   P1-4 ots conceal/reveal
 lifecycle      budget          (APPROVAL)        (depends on P0-1 only)
        └────────────┬────────────┬───────────────┘
                     ▼
P2-1 generator + QR/mailto · P2-2 file cap/previews · P2-3 richer requests
P2-4 /llms.txt + generated types (APPROVAL for route) · P2-5 i18n (new dep decision)
        ▼
Go-live gate repeat → repeatable deploy (human) → M7 deferred (orgs, SSO, client-side encryption)
```

**Sequencing rules:** no new API endpoint before the contract gate is bidirectional; no record-shape change before backups and migrations cover it; **no P1 feature before P0-5 closes the MAC downgrade path**; no P1 feature before its decision is written; one concern per change; no deploy, key rotation or restore performed by an agent.

## 3. Completed work (condensed — detail in ROADMAP.md / TASKS.md)

| Milestone | Status | Evidence |
|---|---|---|
| M0 runnable core; M1 secret lifecycle; M2 UI slice; M2.5 packaging; M3 simple accounts; M4 verification; M5 brand; M6 in-repo ops | **DONE** | 180 specs, five journeys, hardened Compose, TLS rehearsal, preflight self-test 5/5, load test 100/100 exactly once |
| File secrets (T-116), incoming requests (T-117), signed webhooks (T-118) | **DONE** | `e2e/file.mjs`, `e2e/requests.mjs`, `spec/unit/webhook_spec.rb:126-207`; working tree adds hardening specs |
| Security architecture audit and fixes (SA-01/02/03/04/05/07/08/09/10/11/12/13/15/18/20/21) | **DONE** | `SECURITY_AUDIT.md` §3/§4; working tree has IP-pinned webhooks, 3-shape rotation, metadata MAC, 0600 backup, guarded restore, isolated self-test, sliding session index |
| `@stageshow` artifacts | **DONE** | `docs/stageshow/`, `docs/security-posture.*`, `docs/competitor-posture.*`, `docs/roadmap-posture.*` |

## 4. Next increment — milestones, steps, acceptance

**Status (2026-11-21):** P0-1 (contract truth), P0-2 (backup coverage), P0-3 (migration
substrate), P0-4 (bounded defects) and P0-5 (metadata integrity, including request objects)
are **landed and verified** — see `TASKS.md` T-119/T-120/T-130 and the red→green specs named
in each section. P1-4 (`ots conceal`/`ots reveal`) is also landed, using a stdlib HTTP client
against the public v3 API and proven live (create → reveal once → replay `404`). Still open
by explicit decision: P1-1 receipt lifecycle (retention decision) and P1-3 bearer tokens.
The following were **resolved and landed at ₹0** on 2026-11-21: D-012b (per-secret
passphrase budget via the existing Lua limiter), D-retention (daily rotating IP digest in
audit instead of raw IP), D-queue (7-day queue/delivery TTL with atomic pruning), and C2
(public request preview/respond with rate limits; owner routes stay authenticated). T-70/T-71
use free Caddy/Let's Encrypt and the host's own firewall via `script/host-firewall.sh`; the
app side passed the 7-assertion TLS rehearsal, while DNS, the public certificate and the
firewall change remain server-owner actions. See `docs/DECISIONS.md` for all trade-offs.

### P0-1 — Contract truth (READY) — effort S

| Step | Files | Acceptance |
|---|---|---|
| 1.1 | `lib/onetime/web/openapi.rb` | Every v1 error response (`429`, `503`, plus `413`/`422` on share and `401`/`429` on reveal) resolves to `LegacyError`, not the v3 `Error` envelope. `LegacyError` already exists at `openapi.rb:431-434`; parameterise the shared `rate_limited` helper by version instead of cloning it. |
| 1.2 | `openapi.rb` | Add `/metrics` (mounted `app.rb:594-604`) and the v1 form body (`application/x-www-form-urlencoded` alongside JSON); document every status each route can emit (429/501/503). Runtime v1 shapes are **not** changed. |
| 1.3 | `spec/integration/openapi_spec.rb` | Gate rejects the **generic catch-all body** (`{"error":{"code":"not_found","message":"Not found."}}`), not merely any 404 — domain `NotFound` legitimately 404s for substituted `somekey` on `guest/secret/{key}`, `requests/{key}` and `v1/secret/{key}`. Add a reverse check "every mounted API path is documented". Roda exposes no route table, so the mechanism must be decided here: instrument the app to expose its mounted API paths, or keep one explicit registry in the spec and accept it as a deliberate second source of truth — do not duplicate path lists across files. Prove the gate with a deliberately bogus documented path (must fail). See FEATURE_MATRIX B3. |
| 1.4 | `API.md`, `FEATURE_MATRIX.md`, `CHANGELOG.md`, `TASKS.md` | Remove "OpenAPI not implemented"; record B1–B4/C1/C3 as done. |
| 1.5 | `docs/DECISIONS.md:14-16` | Correct D-001: Roda is the decision, but there is no `apps/` directory — all v1/v3 routes live in the single class at `app.rb:15,565-905`. The stale folder claim misleads future design. |
| 1.6 | `openapi.rb`, `spec/integration/openapi_spec.rb`, `spec/integration/secrets_api_spec.rb` | Close the remaining verified drift: add `required: ["message"]` to `LegacyError` (`:431`); add missing 429 on owner **peek/describe** GET (`:222-236` vs `app.rb:878`) and webhook POST/DELETE (`:123-151` vs `app.rb:797,818`); add 503 to all `/api/v3/requests*` and `/api/v3/webhooks*` paths; replace 3.0-style `"nullable": true` (`:505`) with 3.1 `type: %w[string null]`; align the webhook path `{key}`→`{id}` (`:143` vs `app.rb:809`) **and change the gate's substitution at `openapi_spec.rb:30` in the same step** or it breaks. Document `/api/v3/openapi.json` itself. Add a spec asserting the **v1 GET reveal consumes** (`app.rb:614-621`) — currently asserted only via POST. That spec must also lock the security constraint: v1 is never linked from the SPA, HEAD stays 405 (`head_requests.rb:22-26`), and the residual is recorded in `SECURITY.md` §5. |

**Acceptance command:** `docker run … ots-dev bundle exec rspec spec/integration/openapi_spec.rb spec/integration/secrets_api_spec.rb` → green; full suite still `180+/0`; `git diff --check` clean. New gate example must be seen **red** before 1.1–1.3.

### P0-2 — Backup and restore coverage (READY) — effort M

| Step | Files | Acceptance |
|---|---|---|
| 2.1 | `lib/onetime/backup.rb` | Export `request:object:*`, `request:secret:*`, `webhook:endpoint:*`, `webhook:owner:*`, `webhook:queue`, `webhook:delivery:*` with TTLs; keep ciphertext-only and `0600`; bump `FORMAT_VERSION` to 2; `restore` accepts formats 1 and 2 with optional new sections. |
| 2.2 | `backup.rb` | Replace prefix allowlist with an explicit predicate that **rejects** `customer:sessions:*`, `webhook:seen:*`, `webhook:inflight:*`; preserve the `--force` overwrite guard. |
| 2.3 | `spec/unit/ops_spec.rb` | Red→green: export/flush/restore one of every new key type with values and TTLs intact; a crafted dump containing `customer:sessions:*` is rejected; a format-1 fixture still restores. |
| 2.4 | `DATABASE.md`, `SECURITY.md`, `docs/DECISIONS.md`, `CHANGELOG.md` | Document the new namespaces, format v2 and the decision to exclude ephemeral dedup keys. Regenerate `DATABASE.md`'s key catalogue from code — it currently has zero `request:`/`webhook:` entries and a phantom `viewed_at`. |
| 2.5 | `backup.rb` | Add an explicit `no_ttl` flag to format v2. Export must distinguish "no TTL by design" from `ttl <= 0` observed during scan; restore refuses to bare-`SET` a secret record without that flag. Fix `backup.rb:61-67,142` so a near-expiry record cannot become permanent. Red→green: export a 1-second record, wait for expiry, restore, assert no permanent key. |
| 2.6 | `logic/secret_requests.rb` | Bound `request:secret:*` by the **remaining** request TTL (`TTL request:object:<key>`), not the full `record["ttl"]`; handle `-1`/`-2` explicitly. Red→green with a short window. |
| 2.7 | `backup.rb` | Replace the global prefix union with **per-section prefix and type** predicates (`secret:object:*` only in the `secret` section, etc.); a `secret:object:*` key planted in the `customer` section must be rejected. Include `schema:version` (added by P0-3) in export or have `migrate` re-derive it on restore. Preserve zset scores for `webhook:queue` and owner indexes. |
| 2.8 | `backup.rb`, `RUNBOOK.md` | Make restore transactional or explicitly document partial-restore recovery; a dry-run **on a copy** is mandatory before apply. Restore remains a human action. |

**Acceptance command:** `docker run … ots-dev bundle exec rspec spec/unit/ops_spec.rb` → green; then the full suite. The destructive restore drill on a **copy** is a human action per `RUNBOOK.md` — an agent must not restore into a live instance.

### P0-3 — Migration substrate (READY) — effort S/M

| Step | Files | Acceptance |
|---|---|---|
| 3.1 | `lib/onetime/backup.rb` or new `lib/tasks/`, `bin/ots` | Write/read `schema:version`; add `bin/ots migrate --dry-run` with a version gate. Today no key, no directory and no CLI verb exist (`DATABASE.md:42,173-181` planned only). |
| 3.2 | new `spec/unit/migration_spec.rb` | Dry-run reports intended writes without touching Redis; applying once is idempotent; a downgrade is refused. |

**Depends on:** P0-2 (so a migration can be backed up). **Acceptance:** `bin/ots migrate --dry-run` exits 0 and changes no keys; full suite green.

### P0-4 — Bounded defects (partly APPROVAL) — effort S

| Step | Files | Acceptance |
|---|---|---|
| 4.1 | `lib/onetime/logic/reveal_secret.rb` | Wrap post-consume `Models::Secret.cleanup` so a receipt/index failure cannot turn a spent secret into 500/503 (SA-06). Plaintext still returned once. |
| 4.2 | `lib/onetime/audit.rb` | `audit:dropped` counter on the rescue path; explicit retention decision recorded (`MINID` trimming). No IP retention change without a decision (SA-16). |
| 4.3 | `lib/onetime/webhook.rb`, `web/app.rb` | DONE 2026-11-21 (explicit operator approval): pass `:id` to `Webhook.deliveries`, add `Webhook.owned?`, answer `404` for unknown/foreign ids (B8). |
| 4.4 | specs | Red→green: a forced Redis error after consume still returns the plaintext; dropped counter increments; two endpoints for one owner → deliveries for the requested id only. The cleanup rescue must emit a warning and increment a counter — **not** swallow the error silently (AGENTS rule 6). |

**Priority note:** FEATURE_MATRIX §5 #9 ranks this bundle P2; this plan promotes it to P0 because SA-06/SA-16 are security/observability defects with small effort. FEATURE_MATRIX #9 will be updated in the same change that lands P0-4.

### P0-5 — Close the metadata integrity gaps (READY) — effort S/M — **hard gate before any P1**

The four-review pass found that the v2 MAC is **not** the control the docs claimed: `models/secret.rb:82` returns early for `v < 2`, so a Redis writer can set `v: 1`, delete `passphrase_hash` and `meta_mac`, and reveal succeeds with no passphrase. `spec/integration/security_hardening_spec.rb:53-63` currently asserts that downgrade works. The `request:object:*` record also has no MAC (`secret_request.rb:22-37`), yet reveal authorises on its unsigned `owner_id` (`secret_requests.rb:94`).

| Step | Files | Acceptance |
|---|---|---|
| 5.1 | `lib/onetime/models/secret.rb` | `verify_meta!` rejects **any** record whose `v != 2` or whose `meta_mac` is absent/invalid with typed `Onetime::Error`; remove the legacy early-return. Since there is no pre-release data (`DATABASE.md:173`), no migration window is needed. |
| 5.2 | `spec/integration/security_hardening_spec.rb` | Replace the "legacy unversioned record still reveals" example with a red→green test: downgrade `v` to 1, strip `passphrase_hash`/`meta_mac`, reveal → typed error, no plaintext, record intact. Existing v2 tamper tests stay green. |
| 5.3 | `lib/onetime/models/secret_request.rb`, `logic/secret_requests.rb` | Bind `owner_id`, `label`, `ttl` into a MAC under `SECRET` (reuse `Models::Secret.sign_meta!` if its field set is parameterised; do not build a second MAC helper). Verify before owner check. **Do not** add a new crypto primitive. |
| 5.4 | `SECURITY.md`, `SECURITY_AUDIT.md`, `DATABASE.md`, `ARCHITECTURE.md` | Remove the "bounded legacy window" claim; record the downgrade path as closed and the request-object signature as present. Never claim E2EE. |

**Acceptance command:** `docker run … ots-dev bundle exec rspec spec/integration/security_hardening_spec.rb spec/integration/requests_spec.rb` → green; full suite green; the new downgrade spec was seen red before 5.1.

### P1-1 — Owner receipt lifecycle (DONE 2026-11-21 — D-017) — effort M

**Decision recorded in `docs/DECISIONS.md` D-017 (operator):** keep the receipt after reveal
with statuses `new → previewed → revealed → burned`, retain non-sensitive metadata 30 days,
permanently delete the payload, and expose an owner-only burn route. The token/receipt API
sub-model in step 1.3 remains deferred — the opaque key is the capability and no separate
receipt token decision has been made.

| Step | Files | Acceptance |
|---|---|---|
| 1.1 | `models/secret.rb`, new `models/receipt.rb` only if ≥2 real call sites | Expand receipt hash with `receipt_token` (SHA-256 digest), `status`, timestamps; new `receipt:index:<digest>` with remaining TTL; legacy readers treat missing `status` as old receipts. |
| 1.2 | `bin/ots migrate receipt-status --dry-run` | Additive fields; no usable token for legacy receipts (document this honestly); rollback = code revert + expiring orphan index. |
| 1.3 | `web/app.rb` (APPROVAL), `web/openapi.rb`, `request_logger.rb` | New `/api/v3/receipt/:token` preview + burn endpoint with CSRF, rate limit, owner scoping (non-owner → uniform 404), no plaintext in receipts. |
| 1.4 | `frontend/src/router.ts`, `views/ReceiptView.vue`, `DashboardView.vue`, `lib/api.ts`, new `e2e/receipt.mjs` | Browser journey: create → keep receipt link → status changes → burn unread secret → recipient sees gone. |

### P1-2 — Per-secret passphrase attempt budget (DECISION) — effort M

**Decision first:** reverse or narrow D-012 — budget value, whether wrong guesses count, interaction with per-IP limiter, and explicitly "wrong guesses never consume".

| Step | Files | Acceptance |
|---|---|---|
| 2.1 | `store.rb`, `models/secret.rb`, `logic/reveal_secret.rb` | New `secret:attempts:<objid>` counter with Lua INCR+TTL; checked before `verify_passphrase!`; never touches plaintext or logs; verify→decrypt→consume unchanged. |
| 2.2 | specs + `script/loadtest.rb` | N wrong then correct → 200 with record intact; budget exhausted → 429/401 with record readable; 8-way race still exactly one winner. |

### P1-3 — Bearer API tokens (DECISION + APPROVAL) — effort M/L

**Decision first:** token model, scopes, revocation, and whether owner routes accept cookie **or** token. Must not weaken `verify_csrf!` on the cookie path (`app.rb:437-474`) or guest routes.

| Step | Files | Acceptance |
|---|---|---|
| 3.1 | new `models/api_token.rb` + logic, `web/app.rb` (APPROVAL), `openapi.rb`, `SECURITY.md` | Digest-at-rest tokens, `Crypto.secure_compare`, rate-limited by token, never logged, OpenAPI `http/bearer` scheme. |
| 3.2 | specs | Token-auth create/reveal works; cross-site cookie mutation still 403; guest routes unchanged. |

### P1-4 — `ots conceal` / `ots reveal` (READY) — effort S

Calls the HTTP API (same sequence as `examples/`), never Redis directly; no secret in argv or logs, and design the input so it never enters shell history (this is a design constraint — a spec can prove argv/log hygiene, not shell history). No new gem (`Net::HTTP`/`Open3` are stdlib). Acceptance: new CLI spec + a **manual** run with log inspection; `docs/SDK.md` and `examples/` updated. Depends only on P0-1 (trustworthy contract).

### P2 phases (each with its own decision/gate)

- **P2-1 generator + QR/`mailto:` share** — pure frontend, Web Crypto, no new dep; typecheck/build/Vitest + journey. **READY**.
- **P2-2 larger/multi-file + sanitized previews** — raises `MAX_FILE_BYTES` ↔ `MAX_SECRET_BYTES` together (the body ceiling already derives from `MAX_SECRET_BYTES`; `conceal_secret.rb:14-18`), changes the base64 payload, protected `app.rb` (APPROVAL). Treat competitor 2026 XSS advisories as the primary risk: strict CSP, no `v-html`. **A sanitizer would be a new dependency** — AGENTS rule 8 requires a `docs/DECISIONS.md` entry and canonical-package check before adding one; the current design has no sanitizer.
- **P2-3 richer inbound requests** — file answers, passphrase, substitution fingerprint; needs the `AUTH_MODE` decision because request routes call `require_accounts!` (`app.rb:769,774`) and default mode is `disabled`.
- **P2-4 `/llms.txt` + one-way generated types** — static route in protected `app.rb` (APPROVAL); stdlib generator from the served document, no second contract file; new package only with `docs/DECISIONS.md` entry (AGENTS rule 8). Do **not** claim `/mcp` as an existing or rejected feature: `docs/DECISIONS.md:160-163` (D-011) only says a future MCP server would require a minimal tool config — it neither implements nor forbids one.
- **P2-5 i18n** — new npm dependency decision; extract 7 views + 6 components; RTL and `<html lang>` in scope; `TASKS.md:166` T-64 is the status-of-record slot.

## 5. Decisions needed before implementation

| ID | Decision | Unblocks | Owner |
|---|---|---|---|
| D-012b | **RESOLVED 2026-11-21 — D-012b in `docs/DECISIONS.md`.** Reused the Redis `passphrase` limiter scope keyed by the opaque secret id: 5 guesses per dedicated 900 s window, only on records with a passphrase. Wrong guesses count, never consume, and exhaustion is `429` with the record intact; per-secret exhaustion DoS accepted explicitly. Counter expires with the window (no backup needed). | P1-2 | Product + security |
| D-receipt | **Resolved 2026-11-21 by the operator and recorded in D-017:** keep the receipt, statuses `new→previewed→revealed→burned`, 30-day metadata retention, payload permanently deleted, burn CSRF-checked + rate-limited + owner-scoped with uniform 404, no plaintext/keys/passphrases in receipts or logs. | P1-1 | Product |
| D-token | API-token model, scopes, revocation. **Security constraint:** the cookie path still runs `verify_csrf!` even when a token is present; a token must not bypass `require_accounts!`/`require_session!`; guest routes unchanged; digest-at-rest + `Crypto.secure_compare`; token-scoped limiter; immediate revocation; no token in audit `detail`. | P1-3 | Product + security |
| D-request-mode | Whether public request preview/respond work in `AUTH_MODE=disabled` (current code says no). **Security constraint:** unauthenticated respond keeps `enforce_rate_limit!(:conceal)` (`app.rb:354`) and never exposes owner fields; today `require_accounts!` blocks both (`app.rb:769,774`). | P2-3 and contract C2 | Product + security |
| D-migrate | **RESOLVED in code 2026-11-21.** Format 2 exports/imports every namespace with TTLs and zset scores; allowlist rejects `customer:sessions:*`/`webhook:seen:*`/`webhook:inflight:*`; backups now carry `schema:version`, validated in pre-flight before any key is written; `script/restore-drill.sh` proved a round-trip on an isolated Redis. `no_ttl` flag not added (all exported keys carry their TTL). | P0-2/P0-3 | Engineering |
| D-retention | **RESOLVED 2026-11-21 — D-retention in `docs/DECISIONS.md`.** `Audit.record` stores a daily-rotating HMAC `ip_day` (12 hex chars) instead of a raw IP; abuse prevention stays in short-lived limiter keys; dropped writes are counted/alertable. | P0-4 | Security + ops |
| D-metrics | **RESOLVED in code 2026-11-21.** `/metrics` is a closed 404 unless `METRICS_ENABLED` and a configured `METRICS_TOKEN` are both present (constant-time `secure_compare`), uses its own `:metrics` limiter, and no longer emits the exact build version. Operators still set the token and restrict the scrape network on the server. | P0-1 (1.2) | Ops + security |

Record each in `docs/DECISIONS.md` with context → decision → consequences **before** code lands.

## 6. Operator actions (no agent execution)

1. **T-70:** terminate TLS on a real hostname; set `SSL=true`, `HOST`, `TRUST_PROXY=true`, `TRUSTED_PROXIES`. Gate: `HOST=https://… script/preflight.sh` exits 0.
2. **T-71:** apply the host firewall rule for the fixed Redis subnet. Gate: `script/tls-rehearsal.sh --with-redis` reports `PASS host cannot reach Redis at 10.77.13.2:6379` with 0 skips.
3. **K-46:** schedule `bin/ots webhooks:work` (cron/systemd) and restrict its egress. Gate: a queued event is delivered to a test receiver and the signature verifies. **Ownership:** the operator owns queue *liveness* — a one-shot delivery proof does not cover backlog growth; alert on `ZCARD webhook:queue` and delivery-age, and set a retention policy for `webhook:delivery:*` (no TTL today, `webhook.rb:32`).
4. **Human review:** approve edits to protected paths listed in step 4.3, P1-1/1.3, P1-3, **P2-3** (it changes `app.rb:769,774`), P2-2 and P2-4. The protected-path list from `AGENTS.md` also includes `auth/`, `payments/`, `secrets/`, credentials and any `*.pem`/`*.key`. Never auto-deploy, rotate `SECRET`, or restore into a live instance from an agent run.
5. **P2-3 (DECISION + APPROVAL)** — the previous status omitted approval for a protected-path edit; corrected here.

## 7. Acceptance gate (run on every milestone)

```bash
# Backend (Ruby is absent on the host; Redis DB 15 only — never FLUSHALL)
docker run --rm --network=host -v "$PWD":/app -v ots-bundle:/bundle \
  -e BUNDLE_PATH=/bundle -e REDIS_URL=redis://127.0.0.1:6398/15 -w /app \
  ots-dev bundle exec rspec

# Frontend
npm --prefix frontend run test
npm --prefix frontend run typecheck
npm --prefix frontend run build

# Packaging / clone gates
docker build -t ots-prod .
SECRET=$(openssl rand -hex 32) docker compose config --quiet
script/brand-sweep.sh
python3 ~/.agents/skills/replica-diff/parity.py replica/features.csv

# New-behavior evidence
# - every new spec was observed failing before the fix (red → green)
# - changed HTTP path exercised by curl or a committed e2e journey with output pasted
# - no secret material in code, logs, fixtures or docs
```

## 8. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Record-shape changes break the CAS or metadata MAC | Silent data loss or undecryptable records | expand→migrate→contract; P0-2/P0-3 first; dual verification for one release; red→green concurrency specs |
| Protected-path edits without approval | Process violation / unreviewed security changes | explicit approval gate per step; audit the diff before editing |
| Backup format v2 loses old dumps | Operator cannot recover | restore accepts v1; keep old binary and dump; dry-run on a copy |
| Webhook/backlog growth with no worker | Unbounded Redis growth, lost events | operator schedules K-46 before any new webhook event type; queue TTL decision in P0-2 |
| New previews reintroduce XSS | Credential theft | no `v-html`, strict CSP, sanitizer budget, filename validation already at `conceal_secret.rb:105-117` |
| Documentation drift recurs | False status claims | every change updates TASKS, FEATURE_MATRIX, API/DATABASE, CHANGELOG in the same commit; code + command output win |
| Ruby absent on host | Slow feedback | keep the Docker command in §7; CI mirrors it |

## 9. Status-of-record updates required in every change

`TASKS.md` (stable IDs, never renumber), `replica/features.csv` (`clone` column), `FEATURE_MATRIX.md` (status + priority), `API.md`/`DATABASE.md` (contracts and shapes), `SECURITY.md`/`SECURITY_AUDIT.md` (controls and residual risks), `CHANGELOG.md` (user-visible behavior), `ARCHITECTURE.md` (when boundaries change), and this plan (phase state). A feature moves to `yes`/`DONE` only with a passing spec **and** an executed command.

## 10. Deferred (explicitly not scheduled)

Organizations/RBAC/SSO/MFA/WebAuthn (D-003), custom domains and branding, billing, public SaaS and multi-region, client-side encryption or zero-knowledge claims (D-012), multiple storage backends, discussions/Markdown/JSON-LD compatibility, destruction email, view-count budgets, 27-locale i18n, and a product MCP server (unscheduled; D-011 only sketches what config it would need).

## 11. Product-engineering artifact

`docs/roadmap-posture.html` and its rendered `docs/roadmap-posture.png` are the `@stageshow` still for this plan: one cropped hero window listing the next increment with dependencies, one straddling evidence-gate card (180 specs/0 failures, 11/11 must-haves, five journeys). Rendered at 1030×560 with zero page errors; every real word measured inside the crop. No competitor UI was reproduced.

## 12. Landed 2026-11-21 (evidence, not inspection)

Five parallel specialist reviews (database/storage, API, business logic,
validation/error/logging, backend testing) confirmed that the lifecycle, auth, APIs and
consumption primitive are implemented and tested; they converged on the following genuinely
missing items from this plan. Each was written red before the fix and verified by command.

| Step | Result | Evidence |
|---|---|---|
| P0-3 (3.1, 3.2) | DONE | `lib/onetime/migrate.rb`, `bin/ots migrate [--dry-run]`, `spec/unit/migration_spec.rb` — 6 examples red (`NameError`) → green; live CLI on DB 14: dry-run left marker absent, apply → `1`, re-apply → "nothing applied" |
| P0-4.1 (SA-06) | DONE | `lib/onetime/logic/reveal_secret.rb` wraps post-consume cleanup; red spec saw `503` after consume → now `200` with plaintext; counter `operation="cleanup"` |
| P0-4.2 (SA-16) | DONE | `lib/onetime/audit.rb` logs `request_id`/`actor_id` on drop and increments `operation="audit"`; red spec lacked both → green |
| P0-5 (5.1, 5.2) | DONE | `models/secret.rb#verify_meta!` rejects `v != 2`/missing MAC; downgraded passphrase-stripped record `200` → `500`, record intact. The request-object half (5.3) is present too: `models/secret_request.rb` reuses the same primitive and both submit/reveal verify before trusting `owner_id`; `requests_spec` tamper example green |
| P0-1 (1.1–1.4, F1–F4) | DONE | `openapi.rb`: v1 errors → `LegacyError` (required `message`), missing 413/422/401, v1 form body, 3.1 null type; `openapi_spec.rb`: 4 → 11 examples incl. catch-all-body mount gate and bogus-path negative control. Seven contract specs red → green; live v1 429/503 bodies are `{"message":...}` only |

**Already present in the working tree (verified, not written in this increment):** P0-2
backup format 2 covers `request:object:*`, `request:secret:*`, `webhook:endpoint:*`,
`webhook:owner:*`, `webhook:queue`, `webhook:delivery:*` with TTLs, v1 dumps still restore,
and `customer:sessions:*` is denied (`spec/unit/ops_spec.rb`, 19 examples). SA-22 is closed
by that work. Request-object MAC (P0-5 5.3) is also present and covered.

**Verification command:** `/tmp/opencode/run-rspec.sh` (the documented Docker command plus a
stale-container cleanup, because a lingering rspec container trips the DB-15 single-client
guard on this host) → **230 examples, 0 failures**, seed 18297.

The `@stageshow` coordination still for this increment is `docs/backend-gates-posture.html`
and its `docs/backend-gates-posture.png`: one cropped reveal window and one straddling
evidence card naming the four gates. Rendered at 1030×560 with zero page errors.

**Also landed 2026-11-21 after explicit operator approval (D-017):** owner burn and the
D-receipt lifecycle (8 new red→green examples in `spec/integration/receipt_lifecycle_spec.rb`),
B8 endpoint-scoped webhook deliveries (`spec/integration/webhooks_spec.rb`), the dedicated
`RATE_LIMIT_BURN` scope (a red spec caught `Config.rate_limit` falling back to the reveal
budget), and updates to three older specs that asserted the *deleted-receipt* contract.
`owner_index` retention, `secret.burned` audit event, OpenAPI burn path and receipt `status`
are part of the same change.

**Still not changed at that point:** the per-secret passphrase budget (D-012b), a separate
receipt-token API (no decision), and all operator actions. D-012b is now closed in §13.

## 13. Pre-launch remediation increment (2026-11-21, ₹0 budget)

Driven by the `GO_LIVE_REMINDER.md` reconciliation. No commit, push, deploy, or production
restore. Evidence in `SECURITY_AUDIT.md` §14 and `RELEASE_CHECKLIST.md`.

| Item | Outcome | Verification |
| --- | --- | --- |
| D-012b per-secret passphrase budget | **FIXED AND VERIFIED** — `passphrase` limiter scope keyed by opaque secret id, 5 guesses / 900 s dedicated window, protected records only, exhaustion `429` with record intact; decision recorded | red→green spec in `secrets_api_spec.rb`, `Config` validation |
| D-retention audit IPs | **FIXED AND VERIFIED** — daily-rotating HMAC `ip_day`, no raw IP; decision recorded | `audit.rb`, `ops_spec` |
| Backup schema versioning | **FIXED AND VERIFIED** — `schema_version` exported and pre-flight validated before any write; marker stamped last; included in overwrite check | `backup.rb`, `ops_spec` round-trip + corrupt-marker specs |
| Backup/restore round-trip drill | **FIXED AND VERIFIED** — `script/restore-drill.sh` on a throwaway Redis container | `RESTORE DRILL PASSED`, spent record stays gone, schema=1, no pending migration |
| `/metrics` secure access | **FIXED AND VERIFIED** — required bearer token, dedicated rate scope, no version label | integration + unit metrics specs |
| Webhook worker scheduling | wrapper + units **FIXED AND VERIFIED**; **REQUIRES SERVER OPERATOR** to install/monitor | `script/webhook-worker.sh`, `docs/ops/webhook-worker.md`, `bash -n` |
| Protected paths (`crypto.rb`, `app.rb`, `compose.yaml`) | **REQUIRES HUMAN APPROVAL** — diffs re-read, no regression found; sign-off outstanding | `GO_LIVE_REMINDER.md` review table, `SECURITY_AUDIT.md` §14.5 |
| T-70 / T-71 / K-46 on target | **REQUIRES SERVER OPERATOR** | target-host prefirest evidence |
| Public launch / live restore / real TLS claim | **BLOCKED** | NO-GO; no host access |

Final gate: **261 examples, 0 failures** (single clean run, seed 35351). Launch verdict remains **NO-GO** while
mandatory operator and human gates are open.
