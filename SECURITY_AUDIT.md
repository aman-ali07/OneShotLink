# OneShotLink — Security Audit

**Date:** 2026-11-21
**Scope:** the full application stack in this repository — Roda/Rack web layer, crypto,
authentication, Redis data layer, webhooks, backup/restore, audit logging, configuration and
deployment posture. This is a code-and-behaviour audit, not a penetration test of a deployed
host.

## 1. Method and evidence standard

- Five parallel specialist reviews were run: **cryptography**, **authentication**, **API
  security**, **database/Redis security**, and **threat modelling**. All findings were
  re-read against the source before being recorded here; agent prose is not treated as
  evidence.
- Regression specs were added for each fix and checked against the pre-fix behavior where
  practical. The first batch was observed **red (`34 examples, 8 failures`)** before the
  implementation and **green** afterwards; the metadata-MAC and HEAD-header specs would
  likewise fail against the pre-fix code (they assert behavior that did not exist).
- Ruby is not installed on the host, so backend verification runs in the `ots-dev` Docker
  image against Redis DB 15, per `TESTING.md` §2.
- "Verified" below means a command was executed and its output observed. Claims inherited
  from `SECURITY.md` / `PRODUCTION_READINESS.md` are labelled as documented, not re-run.

## 2. Executive summary

The core one-time-secret guarantees are sound: AES-256-GCM with a per-record random salt and
IV, an atomic Lua compare-and-delete for consumption, verification and decryption *before*
the irreversible delete, opaque 128-bit identifiers, Argon2id passphrase hashing, and
fail-closed configuration. No nonce reuse, no plaintext-at-rest defect, and no break in the
single-use invariant was found.

Two passes recorded **thirty-one** issues (SA-01…SA-31) and fixed **nineteen** in code. The
first pass fixed the webhook SSRF (DNS rebinding), key-rotation orphaning, rotation/backup
integrity, metadata tampering, logging leakage, retry and account-cleanup defects. A second
pass of five parallel domain reviews (§13) found and fixed one S2 — shipped defaults that
collapsed all per-IP rate limits into one bucket behind the local TLS proxy — plus seven S4s
(attacker-chosen cipher, shared responder bucket, incomplete HEAD headers, OpenAPI burn drift,
unverified previews, replayable request links, and documentation overclaim). The remainder
are operator actions or product decisions, not code defects, and are listed in §6, §10 and §13.

**There is no end-to-end encryption and no zero-knowledge property in this design.** See §7.

## 3. Findings and dispositions

Severity: **S1** blocks use/security, **S2** high, **S3** medium, **S4** low/process.

| ID | Sev | Finding | Evidence (verified in source) | Status |
| --- | --- | --- | --- | --- |
| SA-01 | S2 | **Webhook SSRF via DNS rebinding.** URL was checked against private ranges only at creation, then `Net::HTTP.start(uri.host, …)` re-resolved the name at delivery; IPv4-mapped IPv6 (`::ffff:169.254.169.254`) also bypassed the blocklist. | `webhook.rb` `validate_url!` / `post` (pre-fix), `PRIVATE_NETS` | **Fixed** |
| SA-02 | S2 | **Key rotation orphaned other encrypted data.** Rotation scanned only `secret:object:*`; `request:secret:*` submissions and `webhook:endpoint:*` `signing_secret` fields stayed under the old key. After the recommended `SECRET` swap, submissions 500'd until TTL and webhook signatures failed permanently. | `rotate_key.rb` `each_object_key`; `secret_requests.rb:71`; `webhook.rb:61,147` | **Fixed** |
| SA-03 | S2 | **Session revocation index TTL does not slide.** Session key TTL refreshes on every request; `customer:sessions:<id>` expires at creation time only. `revoke_all` reads that index, so after one `SESSION_TTL` a still-live stolen session survives a password change. | `session.rb:47-49,60,77-83`; `app.rb:704` | **Fixed (see §11)** |
| SA-04 | S3 | **Backup file created with the process umask** (typically `0644`) although it contains Argon2id password hashes and customer emails. | `backup.rb:27-29` (pre-fix) | **Fixed** |
| SA-05 | S3 | **Unauthenticated record metadata.** GCM AAD covered only the salt; `passphrase_hash`, `owner_id`, `kind`, `ttl` were editable by anyone with Redis write access, allowing the passphrase gate to be stripped. | `crypto.rb:34,54` (pre-fix) | **Fixed with v2 metadata MAC** (parallel work) |
| SA-06 | — | **Resolved 2026-11-21:** post-consume receipt/index cleanup is best-effort. A Redis failure now logs a warning (class only, never the secret key) and increments `onetime_best_effort_failures_total{operation="cleanup"}`; the plaintext is still delivered once and the record stays consumed. Red spec first (`503` after consume), then green. | `reveal_secret.rb:41-50`; `metrics.rb`; `spec/integration/security_hardening_spec.rb` | — |
| SA-07 | S4 | **Request-link keys logged in cleartext** in `/api/v3/requests/:key` and `/request/:key`; these are bearer capabilities. | `request_logger.rb:11-12,37` (pre-fix) | **Fixed** |
| SA-08 | S4 | **Webhook retries never ran.** `seen:<id>` was claimed before the POST, so a re-queued retry was skipped; `MAX_ATTEMPTS` was unreachable. | `webhook.rb:139-163` (pre-fix) | **Fixed** (parallel work) |
| SA-09 | S4 | **HEAD 405 bypassed hardening headers and request ID** because the guard returns before Roda. | `head_requests.rb:20-21` (pre-fix) | **Fixed** (parallel work) |
| SA-10 | S4 | **False control attestation:** `Crypto.secure_compare` had no callers and no spec, while `SECURITY.md:31` claimed unit-spec verification. | `crypto.rb:67-72`; `spec/unit/crypto_spec.rb` | **Fixed** — spec added |
| SA-11 | S4 | **Rate-limit scope collision:** `:signin` is shared by signup, signin and request creation, so a burst in one flow locks out the others from the same IP. | `app.rb:642,653,747` | **Fixed (see §11)** |
| SA-12 | S4 | **SECRET error says "entropy" but only byte length is checked.** | `config.rb:39-45` | **Fixed (see §11)** |
| SA-13 | S4 | **Account deletion left request links, submissions and webhook endpoints behind.** | `delete_account.rb:17-37` (pre-fix) | **Fixed** (parallel work) |
| SA-14 | S3 | **No per-secret passphrase attempt budget**; only a per-IP limiter. Distributed guessing remains possible and each guess costs an Argon2id run. | `reveal_secret.rb:62-70`; `config.rb:22-24` | **Accepted product decision** (D-012) — see §8 |
| SA-15 | S3 | **`restore` was unguarded**: overlaying an old backup could overwrite live keys and resurrect consumed records; backups also omit `request:*` / `webhook:*` / audit data. | `backup.rb:38-130` (pre-fix); `bin/ots:173-181` | **Fixed** (overwrite guard + namespace allowlist); backup coverage still partial |
| SA-16 | S4 | **Partly resolved 2026-11-21:** a dropped audit write now logs `request_id`/`actor_id` and increments `onetime_best_effort_failures_total{operation="audit"}` instead of disappearing. The stream still has no IP-retention policy — that remains an operator/product decision (D-retention). | `audit.rb:52-62`; `metrics.rb`; `spec/unit/ops_spec.rb` | D-retention for IP trimming |
| SA-17 | — | **TLS on a real hostname (T-70) and Redis host firewall (T-71)** remain operator-owned. | `PRODUCTION_READINESS.md` | **Open — operator action** |
| SA-18 | S4 | **Rate-limit and edge gaps on protected paths:** no limiter on webhook creation (each call performs DNS), password change, account deletion, signout or `/metrics`; `include?("application/json")` accepts `application/jsonp`; Roda's static-file headers replace CSP/nosniff on assets. | `app.rb:242,579-597,664-734,784-810` | **Fixed (see §11)** |
| SA-19 | S4 | **Overstated / drifting documentation and unauthenticated metrics:** spec counts disagree (133 vs 149), `/metrics` emits the exact version when enabled, and no scrape-network restriction is enforced. | `SECURITY.md:7`, `KNOWN_ISSUES.md:6`, `metrics.rb:80`, `app.rb:587-597` | **Open — documented/operator** |
| SA-20 | S4 | **Lua consume script had an empty-value escape hatch:** `if ARGV[1] ~= '' …` meant an empty expected value would delete unconditionally if the Ruby guard were ever bypassed. | `store.rb:46-52` (pre-fix) | **Fixed** — comparison is now unconditional |
| SA-21 | S1 | **The go-live self-test can destroy a live deployment.** `script/preflight_selftest.sh` reuses the default Compose project (`name: oneshotlink`) and its EXIT trap runs `docker compose down -v --remove-orphans`; on a host running the real stack it deletes `oneshotlink_redis-data` and `oneshotlink_backup-data` after recreating web/Redis with throwaway keys. | `script/preflight_selftest.sh:24,35-40,84`; `compose.yaml:1` | **Fixed (see §11)** |
| SA-22 | S3 | **Backups are incomplete.** Export collects only `secret:object:*`, receipts and `customer:*`; pending `request:object:*` / `request:secret:*`, webhook endpoints and their deliveries are silently lost on restore. | `backup.rb` (pre-fix) | **Fixed** — format 2 exports/imports all request and webhook namespaces with TTLs, keeps format-1 readers, and the allowlist now rejects `customer:sessions:*`, `webhook:seen:*` and `webhook:inflight:*`. Red→green specs in `spec/unit/ops_spec.rb`; no restore drill run against a live instance. |
| SA-23 | S4 | **Webhook delivery enumeration used Redis `KEYS`** and ignored the `:id` path parameter, so one authenticated call scanned the whole keyspace and returned the owner's deliveries across all endpoints. | `webhook.rb:193-217` (`deliveries`), `app.rb:838-842` | **Fixed** — `deliveries` uses `SCAN` filtered by owner endpoint id, and the route checks `Webhook.owned?` so a foreign/unknown id is a uniform 404. Integration spec in `webhooks_spec.rb` |

