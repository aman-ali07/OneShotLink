# OneShotLink — competitor-backed feature matrix and implementation priorities

**Date:** 2026-11-21
**Purpose:** compare the verified competitor research in [COMPETITOR_RESEARCH.md](COMPETITOR_RESEARCH.md) against the **current working tree** of OneShotLink, and rank what to build next. This replaces the earlier clean-room clone matrix; competitor claims are carried over only where that report marks them VERIFIED.

## 1. Evidence standard

- Every status below is backed by a repository path (with line numbers), a committed spec/E2E journey, or a command output. No status rests on a document's self-description alone.
- Five parallel area auditors (frontend, backend, security, APIs, user workflows) inspected the code read-only, grounded in the repository's `.claude/agents/` reviewer personas. Their claims were cross-checked against source before being recorded here.
- **Status legend**
  - **IMPLEMENTED** — code path exists and is exercised by a spec, E2E journey, or a command run in this pass.
  - **PARTIAL** — a narrower form exists; the competitor's full capability does not.
  - **MISSING** — no code path found for the capability as described.
  - **BROKEN** — a code path exists but a concrete defect was demonstrated; each such item appears in §4 with evidence and disposition.
  - **OPPORTUNITY** — no competitor-parity claim; a differentiated opportunity justified by cited evidence.
- **Priority legend**: P0 = do next (security or high user value, low dependency), P1 = next cycle, P2 = later, **DEFER** = deliberate out-of-scope decision.
- **Scoring**: Value (1–5 user impact), Sec (1–5 risk reduction), Complexity (S/M/L), Deps (None/Low/Med/High). Priority is a judgement from these four, not a formula.

## 2. Verified baseline of the current tree

| Evidence | Result |
|---|---|
| `git log -1 --oneline` | `741e71f Ship signed, idempotent webhooks end to end (T-118)` — historical baseline of this matrix |
| Working tree vs HEAD | Point-in-time snapshot: **47 files changed, 1636 insertions(+), 585 deletions(-)** (hardening + research + this matrix). Statuses below describe that working tree, not HEAD; the final release tree is larger and uncommitted. |
| Final release gates | **307 backend examples / 35 Vitest tests / 8 browser journeys / 0 a11y violations** — `RELEASE_CHECKLIST.md` and `TESTING.md` are authoritative for current counts; older counts in this matrix are snapshots. |
| Backend suite | `docker run --rm --network=host -v "$PWD":/app -v ots-bundle:/bundle -e BUNDLE_PATH=/bundle -e REDIS_URL=redis://127.0.0.1:6400/15 -w /app ots-dev bundle exec rspec` → **285 examples, 0 failures** (current tree; see `TESTING.md` §1 for the canonical command and Redis DB 15) |
| Frontend gates | `npm --prefix frontend run test` → 28 passed; `vue-tsc --noEmit` clean; `npm --prefix frontend run build` → built (239.75 kB JS / 22.77 kB CSS) |
| Hardening specs observed | `spec/integration/edge_hardening_spec.rb`, `hardening_spec.rb`, `security_hardening_spec.rb` cover rate-limit scopes, header propagation on assets, media-type strictness, metadata MAC and HEAD 405 |
| Protected-path fixes present | `script/preflight_selftest.sh` uses `PF_COMPOSE_PROJECT` (default `otspreflight-selftest`) and refuses the production project; `models/session.rb` has `TOUCH_SCRIPT` sliding the revocation index; `web/app.rb` has per-scope `enforce_rate_limit!` calls |
| One defect fixed during this audit | `e2e/requests.mjs` no longer prints the submitted answer to stdout (see §4); the fix is an uncommitted working-tree change (HEAD `741e71f` still logged `secret`) |
| Independent verification | Five parallel `.claude/`-persona area auditors re-read this matrix against source this pass; no status was refuted, but B1 was narrowed and several citations/lines were corrected (§4.2) |

## 3. Feature matrix

Competitor column abbreviates sources from `COMPETITOR_RESEARCH.md` (§3 matrix, §4 per-product evidence, §6 opportunities). "Evidence" is the OneShotLink file/line or committed test.

### 3.1 Product & UX (frontend)