### Second pass — five parallel specialist reviews (2026-11-21)

The five domains required by the audit directive (cryptography, authentication, API security,
database/Redis security, threat modelling) were run again as independent reviewers after the
first pass, then every finding was re-read against source. New findings SA-24…SA-31 and their
dispositions are recorded in §13.

## 4. Fixes implemented in this pass

### SA-01 — Webhook SSRF (S2)
`lib/onetime/webhook.rb`:
- `validate_endpoint` resolves once, checks **every** answer against `PRIVATE_NETS`, and
  returns the validated IP alongside the URL; `validate_url!` is kept as a thin wrapper.
- That IP is stored as `resolved_ip` on the endpoint. `pinned_address` re-checks it at
  delivery (and resolves-and-validates for legacy endpoints with no stored IP).
- `post` sets `Net::HTTP#ipaddr` **before** `start` opens the socket, so the TCP destination
  is the validated IP while `Host` and TLS SNI stay the original hostname. The initial
  attempt to set `ipaddr` inside the `start` block failed with `Socket::ResolutionError`
  and was corrected — that failure is the evidence the pin actually matters.
- `private_address?` normalizes IPv4-mapped IPv6 with `IPAddr#native`.
- No redirects are followed (Net::HTTP default), and payloads remain metadata-only.

Regression specs: `spec/unit/webhook_spec.rb` — rejects mapped IPv6, stores the validated
address, refuses a private stored address, and proves a socket connects to the pinned IP
while preserving the `Host` header.

### SA-02 — Key rotation (S2)
`lib/onetime/logic/rotate_key.rb` now walks all three encrypted data classes:
`secret:object:*` (metadata preserved), `request:secret:*` (bare Crypto payload), and
`webhook:endpoint:*` `signing_secret` (hash field). String records use the existing
`Store.rewrite_if_unchanged` CAS; hash fields use the new
`Store.rewrite_hash_field_if_unchanged` Lua CAS in `lib/onetime/store.rb`. `HSET` does not
disturb a TTL. The webhook signing secret is re-encrypted, not regenerated, so receivers'
signatures keep verifying.

Regression specs: `spec/unit/ops_spec.rb` (submission + signing secret decrypt under the
new key and fail under the old one; consumed records still are not resurrected) and
`spec/unit/store_spec.rb` (hash-field CAS match/mismatch).

### SA-04 / SA-05 / SA-07 / SA-10 — smaller fixes
- `backup.rb`: the `.tmp` export is created with `File::WRONLY|CREAT|EXCL, 0o600` after
  removing a stale temp file; verified `0600` by `File.stat`.
- `web/request_logger.rb`: added redaction for `/api/v3/requests/<key>` and `/request/<key>`.
- `spec/unit/crypto_spec.rb`: added constant-time comparison examples, making the existing
  `SECURITY.md` claim true.

### SA-15 / SA-20 — backup and consume hardening
- `backup.rb#restore(path, force: false)` now refuses to overwrite any live key unless
  `force: true` is passed (`bin/ots restore --in FILE --force`), and rejects backup files
  containing keys outside `secret:object:*`, `secret:receipt:*` or `customer:*`. Tests assert
  the overwrite is refused, forced restore still works, and an evil namespace is rejected.
- `Store::CONSUME_SCRIPT` no longer exempts an empty `ARGV[1]` from the comparison; the Lua
  contract itself now cannot delete an unverified record.

### Record metadata, HEAD headers and account cleanup
A v2 record metadata MAC (`models/secret.rb` `sign_meta!`/`verify_meta!`, checked in
`logic/reveal_secret.rb` before the passphrase gate and decrypt, and renewed by rotation)
stops a Redis writer from stripping `passphrase_hash` or editing display metadata. **v2 is
enforced with no legacy read window**: a `v != 3` or unsigned record is rejected with a typed
500 and the record is left intact (P0-5). HEAD 405 now
carries the app's hardening headers and a request ID (`web/head_requests.rb`). Account
deletion removes request links/submissions, webhook endpoints and their delivery records.
Coverage: `spec/integration/security_hardening_spec.rb` (4 metadata/rotation cases + HEAD),
`spec/integration/accounts_spec.rb`, `spec/unit/ops_spec.rb`.

## 5. Security guarantees verified by executable evidence

| Guarantee | Evidence |
| --- | --- |
| One-time consume is atomic; concurrent reveals yield one winner | `Store.consume` Lua GET/compare/DEL; 8-way race spec in `secrets_api_spec.rb` |
| Wrong passphrase and undecryptable/corrupt records are not destroyed | verify → decrypt → consume order in `reveal_secret.rb`; specs for wrong passphrase, tampered ciphertext and rotated key |
| Only ciphertext is persisted | `Models::Secret.create` encrypts before `JSON.generate`; at-rest integration spec |
| Opaque identifiers, no plaintext in URLs/storage | `Ids.extid` 128-bit CSPRNG; browser journeys assert empty `localStorage` |
| Argon2id (m=64 MiB, t=3, p=2) with bcrypt legacy verify | `password.rb:13`; `spec/unit/password_spec.rb` |
| Boundary validation fails closed | TTL allowlist, size caps on JSON/form/chunked bodies, passphrase floor; `413`/`422` specs |
| Client IP cannot be spoofed unless a trusted proxy is configured | `app.rb#client_id`; proxy-trust specs |
| No stack traces, Redis errors or secret material in responses/logs | typed error handler; redacted request logger; audit closed vocabulary |
| Fail-closed configuration | `Config.validate!` at boot; `AUTH_MODE=full` → 501 |

## 6. Threat model — highest residual paths

1. **Operator trust / SECRET compromise.** The instance key decrypts everything. A leaked
   `SECRET` plus a Redis dump exposes all unexpired secrets, including passphrase-protected
   ones. Rotation now preserves all encrypted data classes, but a leaked key that is never
   rotated remains a total compromise.
2. **Link interception.** Anyone with the link first wins. Transport security is entirely
   the operator's TLS terminator (T-70); without it, links and reveal responses travel in
   clear text.
3. **Passphrase guessing.** 8-byte floor + Argon2id + per-IP limiter **and** a per-secret budget
   (D-012b: 5 guesses / 900 s keyed by the opaque secret id). A fixed window permits boundary
   bursts; a distributed attacker still gets 5 guesses per link per window, and the Argon2id
   CPU/memory cost remains a DoS vector.
4. **Redis write access.** The v2 metadata MAC protects access-control and display fields;
   v1/unsigned records are rejected outright (no compatibility window). The AEAD and the
   metadata MAC still rely on the operator-held `SECRET` never leaking.
5. **Webhooks.** IP pinning closes DNS rebinding, but private URL testing requires
   `WEBHOOK_ALLOW_PRIVATE=true`, delivery is at-least-once, and the worker must be scheduled
   by the operator (K-46).

## 7. E2EE / zero-knowledge statement — read this before writing copy

**Do not claim end-to-end encryption, zero knowledge, or "the server cannot decrypt".**
They are false for this architecture:

- Decryption uses only the instance `SECRET` (`crypto.rb`); the passphrase is verified against
  an Argon2id hash and then discarded — it is an **access gate**, not a second key (D-012).
- The web process sees plaintext in memory on both create and reveal.
- A leaked `SECRET` plus a record opens the content without the passphrase.

The accurate statement is: **"AES-256-GCM at rest with an operator-held instance key; an
optional Argon2id passphrase acts as an extra access check."** Also do not call the service
"production ready" in public copy while T-70 and T-71 are open.

## 8. Coordination with product engineering

The `stageshow` skill was loaded and its restraint rules applied to the product-facing
coordinate: one focal object, real words only on what the story is about, no decorative
"security" sparkles or purple accent, and a still whose payoff is the result, not a mid-change
frame. The coordination still is committed at `docs/security-posture.html` and
`docs/security-posture.png`: a cropped product window with one satellite panel, real words
only on the findings and their statuses, and placeholder lines elsewhere. It is an
illustration for the product-engineering conversation, not a screenshot of a live dashboard.
The messages for product engineering are: (a) keep passphrase copy as "extra access check", never
E2EE; (b) D-012b closed the per-secret budget question — communicate the 5 guesses / 900 s
behaviour; (c) the operator must terminate TLS on a real hostname and schedule the webhook
worker; (d) backup restore and key rotation remain operator-run commands with a defined runbook;
(e) the v2 metadata MAC is **strictly enforced** with no legacy read window: a missing/invalid
MAC is rejected and the record left intact, never revealed.