| Capability | Competitor evidence | Status | OneShotLink evidence | Notes |
|---|---|---|---|---|
| Branded custom domain / per-domain theming | Onetime paid branding but "workspace branding … Not available yet" (§4.1); Yopass branding in €149/yr licence (§4.2); Password Pusher branding/custom domain from Solo (§4.4) | **MISSING** | Brand hardcoded `AppHeader.vue:27`, `AppFooter.vue:5`, `frontend/index.html:8,10`; global tokens `assets/styles.css:2`; `TASKS.md:163` T-61 deferred | `site/index.html:80` shows `app.your-domain.example` only in a decorative mockup, not a feature. Rebrand gate applies. |
| Premium, distinctive frontend | Polished SaaS competitors (§3) | **IMPLEMENTED** | redesigned views/components; `DESIGN_SYSTEM.md`; 12 Vitest pass, typecheck/build clean (§2) | Original UI not copied. |
| Responsive + AA accessibility | Competitors yes/partial (older matrix) | **IMPLEMENTED** (code + automated axe evidence) | skip link + `tabindex="-1"` `App.vue:8-15`, per-route titles `router.ts`, focus recovery on gone/sent/taken/revealed, 44px targets, `role=alert/status`; `e2e/a11y.mjs` → 11 states, 0 WCAG 2.2 AA violations; 320px overflow verified false in Chrome | Real screen-reader output and 400% zoom remain manually unverified; automated gate is non-vacuous (negative control reports `image-alt`). |
| No browser storage of secrets | Yopass admits `localStorage` private keys/tokens (§4.2); opportunity §6.2 | **IMPLEMENTED** | grep `localStorage|sessionStorage|indexedDB` in `frontend/src` and shipped bundle → zero matches; state cleared `ConcealView.vue:131-134`, `RevealView.vue:43`; E2E asserts `"{}"` in `journey.mjs:52,146`, `accounts.mjs:84-85`, `requests.mjs:74-75`, `webhooks.mjs:55-56` | Strongest-evidenced capability. |
| Confirmation-before-reveal / link-scanner protection | Onetime confirm page (§4.1); PrivateBin `#-` (§4.5); Password Pusher retrieval step (§4.4) | **IMPLEMENTED** | `RevealView.vue:12` default `idle`, `:32` no auto-reveal, `:183-231` interstitial, POST-only consume `api.ts:181-188`; `app.rb:298-314` GET = metadata; `e2e/journey.mjs:54-63` | No `#-` trick needed because GET never consumes. Frozen v1 GET still consumes (`API.md` §4). |
| Passphrase/access-gate UI + 8-byte floor | Onetime access-check passphrase (§4.1); Bitwarden password "not used for encryption" (§4.6) | **IMPLEMENTED** | `ConcealView.vue:117-120,260-278,312-318`; `RevealView.vue:47-55,228`; `e2e/journey.mjs:65-88,90-155`; unit `api.test.ts:96-112` | Three layers: HTML `minlength`, JS byte check, backend 422. Access gate, not a second key (D-012). |
| Inbound request links UI | Yopass licensed request flow (§4.2); Password Pusher mature requests (§4.4) | **IMPLEMENTED** (narrow) | route `router.ts:18`; `RequestView.vue:1-146`; `DashboardView.vue:321-393`; `api.ts:190-224`; `e2e/requests.mjs:33-77` | Text answers only; no passphrase/fingerprint. |
| Files / attachments with previews | PrivateBin multi-attachment + image/PDF preview (§4.5); Password Pusher 4 GB tested (§4.4) | **PARTIAL** | single file `ConcealView.vue:14-16,59-84,67-71`; download-only `RevealView.vue:83-106,148-163`; `e2e/file.mjs:29-80`; 512 KiB decoded cap `conceal_secret.rb:14-18` | No multi-file, no preview. ~1/8000 of Password Pusher's tested size. |
| QR code / "save document" / raw text / email share | PrivateBin result actions (§4.5) | **PARTIAL** | copy link `ConcealView.vue:342-345`, `CopyButton.vue:1-61`; raw `<pre>` `RevealView.vue:165`; file save `:93-106,161`; no QR dep (`frontend/package.json:13-17`), no `mailto:` | QR is pure frontend (no backend change). |
| Password generator | Password Pusher passphrase/password/PIN generator + `/api/v2/generate` (§4.4) | **MISSING** | `ConcealView.vue:204-217` plain textarea; no `generate` in `api.ts`; no endpoint in `openapi.rb` | Pure-frontend candidate via Web Crypto; no new dep. |
| Markdown / source-code formatting | PrivateBin format selector (§4.5) | **MISSING** | `ConcealView.vue:204-243` only textarea/file; `<pre>` at `RevealView.vue:165`; no format field in `api.ts` | New npm dep would need `docs/DECISIONS.md` entry (AGENTS rule 8). |
| Password strength meter | Privnote strength meter (§4.3) | **MISSING** | `ConcealView.vue:260-278` only `minlength`/`maxlength`; no `strength` match in `frontend/src` | Copy must not imply E2EE. |
| In-app notification / read receipt status | Privnote destruction email, Yopass paid read receipts, Onetime New/Previewed/Revealed (§4.1–4.3) | **PARTIAL** | webhook UI + `secret.revealed` event `DashboardView.vue:26-32,395-463`; receipts list `:283-319` shows metadata only; no toast/poll (`grep notification|toast` → none) | Webhooks are external, metadata-only, need operator worker. No status transitions. |
| 30+ locales / i18n | PrivateBin ~36, Password Pusher 30–31, Onetime 12+/14 (§4.1/4.4/4.5) | **MISSING** | `TASKS.md` T-64; no i18n dependency (unused `i18n`/`semantic_logger` gems were removed); `frontend/index.html:2 lang="en"`; copy hardcoded e.g. `ConcealView.vue:166-172` | No locale switch, no RTL. |
| Account dashboard / receipts / webhooks UI | Password Pusher/Bitwarden accounts; Onetime orgs (§4.1/4.4/4.6) | **IMPLEMENTED** | `router.ts:15-17`; `DashboardView.vue:256-526`; `api.ts:226-290`; `e2e/accounts.mjs:40-115`, `e2e/webhooks.mjs:23-57` | Simple mode only; SSO/MFA deferred. |

### 3.2 Backend, data & operations