## 9. Verification

Baseline before changes: `149 examples, 0 failures` (observed).
Red phase for the first regression batch: `34 examples, 8 failures` (observed, with the eight
failures matching the eight missing fixes).
After the first pass: `168 examples, 0 failures` (seed 54368). After the protected-path pass
below: `180 examples, 0 failures` (observed, seed 10555, 53.49 s); the previously failing
order-dependent seed 54318 also passed at `178 examples, 0 failures` before the last two
session specs were added. Additional gates: `npm --prefix frontend run test` → 12 passed;
`npm --prefix frontend run typecheck` → clean; `npm --prefix frontend run build` → built;
`script/brand-sweep.sh` → clean; `bash -n script/preflight_selftest.sh` → OK;
`docker compose config --quiet` → OK; `script/preflight_selftest.sh` → **`PREFLIGHT SELFTEST
PASSED (5 assertions)`**, with the self-test project `otspreflight-selftest` and no leftover
containers; GitHub API resolved every pinned CI action SHA (`actions/checkout` v4.4.0 =
`11d5960…`, `actions/setup-node` v4.4.0 = `49933ea…`, `ruby/setup-ruby` v1 branch head =
`be3c7df…`). The stageshow still rendered in headless Chrome at 1030×560 with 0 page errors.

```bash
# Ruby is not installed on the host; use the ots-dev image against a throwaway Redis DB 15.
docker run -d --rm --name ots-audit-verify -p 6398:6379 redis:7.4-alpine
docker run --rm --network=host \
  -v "$PWD":/app -v ots-bundle:/bundle -e BUNDLE_PATH=/bundle \
  -e REDIS_URL=redis://127.0.0.1:6398/15 -w /app \
  ots-dev bundle exec rspec
```

## 10. Deferred items from the first pass

These files are marked in `AGENTS.md` as requiring human review. The first pass therefore
only specified patches; a later directive authorized the listed changes and they are now
applied (see §11). `lib/onetime/crypto.rb`, `lib/onetime/password.rb`, `Dockerfile`,
`config.ru` and `config/puma.rb` were **not** changed.

- **SA-03** (`models/session.rb`): slide the `customer:sessions:*` index TTL in `Session.fetch`
  (the customer ID is already in the hash), or drop the index TTL and prune stale digests.
  Also make `revoke_all` one MULTI and guard `fetch`'s `HSET` against a concurrent destroy.
  Spec: expire only the index, slide the session, assert `revoke_all` still revokes.
- **SA-11 / SA-12 / SA-18** (`web/app.rb`, `config.rb`): split the `:signin` limiter scope;
  rate-limit webhook creation, password change, account deletion, signout and `/metrics`;
  use `request.media_type == "application/json"`; merge hardening headers back into
  Roda's static-file responses; reword the SECRET error to say "length" not "entropy".
- **SA-21 (Critical, protected path `script/preflight*.sh`)** — the go-live self-test must be
  isolated from production. Concrete patch:
  ```diff
   cleanup() {
     docker rm -f "$CADDY" >/dev/null 2>&1
  -  SECRET=x REDIS_PASSWORD=y docker compose down -v --remove-orphans >/dev/null 2>&1
  +  SECRET=x REDIS_PASSWORD=y docker compose -p oneshotlink-selftest down -v --remove-orphans >/dev/null 2>&1
     rm -rf "$WORK"
   }
  ...
  - docker compose up -d >/dev/null 2>&1 || { echo "compose up failed" >&2; exit 1; }
  + docker compose -p oneshotlink-selftest up -d >/dev/null 2>&1 || { echo "compose up failed" >&2; exit 1; }
  ```
  Apply the project flag to **every** `docker compose` invocation in the script, derive `NET`
  from that project's network, and refuse a project name equal to the production project
  (`oneshotlink`) before any container is created. Until then, never run the self-test on a
  host with a live stack.
- **SA-01 (defense in depth)** (`compose.yaml`, workflows): default `APP_BIND` to `127.0.0.1`,
  use `REDISCLI_AUTH` instead of `-a` in the healthcheck, pin CI actions to full SHAs, and
  firewall the webhook worker's egress.
- **SA-06 / SA-16:** wrap post-consume cleanup so a receipt-delete failure cannot turn a
  spent secret into a 500, and count/alert on dropped audit writes.
- **SA-14:** product decision on a per-secret passphrase attempt budget.
- **SA-17:** operator action for TLS (T-70) and the Redis host firewall (T-71).

## 11. Follow-up: protected-path fixes applied 2026-11-21 (T-120)

The items above were authorized in a later directive and have now been applied:

- **SA-03 — FIXED** (`models/session.rb`). `Session.fetch` uses one Lua `TOUCH_SCRIPT`
  that checks `EXISTS` (a concurrent destroy cannot recreate a TTL-less ghost hash),
  slides the session TTL, and re-adds + slides the digest in `customer:sessions:<id>`.
  `revoke_all` is one MULTI. Regression spec: delete only the index, fetch the session,
  assert the digest is restored and revocation still works.
- **SA-11 / SA-12 / SA-18 — FIXED** (`web/app.rb`, `config.rb`, `.env.example`). Nine
  independent limiter scopes with boot validation; webhook creation/deletion, password
  change, account deletion and signout are now limited; JSON parsing uses
  `request.media_type == "application/json"`; static assets get the same hardening headers
  via a shared `HARDENING_HEADERS` hash; the SECRET error says "bytes", not "entropy".
- **SA-21 / SA-01 defense in depth — FIXED** (`script/preflight_selftest.sh`, `compose.yaml`,
  `.github/workflows/ci.yml`). The self-test uses its own Compose project, derives its
  network from it, refuses the production project name **and refuses to run while any
  container of the production project exists**, and passes `-p` to every compose call.
  `define_preflight` also passes `REDIS_NETWORK=<project>_backend` so the Redis-reachability
  negative control still exercises the isolated network — without it the renamed project
  made that check vacuous (observed as a failing self-test before the fix). Compose defaults
  `APP_BIND=127.0.0.1`, uses `REDISCLI_AUTH`, and passes the new rate-limit variables; CI
  actions are pinned to full commit SHAs. Verified with `docker compose config --quiet`,
  `bash -n`, a Psych YAML parse, and a full `script/preflight_selftest.sh` run ending
  `PREFLIGHT SELFTEST PASSED (5 assertions)`.
- Remaining are not code defects: post-consume cleanup alerting, a product decision on a
  per-secret passphrase budget, and operator TLS/firewall/egress actions.

Final backend suite for the protected-path pass: **180 examples, 0 failures** (seed 10555).
Two extra session specs (slide the index TTL on touch; do not recreate a destroyed hash) were
added in the follow-up.

## 12. Follow-up gates closed 2026-11-21

Driven by the `IMPLEMENTATION_PLAN.md` P0 increment and five parallel specialist reviews
(database, API, business logic, validation/logging, backend testing):

- **P0-5 — metadata-MAC downgrade closed.** `verify_meta!` now rejects any record whose
  `v != 2` or whose `meta_mac` is missing/empty. Previously a Redis writer could set `v=1`,
  delete the MAC and the passphrase hash, and reveal a protected secret without a
  passphrase. The red spec observed `200`; after the fix it is `500` with the record intact.
  There is no released data to stay compatible with, so no dual-read window is needed.
- **P0-3 — migration substrate.** `Onetime::Migrate` owns `schema:version` with a read-only
  `ots migrate --dry-run` and an idempotent `ots migrate`; it refuses corrupt/newer markers
  and never rewrites `secret:object` values. Six red→green specs plus a live CLI run.
- **P0-4.1 / 4.2 — SA-06 and SA-16**, resolved in the tables above. The new
  `onetime_best_effort_failures_total{operation="cleanup"|"audit"}` counter makes both
  best-effort edge effects alertable without breaking a request.

Still open and deliberately left for a recorded decision or an operator: backup format v2
and restore allowlist (P0-2), endpoint-scoped webhook deliveries (B8 — protected `app.rb`),
owner burn/receipt status (P1), per-secret passphrase budget (D-012b), IP retention
(D-retention), TLS/hostname (T-70) and the host Redis firewall (T-71).

Backend suite after these gates: **188 examples, 0 failures** (seed 53895). Later in the
same increment the suite grew to **213 examples, 0 failures** (seed 27845) with the OpenAPI
contract, audit-redaction, CLI and owner-index-TTL specs; the request-object MAC is now
verified before owner authorization in `RevealRequestSubmission`.

## 13. Second-pass specialist reviews, findings and fixes (2026-11-21)

Five independent reviewers (cryptography, authentication, API security, database/Redis
security, threat modelling) audited the code again after the first pass. They ran in
parallel; every claim below was re-read against source before being recorded. Agent prose
is not treated as evidence.

### Findings and dispositions

| ID | Sev | Finding | Evidence | Status |
| --- | --- | --- | --- | --- |
| SA-24 | S2 | **Shipped defaults collapse every per-IP limit into one bucket.** `APP_BIND=127.0.0.1` with `TRUST_PROXY=false` means all users behind the documented same-host TLS proxy arrive as `127.0.0.1`; one caller exhausting `RATE_LIMIT_REVEAL`/`CONCEAL` locks out everyone. | `.env.example:56-58`, `compose.yaml:70-71`, `app.rb#client_id:166-180` | **Fixed** — shipped defaults are now `TRUST_PROXY=true`, `TRUSTED_PROXIES=127.0.0.1/32,::1/128`. `client_id` still ignores `X-Forwarded-For` unless `REMOTE_ADDR` is itself trusted, so binding `0.0.0.0` cannot enable spoofing. Config *code* default stays fail-closed (`false`). Spec asserts the shipped topology. |
| SA-25 | S4 | **Attacker-chosen cipher algorithm.** `Crypto.decrypt` passed the unauthenticated `cipher` field (outside AEAD and the record MAC) to `OpenSSL::Cipher.new`; an unknown name raised a raw `RuntimeError` → generic 500 instead of a typed integrity error. | `crypto.rb:49` (pre-fix) | **Fixed** — only `aes-256-gcm` is accepted; anything else raises `Onetime::Error`. Red evidence: `OpenSSL::Cipher.new("garbage")` → `RuntimeError: unsupported cipher algorithm`. Spec added. |
| SA-26 | S4 | **Responder shared the conceal rate-limit bucket.** `respond_to_request_payload` called `enforce_rate_limit!(:conceal)`, so exhausting one flow blocked secret creation from the same IP. | `app.rb:378` (pre-fix), `config.rb` | **Fixed** — dedicated `:respond` scope (`RATE_LIMIT_RESPOND`), boot-validated; integration spec keeps responding after the conceal budget is exhausted. |
| SA-27 | S4 | **HEAD 405 carried an incomplete header set.** The middleware hand-listed headers and omitted `Permissions-Policy` and `X-Permitted-Cross-Domain-Policies`. | `head_requests.rb:37-50` (pre-fix) | **Fixed** — it now merges `App::HARDENING_HEADERS`; spec asserts the full canonical set. |
| SA-28 | S4 | **OpenAPI omitted the owner burn route** although `DELETE /api/v3/secret/{key}` is mounted. | `openapi.rb`, `openapi_spec.rb` | **Fixed** — documented operation + `BurnResponse`; spec asserts verb, cookie security and 429. |
| SA-29 | S4 | **Previews trusted unverified metadata.** `peek_payload` and `request_preview_payload` rendered record fields without the MAC check that submit/reveal perform. | `app.rb#peek_payload`, `app.rb#request_preview_payload` (pre-fix) | **Fixed** — both call `verify_meta!`; a tampered record now fails before any metadata is rendered. Spec added for request preview. Residual: v3 HEAD→GET still marks `previewed` on an unfurl (no consume, no plaintext) — accepted housekeeping, documented. |
| SA-30 | S4 | **Revealed request links were replayable.** Reveal deleted only the submission and the owner-index member; `request:object:*` survived to TTL, so a link holder could submit again and have the owner reveal a second secret. | `secret_requests.rb:113`, `secret_request.rb#cleanup` (pre-fix) | **Fixed** — `SecretRequest.retire` deletes the request object after the atomic consume, best-effort and counted like other cleanup; preview/submit/reveal all become 404. Red→green spec added. |
| SA-31 | S4 | **Documentation overclaimed / drifted.** Spec counts (180 vs 222), limiter scope count, "legacy v1 records still reveal until TTL", SA-23 marked open, and a stale `~= ''` Lua snippet advertising the closed SA-20 escape hatch. | `SECURITY.md:7,54,60,116`, `SECURITY_AUDIT.md`, `DATABASE.md:98-99`, `CHANGELOG.md:108`, `docs/CRYPTO_SPEC.md:57-61` | **Fixed** — all corrected to match code; §7 and site copy still explicitly deny E2EE/zero-knowledge. |

Also re-verified as sound by the reviewers: fresh 128-bit salt + 96-bit IV per record with
HKDF-SHA256 (no nonce reuse), `secure_compare` length/type guards + `fixed_length_secure_compare`,
Argon2id m=64 MiB t=3 p=2, unconditional compare-and-delete consume, CAS rotation of secrets,
request submissions and webhook signing secrets, SCAN-only key iteration, and `AUTH_MODE=full`
→ 501 with no fallback. No new S1/S2 was found beyond SA-24.

### Evidence for this pass

- Baseline after the first pass: **222 examples, 0 failures** (seed 61395).
- Final after SA-24…SA-31: **228 examples, 0 failures** (seed 53404, 43.92 s) — full
  `bundle exec rspec` in `ots-dev` against throwaway Redis DB 15.
- Targeted batches: 24 examples / 0 failures (crypto, HEAD, requests); 37 examples /
  0 failures (config, requests, HEAD, crypto), both observed.
- `SECRET=<64 chars> REDIS_PASSWORD=dummy docker compose config --quiet` → OK.
- `stageshow` coordination still is `docs/security-posture.html` + `.png`; re-rendered in
  headless Chrome at 1030×560, 0 page errors, 70,431-byte PNG (still of the findings table,
  no E2EE claim).

### Remaining risks (not code defects fixed here)

1. **Operator:** TLS on a real hostname (T-70) and the Redis host firewall (T-71) remain open.
   The webhook worker must be scheduled (`bin/ots webhooks:work`) and its egress firewalled;
   `WEBHOOK_ALLOW_PRIVATE=true` disables the SSRF guard for local testing. `/metrics` has no
   scrape-network restriction and emits the exact version (minor info leak, SA-19).
2. **Product decisions:** none outstanding here — D-012b (per-secret budget) and D-retention
   (audit IPs) were closed in §14.1. Only the accepted preview existence oracle remains
   (128-bit IDs make it non-exploitable).
3. **Data integrity — FIXED AND VERIFIED (§14.2):** backups export `schema:version`, validate
   and bound it in pre-flight before any key is written, and stamp it last. A corrupt or future
   marker is rejected with no keys written; the isolated restore drill proves the round trip.
4. **Operational (new, open):** no restore drill has been run against a live instance; backup
   coverage is complete but unverified end to end (SA-22).
5. **Accepted by design:** the instance `SECRET` alone decrypts every unexpired record,
   including passphrase-protected ones — this is why §7 forbids E2EE/zero-knowledge claims.

## 14. Pre-launch remediation (2026-11-21, second directive)

This section records the follow-up that closed the data-integrity and exposure findings above,
implemented the two outstanding decisions with ₹0 budget, and reviewed the protected paths.
No commit, push, deploy, or production restore was performed.

### 14.1 Decisions closed (secure, zero-budget defaults)

- **D-012b — per-secret passphrase budget.** Reused the existing Redis Lua limiter with a new
  `passphrase` scope keyed by the opaque secret id. Default 5 guesses over a dedicated
  `RATE_LIMIT_PASSPHRASE_WINDOW` of 900 s (the general HTTP window is 60 s, which an attacker
  could simply outwait). Only protected records consume the budget; exhaustion is `429` with
  `Retry-After` and the record remains readable. No new gem, service, or paid tier. Recorded in
  `docs/DECISIONS.md`.
- **D-retention — no raw IPs.** `Audit.record` stores `ip_day`, the first 12 hex chars of an
  HMAC-SHA256 keyed by a `SECRET`-derived, daily-rotating salt. No raw IP is persisted;
  same-day correlation survives, cross-day correlation does not. Recorded in `docs/DECISIONS.md`.

### 14.2 Backup schema versioning and verified round-trip

`Backup.export` now records `schema_version` from `Migrate.current_version`; `Backup.restore`
validates and bounds it (0…`Migrate::TARGET_VERSION`) **during pre-flight, before any key is
written**, includes the marker in the overwrite/refusal check, and stamps it last. Format 2 is
unchanged for older readers (an unknown field is ignored). Specs: round-trip preserves the
marker and a future/corrupt marker is rejected with no keys written. This closes the data-integrity
risk in §13.3.

**Isolated restore drill (evidence):** `script/restore-drill.sh` starts its own throwaway Redis
container on loopback port 6413, seeds a live and a consumed secret, exports via `bin/ots backup`,
flushes **only** that instance's DB 15, restores via `bin/ots restore`, and asserts:

```
live=drill-live-payload
spent=GONE
schema=1
migration_pending=no
RESTORE DRILL PASSED (isolated instance; no production data touched)
```

This proves the tooling and round trip; it is **not** a production restore (H6 remains human).

### 14.3 Metrics exposure closed

`GET /metrics` is now a closed 404 unless both `METRICS_ENABLED` and a configured `METRICS_TOKEN`
are present; the whole `Authorization: Bearer …` header is compared with
`Crypto.secure_compare`. Authorized scrapes use a dedicated `:metrics` limiter (default 5). The
exact build version was removed from the exposition, closing SA-19's fingerprint. Integration and
unit specs cover no-token, wrong-token, authorized scrape, rate limiting, and absence of
`onetime_version_info`.

### 14.4 Webhook worker scheduling (free infrastructure)