| Capability | Competitor evidence | Status | OneShotLink evidence | Notes |
|---|---|---|---|---|
| Atomic single-use reveal | Yopass WATCH/MULTI/EXEC, PWP `with_lock`, PrivateBin GET-then-delete (§3) | **IMPLEMENTED** | `store.rb:49-63` GET/compare/DEL with non-empty guard; `models/secret.rb:98-100`; `reveal_secret.rb:39`; `secrets_api_spec.rb:134-147` (8 threads → one 200) | Lua comparison unconditional (SA-20 fixed). v1 GET consumes by frozen contract. |
| Verify/decrypt **before** consume | PrivateBin burns before client decrypt; Yopass GHSA admits stalled decrypt still consumes (§4.5/§4.2, opportunity §6.1) | **IMPLEMENTED** | `reveal_secret.rb:27-43` verify_meta → verify_passphrase → decrypt → consume; `models/secret.rb:78-94` v2 MAC; `secrets_api_spec.rb:113-131,189-206`; `security_hardening_spec.rb:32-79` | Holds for request submissions `secret_requests.rb:99-100`. Strongest verifiable differentiator. |
| Configurable TTL allowlist | Onetime 7/14/30 d, Yopass 1h–90d, PWP 1–90 d + 1–100 views, PrivateBin 5min–3d/`never` (§3) | **IMPLEMENTED** (narrower) | `config.rb:18` TTL options 30m/12h/1d/3d, boot check `:60-65`; `conceal_secret.rb:73-85`; `app.rb:137-147` | Env-configurable but no default >3 days. |
| View-count / multi-view budget | PWP 7d/5 views default, 1–100 configurable, `claim_view!` (§4.4) | **MISSING** | no budget field `models/secret.rb:44-54`; receipt `"viewed" => "0"` deleted on reveal; repo grep finds those tokens only in docs (`COMPETITOR_RESEARCH.md`, `ARCHITECTURE.md`), never in `lib/` code | Strictly one-time; adding budget changes encrypted record shape and Lua script. |
| Scheduled purge jobs | PWP `CleanUpPushesJob`/`PurgeExpiredPushesJob` (§4.4) | **MISSING** (by design); webhook worker **PARTIAL** | `ARCHITECTURE.md:70` "no in-process scheduler … Redis TTL handles expiry"; `DATABASE.md:161` "no sweeper in v1"; `models/secret.rb:109,119`; external `bin/ots:136-144` webhook worker (K-46) | Owner indexes pruned lazily `app.rb:487-506`. An older citation to `ARCHITECTURE.md:30` was stale (that line is now a P0 work item). |
| Multiple storage backends | PrivateBin files/PDO/S3/GCS; PWP SQLite/PostgreSQL; Yopass Redis/Memcached/S3 (§3) | **MISSING** (deliberate) | `store.rb:13-22` single `Redis.new`; `config.rb:149-178`; `AGENTS.md` forbids ORM/second framework | Architecture decision, not oversight. |
| Inbound secret requests | Yopass keypair + fingerprint; PWP file responses; Onetime incoming secrets (§4.1/4.2/4.4) | **PARTIAL** | `secret_request.rb:12-76` SET NX + CAS; `secret_requests.rb:5-115`; `app.rb:750-792`; `requests_spec.rb:31-98` | Text-only, no passphrase/fingerprint, and preview/respond are public capability links in default `AUTH_MODE=disabled` (C2). |
| File secrets | Yopass ≤1 MB free, PrivateBin 10 MiB, PWP 4 GB tested (§3) | **PARTIAL** | `conceal_secret.rb:17,119-128` 512 KiB decoded cap; `app.rb:143-145`; `secrets_api_spec.rb:208-273`; `e2e/file.mjs` | Base64-in-JSON, not multipart; the coupling is `MAX_FILE_BYTES` ↔ `MAX_SECRET_BYTES` (base64 expands ~4/3) — the body ceiling at `app.rb:245` already derives from `MAX_SECRET_BYTES`. |
| Backup/restore completeness | (internal ops; competitors export whole stores) | **PARTIAL** | `backup.rb:18-25` exports only secret/receipt/customer; `restorable_prefixes` `:102-104`; guard `:47-57` + 0600 `:27-34`; `ops_spec.rb:96-188` | Request and webhook namespaces were added in T-106; restore now validates entries before any write (SA-42). |
| Key rotation across encrypted shapes | PWP `PWP_MASTER_KEY_PREVIOUS` (§4.4) | **IMPLEMENTED** | `rotate_key.rb:5-22` walks 3 shapes; `:34-86` CAS re-encrypt; `store.rb:65-95` string + hash-field CAS; `ops_spec.rb:28-93`; `security_hardening_spec.rb:65-79` | Race fixed (K-42): consumed record is skipped, not resurrected. |
| Full auth mode / SSO | Onetime `full`, Yopass OIDC paid, PWP OIDC Organization (§3) | **MISSING** (fails closed 501) | `config.rb:16,74,99-112`; `errors.rb:76-80` NotConfigured 501; `app.rb:430-435,476-481`; `secrets_api_spec.rb:455-461`; `TASKS.md:162` T-60 deferred | No Postgres/RabbitMQ. Never silently downgrades. |
| Self-hosting simplicity | Yopass single Rust binary, PrivateBin PHP, Onetime `simple`=Valkey (§3) | **PARTIAL** | `Dockerfile` 3-stage Node→gems→Ruby; `compose.yaml` web+Redis; `config.ru:8-14`; webhook worker external | Redis-only datastore, but toolchain + TLS proxy (T-70) + firewall (T-71) are heavier. |
| License + code-grounded docs | Apache-2.0/zlib/GPLv3 competitors (older matrix) | **IMPLEMENTED** | `LICENSE` MIT; `SECURITY_AUDIT.md`; `docs/CRYPTO_SPEC.md`; `docs/SDK.md`; `/api/v3/openapi.json` | Copy rules honoured; no zero-knowledge claim. |

### 3.3 Security & trust

| Capability | Competitor evidence | Status | OneShotLink evidence | Notes |
|---|---|---|---|---|
| Client-side encryption / "server cannot decrypt" | Yopass OpenPGP in browser, PrivateBin AES-GCM in browser, Bitwarden fragment key (§4.2/4.5/4.6) | **MISSING** (deliberate, D-012) | `crypto.rb:24-64` decrypt uses `Config.secret!`; `docs/DECISIONS.md:165-184`; `SECURITY_AUDIT.md:160-172` | **Never** claim zero-knowledge / "server cannot decrypt". |
| Passphrase as access gate | Bitwarden source comment "passwordKey is not used for encryption" (§4.6); Onetime docs self-contradict (§4.1) | **IMPLEMENTED** | `models/secret.rb:53` Argon2id hash; `reveal_secret.rb:66-74`; `password.rb:17-32`; `SECURITY.md:67-69` | Matches Bitwarden, not Onetime's contradictory copy. |
| Key in URL fragment vs opaque server ID | Yopass/PrivateBin/Bitwarden fragment keys (§4.2/4.5/4.6) | **IMPLEMENTED** (opaque server ID) | `ids.rb:12-14` 128-bit CSPRNG; `models/secret.rb:26-28`; `SECURITY.md:19` | No browser-held key; link interception + leaked SECRET = compromise (accepted). |
| Rate limiting | Yopass excludes it from bug scope; PWP 30/min generator + 15/min audit; Onetime paid removes limits (§4.1/4.2/4.4) | **IMPLEMENTED** (stronger than Yopass) | `config.rb` 16 validated scopes; `limiter.rb:14-47` Lua; `app.rb:204-224,519,560,725,797,841` | `/metrics`, config/meta and webhook deliveries are now scoped; rejected requests count (K-15). |
| Per-secret passphrase attempt budget | PWP 5/min **per push** (§4.4) | **IMPLEMENTED** | `reveal_secret.rb#check_passphrase_budget!`, `config.rb` (`RATE_LIMIT_PASSPHRASE=5`, window 900 s), D-012b | Keyed by opaque secret id; wrong guesses never consume. |
| Signed, idempotent webhooks | Yopass paid, PWP Team+ (§3) | **PARTIAL** | pin stored `webhook.rb:59,72` and enforced `:216-236,271-295`; seen-after-POST + inflight + retries `:147-191`; HMAC `:161-170`; `bin/ots:136,241-242`; K-46 | Controls implemented; **no worker in web process** — operator must schedule. |
| Read receipts / destruction notification | Privnote email, Yopass paid receipts, PWP full audit with IP/UA/referrer (§4.2–4.4) | **PARTIAL** | receipts `models/secret.rb:102-121`; `app.rb:487-506`; `audit.rb:16-33`; `reveal_secret.rb:42-43` webhook; `PRODUCTION_READINESS.md:92` no email | No email subsystem. Audit stream stores a daily-rotating HMAC reference, never a raw IP; request logs do not store IPs. |
| IP allowlisting / SSO / RBAC / policy | Onetime "Not available yet" + SAML 2026-10; Yopass OIDC paid; PWP OIDC/RBAC paid (§4.1/4.2/4.4) | **PARTIAL (field) / MISSING (enforcement)** | `models/customer.rb:18-27,44-55,88-100` inert `role`; `bin/ots:99,192,230` set-role; no `require_role!` or admin route in `app.rb`; `TASKS.md:162` | No IP allowlist, SSO, MFA, or RBAC checks. |
| Security documentation maturity | Yopass threat model, PrivateBin README limits, PWP audits claim (§4.2/4.4/4.5) | **IMPLEMENTED** | `SECURITY_AUDIT.md:1-286` (method, threat model, E2EE statement); `SECURITY.md`; `docs/CRYPTO_SPEC.md` | Observed-vs-claimed separated. Doc spec counts still drift (SA-19). |
| TLS / custom-domain automation | Research verifies only "proxy in front assumed" for Onetime (§4.1) — automatic certs **not verified** | **PARTIAL** | `app.rb:567` HSTS, `:405-414` cookie flags; `compose.yaml:80` loopback; `script/tls-rehearsal.sh`; `PRODUCTION_READINESS.md:79-80` | T-70/T-71 operator-owned. Do not call "production ready" publicly. |
| Supply-chain / signed releases | Signed tags + SLSA / checksum + attestation were **not** in the research doc — unverified competitor claims | **PARTIAL** | `ci.yml:15-36` bundler-audit + npm audit + pinned SHAs; `TASKS.md:67` T-101 | No signed tags, SLSA provenance, or release attestation. |
| Failed reveal must not burn the secret | PrivateBin/Yopass burn-before-decrypt (§4.2/4.5, opportunity §6.1) | **IMPLEMENTED** | `reveal_secret.rb:22-41` verify→decrypt→consume; `head_requests.rb:22-26`; `app.rb:298-314`; `store.rb:49-63` | v1 GET still consumes by contract. |

### 3.4 API & developer experience

| Capability | Competitor evidence | Status | OneShotLink evidence | Notes |
|---|---|---|---|---|
| Stable versioned JSON API | Onetime v2 stable / v1 legacy / v3 preview (§3) | **PARTIAL** | v1 `app.rb:607-628`; v3 `app.rb:630-892`; no v2 (`API.md:335-346`); `secrets_api_spec.rb:32-95,277-301` | v1 + v3 implemented; no current "stable" version parity. |
| OpenAPI contract + generated types | Onetime OpenAPI v2, Yopass openapi.yaml (§3) | **PARTIAL — BROKEN details in §4** | `/api/v3/openapi.json` `app.rb:641-644`, `openapi.rb:14-35`; gate `openapi_spec.rb:10-44`; no generated types (`*types*.ts\|*.d.ts` → none); `docs/SDK.md:3` | Contract hand-maintained; 4 concrete drift findings in §4. |
| Bearer / API-token auth | Onetime Basic+token, PWP Bearer (§4.4) | **MISSING** | only cookie `ots_session` `app.rb:18,389-414`; CSRF `:437-474`; OpenAPI only `cookie` scheme `openapi.rb:412-414`; no token route found | Secret/request keys are bearer *capabilities*, not API credentials. Headless clients limited to guest routes. |
| Public unauthenticated create/reveal + limits | Onetime anon 7d/100KB (§4.1) | **IMPLEMENTED** | guest routes `app.rb:832-857`; limits `config.rb:21-22`; `secrets_api_spec.rb:32-95,393-419` | GET preview non-consuming; POST is only spend path. |
| Pagination / list endpoints | PWP `/active`,`/expired` 50/page (§4.4) | **PARTIAL** | receipts newest 50 `app.rb:487-506`; webhooks 50 `webhook.rb:86-99`; requests list `:334-336` | Fixed slices, no `page`/`per_page`; no secret list by design. |
| Rate-limit headers / 429 / Retry-After | PWP 429 + Retry-After (§4.4) | **IMPLEMENTED** | 9 scopes `config.rb:21-30`; `app.rb:204-239,907-944`; OpenAPI header schema `openapi.rb:397-408`; `secrets_api_spec.rb:393-419` | Routes without `enforce_rate_limit!` send no `X-RateLimit-*`. |
| Inbound request API | PWP `/api/v2/requests/:token/respond`, Yopass `/request/*` (§4.2/4.4) | **IMPLEMENTED** (caveat) | `app.rb:752-792`, helpers `:319-366`; `API.md:262-282`; `requests_spec.rb:30-99` | "Public" preview/respond call `require_accounts!` (`app.rb:769,774`) → 403 in default `disabled` mode. |
| Outbound webhooks | Yopass paid, PWP Team+ (§3) | **IMPLEMENTED** (ops caveat) | `webhook.rb:18-305`; routes `app.rb:794-830`; worker `bin/ots:136-144`; `webhooks_spec.rb:19-58` | At-least-once, metadata-only; operator schedules worker (K-46). |
| SDK guide + runnable examples | Competitor docs/CLI | **IMPLEMENTED** | `docs/SDK.md:1-276`; `examples/{curl,typescript,python}/quickstart.*` | No SDK package claimed. |
| CLI | Yopass Rust CLI with attestation, PWP CLI (§3) | **PARTIAL** | `bin/ots:183-247` operator commands only — no conceal/reveal, no attestation | See §3.5 workflow #14. |
| MCP / `llms.txt` discovery | Onetime `llms.txt` verified; `/mcp` only in the task brief, **not** in research | **MISSING** | no `llms.txt`; no MCP route; `docs/DECISIONS.md:160-163` explicitly no MCP server | Do not claim `/mcp` as verified competitor fact. |
| Typed errors / uniform 404 | implied across competitors | **IMPLEMENTED** | `errors.rb:3-90`; `app.rb:72-74,907-944,508-516`; `secrets_api_spec.rb:52-53,91,125` | v1 keeps legacy `{"message":...}` envelope. |
| JSON-LD + 13 community clients | PrivateBin (§4.5, §6) | **MISSING / infeasible** | JSON/OpenAPI only; server holds key; `COMPETITOR_RESEARCH.md:126` says full client compat needs browser-side encryption | Do not claim compatibility. |