`script/webhook-worker.sh` is a one-shot drain for host cron/systemd: non-blocking `flock`
prevents overlap, it refuses to run with `WEBHOOK_ALLOW_PRIVATE=true`, and it passes no secret in
argv. `docs/ops/webhook-worker.md` carries cron and systemd units, a default-deny egress example
and verification steps. No new service or paid queue is introduced. **Scheduling and monitoring
on the target remain a server-operator action (K-46).**

### 14.5 Protected-path review (requirement 7)

The current diff of the three flagged files was re-read in full:

| Path | Review finding |
| --- | --- |
| `lib/onetime/crypto.rb` | Only change is the unconditional `cipher` allow-list in `decrypt`. AEAD key/IV/tag handling and the encrypt path are untouched; tampering maps to a typed integrity error. No regression found. |
| `lib/onetime/web/app.rb` | Header consolidation, strict JSON media type, redacted audit references, metadata MAC on previews, independent limiter scopes, CSRF/origin checks and the `/metrics` token gate. The one-time reveal still runs verify → decrypt → atomic consume; no auth bypass or secret/key in logs. No regression found. |
| `compose.yaml` | Loopback-only publish, `TRUST_PROXY=true` with loopback-only trusted proxies, `REDISCLI_AUTH` healthcheck, and pass-through of every new limiter/metrics variable. `client_id` still refuses XFF unless the direct peer is trusted, so exposing the port cannot enable spoofing. No regression found. |

These are reviewed by an agent, **not approved**: explicit human sign-off is recorded as
**REQUIRES HUMAN APPROVAL** in `GO_LIVE_REMINDER.md` and `RELEASE_CHECKLIST.md`.

### 14.6 Verification and launch classification

- Full backend suite after all changes: **239 examples, 0 failures** (seed 60654).
- Targeted backup/metrics batch: 30 examples / 0 failures.
- `bash -n script/webhook-worker.sh script/restore-drill.sh` → OK; isolated drill passed above.
- Every remaining item is classified in `GO_LIVE_REMINDER.md` / `RELEASE_CHECKLIST.md` as
  **FIXED AND VERIFIED**, **REQUIRES HUMAN APPROVAL**, **REQUIRES SERVER OPERATOR**, or **BLOCKED**.

**GO/NO-GO: NO-GO for public launch.** Code-level readiness is GO. T-70 (real TLS hostname) and
T-71 (host Redis firewall) have no target-host evidence, protected-path edits await human
approval, and K-46 is not scheduled. Webhooks must stay disabled until K-46 is closed. No live
restore or public TLS verification is claimed.

## 15. Third pass — five `.claude/` security agents in parallel (2026-11-21)

Five dedicated `.claude/agents/security-{crypto,auth,api,database,threat-model}.md` definitions
were added and run in parallel against the current tree. Each reported against source; no agent
edited files. Their dispositions:

| ID | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| SA-32 | S4 | **Request-link retirement was a TOCTOU.** Submission consume and `request:object` DEL were separate round trips; a concurrent answer could slip into the freed slot. | **Fixed** — one `Store.consume_request` Lua script compares the submission, deletes it **and** the object atomically; `Models::SecretRequest.consume_and_retire` replaces the two-step path. Spec injects a second answer inside the consume and asserts `Conflict`. |
| SA-33 | S4 | **Failed `/metrics` token guesses were free** and a weak token could be set at boot. | **Fixed** — `RATE_LIMIT_METRICS_AUTH` (default 5) throttles failed auth before the compare; `Config.validate!` rejects a `METRICS_TOKEN` shorter than 32 bytes when metrics are enabled. Specs added. |
| SA-34 | S4 | **Webhook deliveries GET scanned every delivery with no rate limit**, and shared the create bucket. | **Fixed** — dedicated `RATE_LIMIT_WEBHOOK_READ` scope on the listings route; red→green spec. |
| SA-35 | S4 | **Malformed `v` gave an untyped 500** (`to_i` on an attacker-supplied object/array). | **Fixed** — strict `is_a?(Integer)` check in `verify_meta!`; spec asserts `Onetime::Error`. |
| SA-36 | S4 | **Documentation drift** re-described D-012b and D-retention as open, and spec counts as 230/228; `ARCHITECTURE.md` called strict v2 enforcement a future option. | **Fixed** — `SECURITY_AUDIT.md` §6/§8/§13, `docs/DECISIONS.md` (D-012/D-014), `KNOWN_ISSUES.md`, `ARCHITECTURE.md`, `SECURITY.md`, `TASKS.md`, `AGENTS.md` corrected. |

**Disposition — version exposure (reported, not changed).** The API agent noted that the exact
`VERSION` is still returned by public `/health`, `/api/v3/config` and `/api/v3/openapi.json`
even though it was removed from `/metrics`. Those are documented response fields (API.md) and
OpenAPI requires `info.version`; gating them behind auth would break monitoring and the contract.
This is an **accepted, documented residual**, not a fix. Operators who do not want version
disclosure must not publish those endpoints publicly (they are behind the same TLS proxy).

Auth and database agents found **no new auth/data defects**; crypto found no new S1–S3. The
crypto, replay, enumeration, atomicity, expiration, secure-deletion and leakage guarantees from
§5 were re-verified. Also fixed during this round: an order-dependent spec leak (`SSL` in
`cli_api_spec.rb`) and a wrong CLI error-message assertion, both test-hygiene defects.

Verification: **258 examples, 0 failures** — run as two sequential batches (162 + 96) because
full-suite runs were intermittently OOM-killed on this host; all 26 spec files were executed.
`stageshow` still re-rendered at 1030×560 with 0 errors. No E2EE/zero-knowledge claim found.

## 16. Fourth-pass security audit (2026-11-21, current working tree)

Five parallel specialists (cryptography, authentication, API security, database/Redis, threat
modelling) audited the tree after the zero-cost decision pass. Every claim below was re-read
against source; no finding is inherited from agent prose without code evidence. IDs start at
SA-39 because §15 already used SA-32…SA-36.

### 16.1 Findings and dispositions

| ID | Sev | Finding | Evidence | Status |
|---|---|---|---|---|
| SA-39 | S2 | **CLI sent secrets in cleartext in the documented production topology.** `CliApi.base_url` always derived `http://` and ignored `SSL=true`, so `ots conceal`/`ots reveal` posted the plaintext secret to `secrets.example.com` before the TLS proxy. | `cli_api.rb:15-18`; `DEPLOYMENT.md:133-135` | **Fixed** — scheme derives from `Config.ssl?`, bare remote URLs default to `https://`, and plaintext to a non-loopback host raises unless `OTS_ALLOW_INSECURE=1`. Red→green specs in `cli_api_spec.rb` |
| SA-40 | S2 | **Rotation laundered tampered metadata.** `rotate_key.rb` re-signed records without verifying the old MAC, so a Redis writer could strip `passphrase_hash` and have rotation re-sign the unprotected record under the new key. | `rotate_key.rb:69-87,89-102` | **Fixed** — `verify_meta!` before re-signing for secret and request objects; tampered records are skipped. Red→green spec in `ops_spec.rb` |
| SA-41 | S2 | **Metadata MAC had no per-record binding.** A Redis writer could copy an unprotected donor's MAC-covered fields and MAC onto a protected record (keeping its ciphertext) and reveal it without the passphrase. Same transplant possible for request objects' `owner_id`. | `models/secret.rb:48,131-134`; `models/secret_request.rb:20` | **Fixed** — secret MAC v3 binds `ciphertext`; request MAC binds `request_key` and verifies it against the Redis key at every call site. Red→green specs in `security_hardening_spec.rb` and `requests_spec.rb` |
| SA-42 | S3 | **Backup restore was non-atomic.** A malformed entry `type` was discovered mid-restore, after earlier sections had overwritten live keys. | `backup.rb:82-96,182-209` | **Fixed** — `validate_entries!` pre-flight rejects unknown types and malformed payloads before any write. Red→green spec in `ops_spec.rb` |
| SA-43 | S4 | **`AUTH_MODE=full` only gated account routes.** Anonymous API routes still answered normally, contradicting the documented fail-closed contract. | `app.rb:476-481,522-527`; `AGENTS.md`; D-003 | **Fixed** — a single guard in the Roda `route` block returns `501 not_configured` for every `/api` path in full mode. Red→green spec in `secrets_api_spec.rb` |
| SA-44 | S4 | **Edge hardening drift:** four rate-limited routes lacked `429` in OpenAPI; preview routes accepted unbounded keys; `RATE_LIMIT_RESPOND`/`BURN` were absent from Compose; webhook queue was pruned only on claim. | `openapi.rb`; `app.rb:323-352,376-395`; `compose.yaml:60-73`; `webhook.rb:119-142` | **Fixed** — 429 entries added, capability-key validation shared by both previews, Compose pass-through, and pruning in `emit` as well as `claim`. |
| SA-45 | S4 | **Audit dropped-write counter is per-worker.** With `WEB_CONCURRENCY=2`, a scrape sees only one worker's in-memory count. | `audit.rb:58-67`; `metrics.rb:38-43`; `compose.yaml:77` | **Open** — documented limitation; making it a Redis counter would add a write to a best-effort path. Do not claim full fleet-wide alertability. |

### 16.2 Remaining risks (not fixed here)

- **Submission ciphertext is not AAD-bound to its request key** (`secret_requests.rb:78`, `crypto.rb:34`). A Redis writer can copy a valid submission from request A to request B and have B's owner decrypt A's answer. Requires Redis write access and an account on B (S4). Not changed: fixing it requires a submission-format version and rotation path.
- **Per-secret budget is also a recipient-DoS primitive**: a link holder can spend 5 guesses and lock the rightful reader out for 900 s. Availability only; no audit event is emitted on exhaustion (D-012b accepted the trade-off).
- **Audit IP digest has no time-based retention**, only `MAXLEN` (D-retention delegates the window to the operator).
- **Webhook endpoint metadata is unsigned** (`webhook.rb:73-85`); a Redis writer can redirect callbacks to an attacker-chosen public endpoint. Internal SSRF is still blocked; payloads are metadata-only.
- **Exact version is still served by unauthenticated `/health` and `/api/v3/config`** (`app.rb:103,155`) despite `/metrics` removing it. This is a deliberate compatibility trade-off that needs a recorded ruling; SA-19's claim is limited to `/metrics`.
- **Metrics best-effort counters are per-process** (SA-45); no fleet aggregation.
- T-70/T-71/K-46 remain operator actions; no public launch claim is made.

### 16.3 Evidence for this pass

- Red→green specs were observed for SA-39/40/41/42/43: targeted batches were red before each fix and green after.
- Full backend suite after these fixes: **258 examples, 0 failures** (exit 0, isolated Redis DB 15 in a persistent container). Earlier `docker run --rm` attempts were killed with exit 137 while other suites contended for the host; the accepted evidence is the clean run above.
- Red→green batches for SA-39/40/41/42/43: `cli_api_spec.rb` (6), `ops_spec.rb` (26), `security_hardening_spec.rb` + `requests_spec.rb` + `cli_api_spec.rb` (30), each observed failing before the corresponding fix.
- No E2EE or zero-knowledge claim was added; the passphrase remains an access gate under D-012.

## 17. Fourth-pass verification and fixes (2026-11-21, this session)

Five parallel specialists (cryptography, authentication, API, database/Redis, threat modelling)
were run again against the current tree, explicitly excluding SA-01…SA-45. Every finding below
was re-read against source; agent prose was not treated as evidence. **No agent edited files.**
The AEAD-transplant issue (SA-41) and the request-link consume/retire TOCTOU (SA-32) reported by
this round were already present as fixes in the working tree; the new spec for the transplant
locks the existing v3 binding rather than claiming a new fix.

### 17.1 Findings and dispositions

| ID | Sev | Finding | Evidence | Status |
| --- | --- | --- | --- | --- |
| SA-46 | S4 | **A queued webhook for a deleted endpoint resurrected a permanent delivery record.** `deliver` called `mark` for a missing endpoint; `mark` is HSET-only, so it recreated `webhook:delivery:<id>` with no TTL after teardown had deleted the hash. | `webhook.rb` (`endpoint.empty?` branch, `mark`); `delete_account.rb` | **Fixed** — return `:skipped` without writing when the endpoint is gone. Red→green: `spec/unit/webhook_spec.rb` ("does not resurrect a delivery record for a deleted endpoint") failed (`exists? == true`) before, passes after. |
| SA-47 | S4 | **`Backup.restore(force: true)` could downgrade `schema:version` to 0.** Once the marker exists `Migrate.apply!` uses `SET NX`, so a forced restore of an older export left migration permanently stuck and future migrations governed by a false marker. | `backup.rb#validate_schema_version!`, `migrate.rb#apply!` | **Fixed** — pre-flight rejects a marker below the live version before any write; fresh-instance restores still work. Red→green: `spec/unit/ops_spec.rb` ("refuses to stamp an older schema marker over a migrated instance"). |
| SA-48 | S2/S3 | **Webhook IP pinning was defeated for `http://` when the worker had `http_proxy`/`HTTP_PROXY` set.** `Net::HTTP.new(host, port)` defaults `p_addr = :ENV`; plain HTTP then connects to the proxy and sends an absolute-form URI, so the proxy re-resolves a rebound hostname and can reach internal addresses. `ipaddr` is consulted only on the direct socket path. | `webhook.rb#post`; Ruby stdlib `Net::HTTP#connect/#edit_path/#conn_address` | **Fixed** — `Net::HTTP.new(uri.host, uri.port, nil)` disables proxy discovery; the pinned IP always governs the socket. Red→green: `spec/unit/webhook_spec.rb` ("ignores an environment HTTP proxy…") failed with `ECONNREFUSED` to the proxy before, passes after. |
| SA-49 | S3 | **Unauthenticated meta routes were unthrottled.** `/health`, `/api/v3/health`, `/api/v3/config` and `/api/v3/openapi.json` issued Redis PINGs or built the full document with no rate limit — a zero-cost way to exhaust the 500k-command free-tier quota. | `app.rb` meta routes; `FREE_TIER_DEPLOYMENT_PLAN.md` quota table | **Fixed** — new `RATE_LIMIT_META` scope (default 300) boot-validated, passed through Compose/`.env.example`, applied to all four routes. Red→green: `spec/integration/web_spec.rb` ("rate limits unauthenticated meta routes…") got `200` before, `429 + Retry-After` after. |
| SA-50 | S4 | **CLI/worker processes skipped the fail-closed boot gate.** `Config.validate!` ran only in `config.ru` and `Cli.health`; a cron/CI worker with a bad `TRUSTED_PROXIES` CIDR or placeholder password ran normally. | `bin/ots`, `config.ru` | **Fixed** — top-level validation before dispatch for every command except `help`, `version` and the `health` diagnostic (which must report the failing check). Red→green: `spec/unit/cli_spec.rb` ("fails closed on invalid configuration…"). |
| SA-51 | S4 | **Security-significant admin CLI operations left no audit trail.** Rotation, backup, restore and migration wrote nothing to the append-only stream; only `set_role` did. | `bin/ots`, `audit.rb#EVENTS` | **Fixed** — `admin.migrated`, `admin.backup_exported`, `admin.restored`, `admin.key_rotated` and `webhook.worker_run` events with counts/status only (never paths, keys or endpoint ids). Red→green: `spec/unit/cli_spec.rb` (admin audit + worker attribution). |
| SA-52 | S3 | **The documented free-tier backup encryption command was invalid.** `openssl enc -aes-256-gcm` fails with "AEAD ciphers not supported"; with `set -e` no encrypted backup was ever produced, removing the only mitigation for non-durable free Redis. | `FREE_TIER_DEPLOYMENT_PLAN.md`, `INFRASTRUCTURE_SECURITY.md`; observed `openssl enc` failure | **Fixed** — document GPG symmetric AES-256 with the passphrase piped on stdin (integrity-protected, no passphrase in argv). Red→green: `spec/unit/security_docs_spec.rb` fails while the invalid command is present and passes after; the GPG recipe was executed locally (encrypt → MAC/decrypt round trip). |

### 17.2 Additional verified fixes from this session

- A rotation regression introduced by the v3 MAC work was repaired: `rotate_key.rb` was passing
  the full Redis key (`request:object:<id>`) to `verify_meta!`, which now binds the MAC to the
  bare request id. `spec/unit/ops_spec.rb` ("renews request-object MACs…") is green.
- The AEAD-transplant red spec in `spec/integration/security_hardening_spec.rb` passes against
  the current v3 field set (`v/kind/filename/owner_id/created_at/ttl/passphrase_hash/ciphertext`),
  proving a protected blob cannot be transplanted onto an ungated record.
- OpenAPI already documents `429` on the owner reveal route; no change needed.

### 17.3 Remaining risks (not fixed here)

1. **Operator-owned:** T-70 real-hostname TLS, T-71 Redis/provider isolation and K-46 worker
   scheduling are still unverified on deployed infrastructure. This audit does not close them.
2. **Worker credential scope (SA-43 residual):** the scheduled worker receives the instance
   `SECRET`, which can decrypt every record and run all admin CLI commands. Worker runs are now
   attributed, but true least privilege needs a derived per-worker key plus a Redis ACL limiting
   it to `webhook:*`. That is a data-format/rotation change requiring an explicit operator
   decision — deliberately not attempted here.
3. **Version exposure (accepted, §15):** `/health`, `/api/v3/config` and `/api/v3/openapi.json`
   still publish `VERSION`; the frontend `ConfigSchema` requires it and API.md documents it.
   Removing it is a contract change, not a silent security fix; SA-19's "fingerprint closed"
   wording is therefore narrowed to `/metrics` only.
4. **Submission/endpoint AAD binding (§16.2):** still open; fixing requires format versions and
   rotation paths, not a silent field change.
5. **No E2EE / zero-knowledge claim.** `crypto.rb` decrypts with `Config.secret!` under every
   path; the passphrase verifies an Argon2id gate (`password.rb`) and never derives a key. The
   accurate statement remains: AES-256-GCM at rest with an operator-held instance key, plus an
   optional passphrase access check. No evidence in this audit supports a stronger claim.

### 17.4 Verification evidence

- Baseline before fixes: **51 examples / 0 failures** (crypto + store + security hardening +
  secrets API) and a full-suite run showed **239 examples / 0 failures**.