### 3.5 End-to-end workflows (committed journey evidence)

| # | Workflow | Competitor(s) | Status | OneShotLink evidence | Notes |
|---|---|---|---|---|---|
| 1 | Anonymous create → link → reveal once → gone | all six | **IMPLEMENTED** | `e2e/journey.mjs:45-63`; `secrets_api_spec.rb:73,134`; `app.rb:832-857` | File variant `e2e/file.mjs`. v1 is spec-only. |
| 2 | Confirmation before reveal (scanner safe) | Onetime, PrivateBin, PWP | **IMPLEMENTED** | `RevealView.vue:9,32,183-231`; `api.ts:181-188`; `app.rb:294-314`; `e2e/journey.mjs:54-57` | Protection from POST-only consumption, not a distinct confirm URL. No scanner-simulation journey. |
| 3 | Passphrase out-of-band, wrong attempt doesn't consume | all six | **IMPLEMENTED** | `ConcealView.vue:19,260-278`; `RevealView.vue:47-55`; `reveal_secret.rb:66-74`; `e2e/journey.mjs:65-88` | Delivery is manual; no email/SMS. |
| 4 | Secret + receipt link, New/Previewed/Revealed, owner burn | Onetime | **IMPLEMENTED** (no second token by D-017) | `models/secret.rb` statuses + 30-day retention; `app.rb` burn route with CSRF/session/rate limit; `DashboardView.vue` status + Destroy control; `e2e/states.mjs` burn→destroyed; `spec/integration/receipt_lifecycle_spec.rb` | The opaque secret key is the capability by decision D-017; no separate receipt-token API. |
| 5 | Destruction notification email | Privnote, Yopass | **MISSING** | no mail gem in `Gemfile`; `lib/` "email" = account id only; `KNOWN_ISSUES.md:76` | No code, route, config, or journey. |
| 6 | Inbound request → responder → owner reveal | Yopass, PWP, Onetime | **IMPLEMENTED** (scoped) | `e2e/requests.mjs:33-76`; `requests_spec.rb:31-59`; `API.md:262-282` | Requires `AUTH_MODE=simple`; text-only answers. |
| 7 | File create → download | Yopass, PrivateBin, PWP, Bitwarden | **IMPLEMENTED** (scoped) | `e2e/file.mjs:29-80` (byte-for-byte + replay 404); `e2e/journey.mjs:112-160`; `secrets_api_spec.rb:207-275` | 512 KiB, base64, server-side encryption. |
| 8 | Signup → dashboard → signout → signin → delete | PWP/Bitwarden/Onetime | **IMPLEMENTED** | `e2e/accounts.mjs:40-115`; `accounts_spec.rb:45-463` | Simple mode; no orgs. |
| 9 | Webhook create → event → delivery → signature verify | Yopass paid, PWP Team+ | **PARTIAL** | create/list only `e2e/webhooks.mjs:23-57`; delivery/HMAC/retry unit-tested `webhook_spec.rb:126-207`; worker `bin/ots` | No single committed journey through the full chain; operator worker required. |
| 10 | Multi-view / timed multi-read note | Privnote timed, PWP view budget, Bitwarden max access | **MISSING** | single consume `reveal_secret.rb:39`; no view budget field | Deliberate one-time invariant. |
| 11 | Discussions / comments on a paste | PrivateBin | **MISSING** | no route in `app.rb:565-905`, no view in `router.ts`, no discussion field in `api.ts` | Out of scope; conflicts with one-time delete. |
| 12 | Password generator | PWP | **MISSING** | `ConcealView.vue:204-217` plain textarea | Pure-frontend opportunity. |
| 13 | QR / email share of link | PrivateBin, PWP | **MISSING** | `ConcealView.vue:342-345` copy only | Pure-frontend opportunity. |
| 14 | CLI create/reveal | Yopass, PWP | **MISSING** | `bin/ots:183-207,222-247` operator commands only; HTTP equivalents in `examples/` | PRD developer persona served only by examples. |

### 3.6 New competitive opportunities (not parity requirements)

These are differentiated plays, not "competitor has it so we must". Each cites both a verified competitor observation and a local gap/status.