- Each red spec above was observed failing before its fix: webhook resurrection (`exists? true`),
  backup downgrade (no error raised), proxy pin (`ECONNREFUSED` to proxy), meta routes (`200`),
  CLI config (`no config error`), admin audit (`events []`), doc gate (invalid cipher present).
- Final full backend suite after all fixes: **261 examples, 0 failures** (seeds 50553 and 35351), Ruby 3.3
  in `ots-dev` against Redis DB 15.
- `@stageshow` coordination still for this pass: `docs/security-fourth-pass.html` + `.png`,
  rendered 1030×560 with zero page errors; it states the E2EE non-claim on its face.

> The counts in §13 and §14 are historical snapshots of those passes. The current release count
> is recorded in §18 below.

## 18. Fifth pass — independent pre-release security + performance audit (2026-11-21)

Five `.claude/` specialists ran **simultaneously** on disjoint scopes: OWASP application review,
dependency/supply-chain scan, authorized local penetration test, performance/Redis profiling, and
infrastructure/crypto/data-handling review. Every finding was re-read against the source and, where
actionable, reproduced with a failing test by the main agent before a fix. Agent prose alone was
never treated as evidence. `@reverse-engineer-anything` was considered and deliberately not used:
its own routing rule says to use normal repository tools for a complete source repository, and no
competitor artifact was supplied. `@stageshow` was used for the product-engineering coordination
still (`docs/security-perf-posture.html` / `.png`).

### 18.1 Findings and dispositions

| ID | Sev | Finding | Evidence | Status |
| --- | --- | --- | --- | --- |
| SA-53 | S4 | **Reveal accepted an unbounded passphrase.** Create caps 8–256 bytes, but reveal passed any string to Argon2id and spent a guess slot; a ~1 MiB wrong guess cost ~500 ms and one of five 900-second attempts. | `app.rb:925,955`; `reveal_secret.rb`; `conceal_secret.rb:12-13` | **Fixed** — reveal mirrors `ConcealSecret::MAX_PASSPHRASE_BYTES` and returns `422 validation_error` before hashing or budget spend. Red (`401`) → green (`422` + correct passphrase still `200` with limit 1). |
| SA-54 | S4 | **Marketing CTA href sink.** `site/index.html` assigned the operator-editable `ots-app-url` meta value straight to `href`; a `javascript:` or protocol-relative value made the trusted CTA an XSS/open-redirect sink (the static site has no CSP of its own). | `site/index.html:30,344-352` | **Fixed** — only absolute `http(s)` URLs with a hostname are accepted, via `URL`, and only `origin + "/"` is assigned. New jsdom/Vitest regression was red (`javascript:...`) then green; brand sweep still clean. |
| SA-55 | S4 | **Backup restore could plant TTL-less receipts/deliveries.** The pre-flight TTL guard covered only secret/answer keys, so a tampered backup could make 30-day receipts and 7-day delivery records permanent (PII retention, not decryption). | `backup.rb` `validate_entries!` | **Fixed** — guard extends to `secret:receipt:*`, `webhook:delivery:*`, `webhook:queue`. Red (restore succeeded) → green (raises, no keys written). |
| SA-56 | S4 | **Root command injection in the host firewall helper.** `ADMIN_CIDR`/`REDIS_SUBNET` were interpolated into command strings and executed with `eval "$cmd"` under `--apply` as root. | `script/host-firewall.sh:68-79` | **Fixed** — both values must parse as IP networks (`python3 ipaddress`) before anything runs; `eval` removed, `ufw` called with quoted arguments. Verified: malicious CIDR exits 2 and creates no file; valid dry run unchanged; drift spec in `security_docs_spec.rb`. |
| SA-57 | S4 | **`METRICS_TOKEN` appeared in a process argument list** during `script/verify-deployment.sh`. | `script/verify-deployment.sh:48` | **Fixed** — `curl -H @-` reads the header from stdin; syntax checked and header delivery smoke-tested. |
| SA-58 | S4 | **Throwaway test Redis published on all host interfaces** (no password) in the SDK/dev harnesses. | `script/test-examples.sh:41`, `script/dev.sh:35` | **Fixed** — bind `127.0.0.1`. SDK example suite re-run green. |
| SA-59 | S4 | **Throwaway TLS private key created mode 0644** (inside a 0700 temp dir). | `script/tls-rehearsal.sh:65` | **Fixed** — key `0600`, certs `0644`; rehearsal re-run `PREFLIGHT PASSED (1 skipped)`. |

A measured hot-path inefficiency (not a vulnerability) was also fixed: `Webhook.emit` issued two
sequential Redis round trips on every owned conceal/reveal. It now pipelines queue pruning and the
owner-endpoint lookup; a red spec asserted the batch, and the full webhook suite (15 examples) is
green. Not re-benchmarked after the change — the claimed gain is one round trip per emit.

### 18.2 Authorization-tested local penetration test

The specialist exercised `http://127.0.0.1:3100` (`AUTH_MODE=simple`) with synthetic values only.
**No S1/S2/S3 and no critical exploitable issue was found.** Passphrase missing/wrong/non-string,
CSRF origin proofs, IDOR on receipts/requests/webhooks, header-spoofing rate-limit identity,
method override, traversal/static serving, body caps/media-type confusion, deep JSON, `__proto__`
keys, XSS reflection, credential-stuffing uniformity and `429`, cookie flags, HEAD semantics and
generic errors all behaved as documented. One S4 was reported: error responses on the live stack
lacked `Cache-Control: no-store`/`Pragma: no-cache`. Source and `web_spec.rb` already required them
(`app.rb` `apply_response_headers!` in the error handler), so the observation proved the **process
was stale**, not a code defect: after `docker restart ots-devrel-web`, a real 404 returned both
headers, and `web_spec.rb` was 16/16 green. The stale-process caveat is recorded in §18.5.

Documented intentional designs confirmed, not bugs: bearer link capabilities, headerless API
clients, `AUTH_MODE` gates, SPA fallback, absent CORS, and version fields on `/health`/`/config`.

### 18.3 Dependency and supply-chain posture

| Check | Command / result |
| --- | --- |
| Production gems | `bundler-audit check --update`: advisory DB 1406 commits, **No vulnerabilities found** (puma 7.2.3) |
| Frontend production | `npm --prefix frontend audit --omit=dev --audit-level=high`: **0 vulnerabilities** |
| Frontend full tree | 5 moderate in dev-only `@vue/test-utils → js-beautify → {editorconfig, glob → minimatch}`; no high; CI's `--audit-level=high` gate passes |
| e2e tree | 9 high in dev-only `puppeteer-core` 24.43.1 + transitives (`extract-zip`, `basic-ftp`, `zod` 3.25.76 in `chromium-bidi`, etc.). **Not exploitable here:** `puppeteer-core` does not download browsers (explicit system Chrome), no proxy is configured, `e2e/` is never copied into the image. A dated waiver is recorded in `KNOWN_ISSUES.md`; `npm audit fix --force` would be a semver-major upgrade requiring a full 8-journey re-run and a new decision. |
| Integrity | `npm ci --dry-run` reports both lockfiles up to date; all `resolved` URLs are `registry.npmjs.org`; only one install script (`esbuild`, canonical, build-time); GitHub Actions and the replica-skill clone are SHA-pinned |
| Open gaps | Mutable base-image tags (`Dockerfile`, `compose.yaml`, CI: **protected paths — proposed only**) and inert `npx @latest` MCP templates in the vendored ECC plugin (not enabled) |

### 18.4 Performance findings

Measured, cross-checked and documented in **`PERFORMANCE.md`**. Headline: plain conceal p50 11 ms,
passphrase conceal 573 ms, passphrase reveal 640 ms, `receipts` with 50 entries 53 ms (N+1),
Redis `SLOWLOG LEN = 0` throughout, all documented body/rate limits hold. Argon2id throughput is
~2 req/s on this single-worker staging stack and is flat under 1/5/10 clients; that is a security
parameter and a capacity plan, not a defect to silently tune. Static JS is 253,742 B with no
compression (80,967 B gzipped) — an operator/proxy decision. Gates not run locally (CI raised-limit
load test, `/metrics`, real-host TLS/firewall) are named in `PERFORMANCE.md` §6.

### 18.5 Verification evidence

- Backend: **303 examples, 0 failures** across all 30 spec files (one file per container because
  this host OOM-kills large RSpec processes; retry logic only, no test weakened).
- Frontend: **35 Vitest tests, 0 failures**; `vue-tsc --noEmit` and Vite build clean.
- Eight browser journeys green; axe gate 0 violations; SDK examples green; brand sweep `Clean.`;
  preflight self-test 5/5; TLS rehearsal `PREFLIGHT PASSED (1 skipped)`.
- Production image inspected: `User=ots`, no `SECRET`/password in image env or layer history;
  built JS has no source maps or secret strings.
- **No E2EE or zero-knowledge claim.** Passphrase is an access gate; `crypto.rb` decrypts with the
  operator-held `SECRET` under every path.
- Release verdict unchanged: code-level **GO**, public launch **NO-GO** until T-70/T-71 have
  target-host evidence and the human sign-offs in `RELEASE_CHECKLIST.md` are completed.

### 18.6 Supplemental skill-aligned checks

After reading `security-review/SKILL.md` and `web-perimeter-owasp-2025-audit/SKILL.md`, the OWASP
specialist re-checked its two findings and found no new code defect. Its "unchanged" line
references were stale: the current `reveal_secret.rb:29-32` enforces the byte ceiling and
`site/index.html:351-363` enforces the `http(s)` allowlist; both regression tests were re-run green
in this session (1 backend example, 3 jsdom examples). Additional clean static checks: CSP under
`app.rb:24-37` uses `script-src 'self'` with no `unsafe-inline`/`unsafe-eval`; no unkeyed-header or
CORS reflection sink exists in the code; the shipped `public/app/` tree has no source maps,
lockfiles or `.env`; HSTS and `Secure` cookies are conditional on `SSL=true` as documented. The
perimeter checklist's live probes (real TLS chain, CDN cache poisoning, deployed header
reflection, exposed dotfiles) were **not** performed — those are operator/edge gates, not claims
of compliance from this audit.

## 19. Independent pre-release audit (2026-11-21, third directive)

Six `.claude/` specialists ran **simultaneously** on disjoint read-only scopes: OWASP API
(`security-api`), encryption/data handling (`security-crypto`), auth/authz (`security-auth`),
infrastructure/secrets (`release-infra`), performance profiling (`performance-optimizer`) and
client-side security (`security-reviewer`). Every finding was re-read against the implementation
by the main agent; agent prose was never treated as evidence. `@reverse-engineer-anything` was
considered and deliberately not used: no competitor artifact was supplied and the repository is
a complete clean-room source tree. `@stageshow` was used for the coordination still
`docs/security-perf-independent.html` / `.png`.

### 19.1 Independently executed checks

| Check | Command | Result |
| --- | --- | --- |
| Ruby production gems | `bundler-audit check --update` in `ots-dev` | advisory DB 1406 commits; **No vulnerabilities found** |
| Frontend production | `npm --prefix frontend audit --omit=dev --audit-level=high` | **0 vulnerabilities** |
| e2e dev tree | `npm --prefix e2e audit --audit-level=high` | **9 high** in `puppeteer-core` 24.x transitives (`extract-zip`, `basic-ftp`, `chromium-bidi→zod`, proxy agents). Fix is semver-major 25.18.1; not shipped, no browser download, no proxy configured, `e2e/` excluded from the image. Waiver per §18.3 stands. |
| Lockfiles / integrity | `npm ci --dry-run`; install-script review | both up to date; only canonical `esbuild` postinstall |
| Live probe (authorized `127.0.0.1:3100`) | curl with `--path-as-is` | traversal, `.env`, `.git/HEAD`, `package.json` all return the SPA shell (`text/html`), not file contents; `HEAD /api/v1/secret/x` → 405; oversized body → 413; error 404 keeps `no-store`/`Pragma` |
| Built asset leakage | `find`/`grep` over `public/app` | no `.map`, `.pem`, `.key`, `.env`, lockfile or secret assignment; no forbidden E2EE claim (copy only *negates* it) |
| Compose | `SECRET=… REDIS_PASSWORD=… docker compose config --quiet` | valid (values are operator-supplied) |
| Concurrency soak | `ruby script/loadtest.rb 400 40` on an isolated throwaway stack | **400/400 secrets revealed exactly once**, 0 double reveals, 0 slowlog entries |

### 19.2 New findings and dispositions

| ID | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| SA-60 | S3 | Throwaway dev/SDK stacks run Puma with `--network=host`; `config/puma.rb` uses the `port` DSL, so `AUTH_MODE=simple` test apps bind `0.0.0.0` on the LAN (`script/dev.sh:38-44`, `script/test-examples.sh:48-55`). The companion Redis was loopback-bound in SA-58, but the app was not. | **Proposed only** — the fix belongs in `config/puma.rb` (a protected path): add a `PUMA_BIND` env with a `0.0.0.0` production default, then pass `PUMA_BIND=127.0.0.1` in both throwaway scripts. Needs operator approval. |
| SA-61 | S3 | Session cookie `ots_session` lacks the `__Host-` prefix. With an attacker-controlled sibling subdomain, an earlier `Domain=.example.com` cookie is sent first and Rack 3 keeps the first duplicate, shadowing the real host-only cookie → session fixation. Precondition: sibling-subdomain control (`app.rb:18,455-484`). | **Proposed only** — `app.rb` is a protected path. Fix: issue `__Host-ots_session` when `Config.ssl?` (browsers reject any `Domain` on `__Host-*`, and `Secure`/`Path=/` are already set); update the two cookie assertions. Needs operator approval. |
| SA-62 | S3 (conditional) | `script/webhook-worker.sh` used a predictable `/tmp/ots-webhook-worker.lock` with `exec 9>`; a local user could pre-create it or plant a symlink, and a root cron job could truncate the target. | **Fixed** — lock now defaults to `${XDG_RUNTIME_DIR:-<project>/tmp}/ots-webhook-worker.lock` in a `0700` directory with `umask 077`; `bash -n` clean. |
| SA-63 | S4 | Backup restore's TTL pre-flight omitted `request:object:`, so a tampered format-2 backup could plant an immortal request link (and its answer could inherit a fresh TTL). | **Fixed** — `request:object:` added to the key-namespace guard. Red (restore succeeded) → green (raises, no keys written). |
| SA-64 | S4 | `Password.verify` had no byte ceiling, so sign-in and two authenticated mutations could drive Argon2id with a ~1 MiB body (create-side paths already capped at 256). | **Fixed** — central `MAX_VERIFY_BYTES = 256` in `lib/onetime/password.rb`, covering sign-in, password change, account deletion and passphrase reveal. Red (257-byte matching value verified `true`) → green (`false`). |
| SA-65 | S4 | Key rotation re-encrypts webhook signing secrets before workers restart with the new `SECRET`; a decrypt failure is swallowed by the generic rescue, marks the delivery `:failed` and never re-queues, while `CLAIM_SCRIPT` already removed it — the event is lost. | **Residual / design decision** — make signing-secret decrypt failures retryable like the non-2xx branch, or rotate endpoint secrets after the key switch. Requires a delivery-state/data-shape review; not changed here. |
| SA-66 | S4 | `script/preflight.sh:33,243` interpolates unvalidated `REDIS_PORT` into `bash -c "/dev/tcp/$ip/$REDIS_PORT"`. | **Proposed only** — `script/preflight*.sh` is a protected path; validate numeric 1–65535 and drop `bash -c`. |
| SA-67 | S4 | `tls-rehearsal.sh` chmods only `srv.key` (leaves `ca.key` 0644) and mounts the whole workdir into Caddy; `preflight_selftest.sh` leaves `key.pem` 0644. All inside 0700 throwaway dirs. | Documented; low impact. `preflight_selftest.sh` is protected; `tls-rehearsal.sh` can be hardened later. |
| SA-68 | S4 | Authenticated GET list routes (`account/me`, `receipts`, `requests`, `webhooks`) have no rate-limit scope; a single client can repeatedly trigger the ~53 ms 50-item listing with no 429. | **Intentional design** (bounded lists, document says so) but a capacity consideration; adding a `:read` scope needs an API.md/OpenAPI contract update and a product decision. Not changed. |
| SA-69 | S4 | `Dockerfile:46` copies all of `script/` into the runtime image (dev/firewall/cert/restore helpers). No secrets, but unnecessary surface. | Proposed; `Dockerfile` is protected. |

No **S1, S2 or S3 defect in shipped code** remains unaddressed: the two S3s that are not code-owned
are recorded with concrete, approved-pending fixes, and the third was fixed.

### 19.3 Performance work in this pass

- `Webhook.emit` fetched each endpoint and wrote each delivery one command at a time: **1 + 4N**
  Redis round trips on every owned conceal/reveal. Endpoint hashes and all delivery writes are now
  each a single pipeline. A red spec (`1` batch for 3 endpoints) went green at exactly `3` batches
  (prune/read + fetch + writes) for any N; webhook suites **19 examples, 0 failures**.
- `Webhook.list` and `SecretRequest.list` replaced per-item `HGETALL`/`GET`+`EXISTS` with pipelines
  (50 rows previously cost 50 and 100 sequential RTTs); requests/unit index suites **18/0**.
- `script/loadtest.rb` opened a fresh TCP connection per request, had a dead `queue`, and
  mis-incremented `reveal_fail` for every key; it now reuses a thread-local connection and reports
  honest counters. The corrected soak still yields **400/400 exactly once**.
- Detailed measurements, including the deliberate Argon2id capacity ceiling and un-run gates, are
  in `PERFORMANCE.md` §8.

### 19.4 Verification and verdict

Backend **307 examples, 0 failures** (138 unit + 169 integration); frontend **35 Vitest tests,
0 failures**, typecheck and build clean; brand sweep `Clean.`; worker and load-test scripts pass
syntax checks. No production data, credential or public host was touched. Code-level acceptance is
**GO**; public launch remains **NO-GO** until T-70/T-71 have target-host evidence and the
protected-path fixes above (SA-60, SA-61, SA-66, SA-69) receive operator approval.