| Opportunity | Evidence | Local gap/status | Priority |
|---|---|---|---|
| Market "a failed reveal never burns the secret" as a verifiable promise | PrivateBin deletes burn pastes at `GET` before decryption (COMPETITOR_RESEARCH.md §4.5); Yopass GHSA admits stalled decryption still consumes (§4.2) | Already implemented — `reveal_secret.rb:31-39`; turn it into user-visible copy and a journey | P0 (copy/journey) |
| Owner receipt lifecycle: separate receipt token, New/Previewed/Revealed status, owner burn | Onetime two-token flow (COMPETITOR_RESEARCH.md §4.1) | PARTIAL — receipt id == secret key, no status/burn (`conceal_secret.rb:51-60`, `app.rb:487-506`, §3.5 #4) | P1 (#4) |
| Per-secret passphrase attempt budget | Password Pusher 5/min per push (COMPETITOR_RESEARCH.md §4.4) | **IMPLEMENTED** — `reveal_secret.rb:83-103` (D-012b: 5/900 s keyed by opaque id) | P1 (#5) |
| `ots conceal` / `ots reveal` CLI for the developer persona | Yopass CLI; Password Pusher API-first workflow (§4.2/§4.4) | MISSING — `bin/ots:183-247` is operator-only (§3.5 #14) | P1 (#6) |
| Agent discovery: `/llms.txt` + generated TS/Python types from OpenAPI | Onetime publishes `llms.txt`, Yopass OpenAPI (COMPETITOR_RESEARCH.md §4.1, §4.2) | MISSING — no `llms.txt`, no generated types (§3.4) | P2 (#12) |
| Pure-frontend convenience: password generator, QR / `mailto:` share | Password Pusher generator + API (COMPETITOR_RESEARCH.md §4.4); PrivateBin QR/email actions (§4.5) | MISSING — `ConcealView.vue:204-217,342-345` (§3.1/§3.5 #12–13) | P2 (#8) |

Do **not** turn client-side encryption, custom domains, i18n, view budgets or SSO into near-term opportunities: each reverses a documented decision or needs infrastructure/product sign-off (§5 DEFER rows).

## 4. Broken functionality (with evidence and disposition)

| ID | Defect | Evidence | Disposition |
|---|---|---|---|
| **B1** | OpenAPI documents wrong v1 error schemas for **503 on all v1 paths and 429 on `/api/v1/share`** | `rate_limited(version:)` now selects `LegacyError` for v1; all v1 401/404/413/422/429/503 responses ref `LegacyError`, which now requires `message`. Live v1 429 and 503 bodies asserted to contain only `message` | **Resolved 2026-11-21** — seven red→green OpenAPI contract specs; full suite 203/0 |
| **B2** | `/metrics` is mounted and tested but absent from the OpenAPI document | `openapi.rb` now documents `/metrics` with a `text/plain` 200 response and 404; `openapi_spec.rb` asserts the path | **Resolved** — verified in the served document |
| **B3** | The "documented paths are mounted" gate cannot detect drift | `openapi_spec.rb#assert_mounted` now detects the generic catch-all envelope by `code`/`message` (not a 404 status, so domain 404s still pass) and a **negative control** injects a bogus path and proves the gate fails | **Resolved** — negative control was red before the fix, now green. Reverse mounted-vs-documented registry is still deliberately not duplicated across files |
| **B4** | v1 request body under-documented | `op(form_body:)` adds `application/x-www-form-urlencoded` alongside JSON for v1 share; 413/422 documented | **Resolved** — asserted by the contract spec |
| **B5** | E2E journey printed the submitted answer to stdout | HEAD `741e71f` had `e2e/requests.mjs:77` logging `{ok, key, secret, errors}`; violates `AGENTS.md` rule 7 | **FIXED in the working tree (uncommitted)** — `:77` is now a "never echo" comment and `:78` logs `{ok, key, errors}`; verified by reading the file and `git diff`. |
| **B6** | Audit writes can be silently dropped; audit stream has no TTL and retains IP | `audit.rb:52-62` now logs `request_id`/`actor_id` and increments `onetime_best_effort_failures_total{operation="audit"}`; `SECURITY_AUDIT.md` SA-16 | **Partly resolved 2026-11-21** — a dropped write is correlated and counted, proven by a red→green spec. IP retention/TTL still needs a recorded D-retention decision. |
| **B7** | Post-consume cleanup is unwrapped | `reveal_secret.rb:39-50` now wraps cleanup after the atomic consume, logs a warning (class only) and increments `onetime_best_effort_failures_total{operation="cleanup"}`; `SECURITY_AUDIT.md` SA-06 | **Resolved 2026-11-21.** Red spec observed `503` after the secret was spent; after the fix the plaintext is returned and the record is gone. No disclosure either way; now the value is not lost. |
| **B8** | Webhook deliveries list ignores the `:id` path parameter and scans owner-wide | `app.rb` passes `id` to `Webhook.deliveries`, `Webhook.owned?` guards the route with a uniform 404; `webhooks_spec.rb` proves two endpoints do not cross-list | **Resolved 2026-11-21** (explicit operator approval, D-017). Red spec first, then green. |
| — | Documentation drift (not runtime breakage) | `API.md:6` says OpenAPI not implemented while `app.rb:641` serves it; `PRD.md` §4 marks file/webhooks/OpenAPI "No" while `TASKS.md:77-79` records them DONE; `KNOWN_ISSUES.md:76` still lists file secrets missing; spec counts disagree (`SECURITY.md:7`=180, `KNOWN_ISSUES.md:8`=168, `TASKS.md:10`=149, `:199`=178) | **Process debt.** Code and specs are the source of truth. |

### 4.1 Addendum from the five independent area inspectors

These were found by the parallel frontend/backend/API/security/workflow inspectors and cross-checked in source. They supplement B1–B8; none is a crypto or consume-path break.

| ID | Defect | Evidence | Status |
|---|---|---|---|
| B9 | Dashboard copy actions bypass `CopyButton`'s clipboard fallback and give no feedback: `copyRequestLink` and `copyText` call `navigator.clipboard?.writeText` directly, silently no-oping when the API is unavailable. | `clipboard.ts:4-27` (`execCommand` fallback), `DashboardView.vue` (`CopyButton` on revealed answer, request link and signing secret; `requestNote` success alert after auto-copy) | **FIXED** — `copyText` has the fallback, list/reveal/secret copy uses `CopyButton`, and create now announces the copy in a `role=status` alert |
| B10 | Request-link TTL options are hardcoded instead of read from `/api/v3/config`, so an operator's `TTL_OPTIONS` can be contradicted by the UI. | `DashboardView.vue` (`requestTtlOptions` via `ttlOptions()` in `onMounted`), `lib/config.ts`, `ConcealView.vue` | **FIXED** — both views load TTL options and default from `/api/v3/config`, with a documented fallback only when config is unreachable |
| B11 | ~~Dark mode documented but not shipped~~ — **RESOLVED**: dark palette ships at `replica/design/tokens.css:81-100`, SPA sets `color-scheme: light dark` at `styles.css:6`; the static site remains light-only and `DESIGN_SYSTEM.md` now says so. | `DESIGN_SYSTEM.md` §3/§10, `tokens.css:81`, `styles.css:6` | **FIXED** — no remaining doc/code contradiction |
| B12 | Audit stream is write-only from the product's point of view: `Audit.recent` has no HTTP route and no CLI command; only specs call it. | `audit.rb:59-65`; route table `app.rb:565-905`; `bin/ots:183-247` | **MISSING operator read path**, S3; pairs with the missing audit UI (§3.5 #23) |
| B13 | Restore namespace allowlist admits `customer:sessions:*` even though the collector excludes them, so a crafted backup can plant revocation-index members. | `backup.rb:103` (`"customer:"` prefix) + `validate_keys!` `start_with?` at `:115` vs collector skip `backup.rb:153`; `Session::INDEX_PREFIX = "customer:sessions:"` `session.rb:16` | **AT-RISK — open**, S3. Practical impact is index pollution driving `revoke_all` (`session.rb:99-110`) to delete arbitrary `session:*` hashes — **not** direct session forgery (live session hashes are not admitted). Narrow the allowlist or reject the session prefix explicitly. |
| B14 | Revealed request answer is a raw `<pre>` with no copy affordance; the "sent" heading sets `tabindex="-1"` but never calls `focus()`, weakening screen-reader announcement. | `DashboardView.vue:360-364`; `RequestView.vue:89` vs `RevealView.vue:44-45` | **FIXED** — `CopyButton` on the answer, `nextTick`+`focus()` on sent/gone/taken; browser-verified |
| B15 | `SecretRequest.fetch_submission` is dead code (reveal reads Redis directly); `Webhook.validate_url!` is spec-only. | `secret_request.rb:69-72` vs `secret_requests.rb:96`; `webhook.rb:238` | **DEAD CODE**, S4 — remove or use, do not leave two paths |

The inspectors also corroborated every "IMPLEMENTED" row in §3.1/§3.2 with committed evidence (`e2e/*.mjs`, `spec/**`) and found **no** broken control in AES-GCM, the atomic consume, the v2 metadata MAC, session revocation, rate limits, key rotation, webhook HMAC, or the verify→decrypt→consume ordering.

**No BROKEN control was found in the crypto, session, rate-limit, consume, rotation, or webhook-signature paths.** Items B6/B7/B8/B13 are recorded as at-risk because no failing test or runtime reproduction was demonstrated.

### 4.2 Independent verification corrections (same day)

Five parallel `.claude/`-persona area auditors (frontend, backend, security, APIs, workflows) re-read this matrix against the working tree. **No status label was refuted**; the following evidence/citation corrections were applied above, and the baseline gates were re-executed:

| Area | Correction |
|---|---|
| Frontend | `RevealView.vue:9` → `:12` for the `idle` default. "No browser storage" now has direct evidence: `grep -rl 'localStorage\|sessionStorage\|indexedDB' public/app/assets` → no matches. B5's current log line is `:78`, not `:77`, and the fix is uncommitted. Latent risk noted: `e2e/requests.mjs:69-70` failure-only `DEBUG_MAIN` DOM dumps; not triggered on success paths. |
| Backend | Purge-worker citation moved `ARCHITECTURE.md:30` → `:70` (+ `DATABASE.md:161`); full-mode spec `:455-459` → `:455-461`. View-budget grep hits docs, not code; file-cap coupling is `MAX_FILE_BYTES` ↔ `MAX_SECRET_BYTES`; B13 impact narrowed to revocation-index pollution. |
| Security | Webhook pinning evidence extended to the delivery-time enforcement at `webhook.rb:216-236,271-295`; B7 impact reworded — the spent secret is **lost** on a cleanup error, merely not disclosed. Supporting `SECURITY_AUDIT.md` line numbers for SA-06/14/23 have drifted (documentation debt). |
| APIs | **B1 narrowed**: 404 already uses `LegacyError`; only 503 (all v1 paths) and 429 (`/api/v1/share`) remain wrong. **B3 fix corrected**: a naive "not 404" assertion would break legitimate domain 404s; detect the generic catch-all body instead. B2/B4 verified as written. |
| Workflows | All 14 workflow statuses and B5 VERIFIED. `file.mjs:80` prints a literal `replay:"404"` while the real assertion waits on the UI; no committed full webhook delivery journey exists. |

## 5. Implementation priorities

Ranked by user value, security impact, complexity and dependencies. Operator-only items are included because they gate any "production ready" claim.

| # | Item | Current status | Value | Sec | Complexity | Deps | Priority | Why now |
|---|---|---|---|---|---|---|---|---|
| 1 | **Restore OpenAPI fidelity + make the mount gate real** (B1–B4) | BROKEN | 3 | 4 | **S** | None | **P0** | Fixed in hours; generated v1 clients still parse wrong 503/429 bodies and the gate cannot catch drift. Use a body-based catch-all check (B3), not "not 404". `openapi.rb` and `openapi_spec.rb` are not protected paths. |
| 2 | **Complete backup/restore coverage** for `request:*` and `webhook:*` (SA-22) | PARTIAL | 4 | 5 | **M** | Low | **P0** | Silent data loss on restore for inbound answers and webhook config. Guard/0600 already fixed; extend collectors + `restorable_prefixes`, bump format with backward compatibility, red→green specs. Restore itself is a human drill (`RUNBOOK.md`). |
| 3 | **Close T-70 TLS on a real hostname, T-71 host firewall, and schedule `bin/ots webhooks:work` (K-46)** | PARTIAL / operator | 5 | 5 | **S code / L ops** | High (host, cert, cron) | **P0 (ops)** | Zero code needed; app side rehearsed. Until done, no public "production ready" claim and queued webhooks never deliver. |
| 4 | **Owner receipt lifecycle**: statuses, owner burn, 30-day metadata retention | PARTIAL | 5 | 3 | **M** | Med | **P1** | D-017 resolved the decision and shipped statuses + retention + burn (T-131). Still open: a separate receipt token and `/receipt/` SPA route (no token model decision yet); the opaque secret key remains the capability. |
| 5 | **Per-secret passphrase attempt budget** (SA-14) | MISSING | 3 | 5 | **M** | **High** (D-012 product decision) | **P1** | Only auth-strength gap vs Password Pusher's 5/min per push; also an Argon2 DoS control. Must keep verify→decrypt→consume ordering. |
| 6 | **`ots conceal` / `ots reveal` CLI** | MISSING | 4 | 2 | **S** | Low | **P1** | Best value-per-effort for the PRD developer persona; `examples/` prove the HTTP sequence. Call the API, not Redis directly; no new gem. |
| 7 | **Bearer/API-token auth** for headless integrations | MISSING | 4 | 4 | **M/L** | High (new token model, protected `app.rb`, SECURITY doc) | **P1** | Largest functional API gap vs Onetime/PWP. Must not weaken cookie CSRF or guest routes. |
| 8 | **Password generator + QR/`mailto:` share** (#12/#13) | MISSING | 3 | 1 | **S** | None | **P2** | Cheap, pure-frontend parity wins; generator uses Web Crypto, no new dependency. |
| 9 | **Wrap post-consume cleanup (SA-06) + dropped-audit counter (SA-16) + id-scoped deliveries (B8) + narrow restore allowlist (B13) + expose `Audit.recent` (B12)** | PARTIAL | 3 | 4 | **S** | Low | **P2** | SA-06 and SA-16 landed 2026-11-21 with red→green specs and an alertable counter. B8 still needs a protected `app.rb` edit (approval); B12/B13 and the restore allowlist remain open. |
| 9a | **Frontend polish B9–B11, B14** — implemented and browser-verified: 44px targets, route titles, focus recovery, clipboard announcements, answer copy, axe gate. Dark theme deliberately skipped. | **DONE** | 3 | 1 | **S** | None | **P2** | Closed with 20 Vitest tests, five journeys and 11-state axe gate; real screen-reader output still needs a manual pass. |
| 10 | **Raise file cap, multi-file, in-browser previews** | PARTIAL | 4 | 2 | **M/L** | Med (payload shape, API.md, protected route) | **P2** | Closes the PrivateBin/PWP UX gap; note their 2026 XSS advisories came from previews — budget sanitization/CSP. |
| 11 | **Inbound requests: file answers, passphrase, substitution fingerprint** | PARTIAL | 3 | 3 | **M** | Med | **P2** | Yopass/PWP parity; requires data-shape change and `AUTH_MODE` decision. |
| 12 | **Agent discovery: `/llms.txt` + generated TS/Python types** | MISSING | 3 | 1 | **S/M** | Low (decision entry; protected `app.rb` for route) | **P2** | Onetime/Yopass discovery parity; do not claim `/mcp` (unverified). |
| 13 | **i18n for SPA (and later emails)** | MISSING | 3 | 1 | **L** | High (new dep + decision + RTL) | **P2** | Competitors ship 30–36 locales; T-64 is the status-of-record slot. |
| 14 | **View-count / multi-view budget** | MISSING | 2 | 3 | **M** | High (product decision + phased data migration) | **DEFER** | Changes the one-time primitive; needs explicit semantics before implementation. |
| 15 | **Custom domains / branding** | MISSING | 4 | 2 | **L** | High (TLS, clean-room brand rules) | **DEFER** | Paid competitor feature; conflicts with the deliberate clean-room identity. |
| 16 | **Destruction notification email** | MISSING | 3 | 2 | **L** | High (mail gem decision, SMTP, templates, queue) | **DEFER** | Real sender assurance but operator infrastructure heavy; webhook already covers machine consumers. |
| 17 | **Full auth / SSO / MFA / RBAC / IP allowlisting** | MISSING (501) | 3 | 4 | **L** | High (Postgres/RabbitMQ, new gems, protected paths) | **DEFER** (D-003/T-60) | Reverse a documented decision first; close T-70/T-71 before adding surface. |
| 18 | **Client-side encryption** | MISSING | 5 | 5 | **L** | **High** (reverses D-012) | **DEFER** | Would change the core threat model. Any copy must never claim zero-knowledge without architectural evidence. |
| 19 | **Multiple storage backends / discussions / Markdown / JSON-LD compatibility** | MISSING | 2 | 2 | **L** | High | **DEFER** | Explicit architecture decisions; JSON-LD client compat is infeasible without client-side encryption. |

**Sequencing note:** #1–#3 can proceed in parallel once the human confirms the protected-path/operator work; #4–#7 depend on product decisions recorded in `docs/DECISIONS.md`; every implementation must update `TASKS.md`, `replica/features.csv`, `API.md`/`DATABASE.md` and `CHANGELOG.md` in the same change, and new specs must be seen failing before they pass.

## 6. Explicitly unverified

- The five area auditors ran no tests, browsers, curls or restore drills; their statuses rest on source and committed specs. The baseline in §2 **was** executed in this pass (`rspec`, Vitest, typecheck, build).
- No live stack was started; E2E journeys are read as committed scripts, not executed here. The webhook end-to-end chain has **no** single committed journey; scanner/prefetch GET resistance is inferred from POST-only code, not journey-tested.
- Absence claims (view budget, discussions, generator, QR, email, i18n, API token, MCP) come from repo-wide greps and the mounted route table, not negative tests.
- Competitor facts are quoted from `COMPETITOR_RESEARCH.md` with its own VERIFIED/PARTIAL/UNKNOWN labels; `api.onetimesecret.com/mcp`, automatic certificate issuance, signed tags/SLSA and attestation were **not** verified there and are not asserted here.
- The audit agents noted `COMPETITOR_RESEARCH.md` changed concurrently during their reads; its §3–§6 substance was re-read before writing this matrix.
- Five independent area re-verifiers ran this pass; none refuted a status label. Their corrections are in §4.2. Re-executed gates: RSpec **180/0** (seed 33248), Vitest **12/12**, `vue-tsc --noEmit` clean, Vite build (239.75 kB JS / 22.77 kB CSS), `replica-diff/parity.py` **66.7/100** (24 counted, 11/11 must-haves — clean-room clone parity, not this comparison). No live E2E or restore drill was run; journey statuses are read from committed scripts.
- `replica/features.csv` parity tool currently reports **66.7/100** (24 counted, 11/11 must-haves); that measures clean-room clone parity, not the competitor comparison above — do not conflate the two.
- No status in this matrix was inferred from a competitor's marketing claim alone where the research doc labelled it unverified.
