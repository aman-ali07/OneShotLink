# Security

This document separates **controls that exist and have been exercised** from **controls
that must still be implemented**. Nothing here is a claim that the system is fully
production-ready: there is no bundled TLS terminator and simplified accounts intentionally
omit full-mode features. The secret lifecycle, simple-mode accounts, UI, hardened
container, and Compose stack are implemented and covered by 307 backend specs, a live Puma run,
eight headless-browser journeys, and a container smoke test. The 2026-11-21 hardening pass
and its evidence are recorded in [SECURITY_AUDIT.md](SECURITY_AUDIT.md).

## Reporting a vulnerability

**Do not open a public GitHub issue for a security vulnerability**, and do not disclose a suspected
issue publicly (discussions, PRs or social media) before it is addressed. Report it privately via
GitHub's confidential vulnerability reporting for this repository:
<https://github.com/aman-ali07/OneShotLink/security/advisories/new>.

> Maintainer action required before public release: enable "Private vulnerability reporting" in
> repository Settings → Security (or publish a maintainer-owned security contact) and set a
> response-time expectation. No contact address is invented in this document.

Include the affected commit/version, reproduction steps and impact. If you observed it on a live
stack, include the `X-Request-Id` from the response. **Never send real secrets, passphrases,
tokens, ciphertext or `.env` contents** — use synthetic values. Supported versions: pre-alpha;
fixes target the latest `main`, with no backports. Coordinated disclosure follows a released fix.

Scope note: TLS on a real hostname (T-70) and per-host Redis isolation (T-71) are operator
responsibilities, not repository defects; see [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md).
A passphrase is an access gate, not a second encryption key — "zero-knowledge" is explicitly out
of scope (D-012). Ordinary bugs (not vulnerabilities) can be filed as public issues with an
`X-Request-Id` and `script/verify-deployment.sh` output.

## 1. Assets and trust boundaries

| Asset | Where it lives | Must never |
| --- | --- | --- |
| Secret plaintext | Request → process memory → response | Touch Redis, logs, analytics, or the URL |
| `SECRET` | Process env | Be committed, logged, baked into an image, or stored in Redis |
| Passphrase | Request body → Argon2id hash | Be logged, stored plaintext, or put in a query string |
| Session token | `HttpOnly` cookie + `session:<sha256(token)>` | Appear in JSON, logs, or localStorage; Redis stores only the digest |
| Secret key (`objid`) | URL path | Be sequential, guessable, or reused |
| Ciphertext | Redis/backups | Be treated as non-sensitive (it is still data) |

Trust boundaries: browser ↔ TLS proxy ↔ Puma; Puma ↔ Redis. Redis and backups are
inside the trust boundary but are assumed readable by an attacker only together with
`SECRET` (which is not stored there).

## 2. Implemented controls

| Control | Implementation | Status |
| --- | --- | --- |
| AES-256-GCM at rest with per-record random IV/salt | `lib/onetime/crypto.rb` | Verified by unit + at-rest integration specs |
| HKDF key derivation; `SECRET` ≥ 32 bytes enforced | `Config.secret!`, `Crypto` | Verified: boot exits 1 on a short secret |
| Constant-time token comparison | `Crypto.secure_compare` | Verified by unit spec |
| Atomic one-time consume (compare-and-delete Lua) | `Store.consume` | Verified: 8-way race yields exactly one `200` |
| Verify-before-consume passphrase gate | `RevealSecret` | Verified: wrong passphrase `401`, record intact, then correct reveal |
| Opaque identifiers (128-bit CSPRNG) | `Ids.extid` | Verified by unit spec |
| Argon2id password hashing + bcrypt legacy verify | `lib/onetime/password.rb` | Verified; K-03 resolved. `Password.verify` caps input at 256 bytes (SA-64) so sign-in and credential mutations cannot drive Argon2id with a ~1 MiB body |
| Fixed-window rate limiter in Lua | `lib/onetime/limiter.rb`, `app.rb` | Verified: `429` + `Retry-After` integration spec |
| Generic 404 for expired/consumed/unknown | `Onetime::NotFound` | Verified over HTTP |
| `Cache-Control: no-store` + nosniff/frame/referrer headers | `lib/onetime/web/app.rb` | Verified by live curl and spec. `apply_response_headers!` runs on the route **and** the error path, so 4xx/5xx (including a consumed-link 404) keep `no-store`/`Pragma` and HSTS |
| Strict CSP, HSTS under `SSL=true`, COOP/CORP, Permissions-Policy | `app.rb` constants | Verified by spec and live `curl -I`; browser journey passes under CSP |
| Boot validation fails closed | `Config.validate!`, `config.ru` | Verified: missing/short `SECRET`, bad TTL/auth/proxy config exit 1 |
| Trusted-proxy-only `X-Forwarded-For` | `App#client_id`, `TRUSTED_PROXIES` | Verified by integration specs (spoof ignored, trusted hop honored) |
| Redacted request logs | `Web::RequestLogger` | Verified: secret keys absent; only method/path/status/duration/request ID |
| Bounded Redis timeouts and reconnect | `Store.redis` env config | Verified live: with Redis stopped, `/health` → `503 degraded`, writes → `503` + `Retry-After`, and the instance recovers without a restart |
| Non-root, read-only container with no secrets | `Dockerfile`, `compose.yaml` | Verified: UID 10001, read-only rootfs, no `.env` in image |
| Input limits: TTL allowlist, `MAX_SECRET_BYTES` cap, passphrase 8–256 bytes (an empty string means none); the body actually read is capped on both the JSON and the form path | `ConcealSecret`, `App#read_body_within_limit!` | Verified: exact boundary accepts N and rejects N+1 (`413`); a 7-byte passphrase is `422` and writes nothing, 8 bytes is accepted and enforced (D-014, T-47); a chunked form body with no `Content-Length` is refused with `413` and writes nothing (K-37) |
| Error hygiene: no stack traces/Redis errors, request ID only | `app.rb` error handler | Verified by 404/500 paths. A Redis outage answers `503 service_unavailable` + `Retry-After` on both API versions (never a `500`, never the driver's message) |
| No auto-reveal on page load, and no GET consumes a secret (link previews are safe) | `RevealView.vue`, `app.rb#peek_payload` | Verified in the browser and over HTTP: `GET /api/v3/guest/secret/:key` answers metadata only, three GETs in a row leave the key intact, and only `POST …/reveal` consumes (K-35 resolved). The v1 GET is still destructive — that contract is frozen (API.md §4); `HEAD /api/v1/secret/:key` is refused with `405 Allow: GET, POST` so a rewritten HEAD cannot burn it (K-39) |
| No plaintext in URL, localStorage, or sessionStorage | SPA state only | Verified: `localStorage === "{}"` after create; URL contains only the key |
| No `v-html` for user content | SPA templates | Code review; CSP now blocks inline/third-party scripts |
| Argon2id customer passwords (bcrypt legacy verify then rehash) | `Models::Customer`, `Password` | Verified: no plaintext password in Redis; duplicate email cannot race |
| Opaque sessions with sliding TTL; SHA-256 Redis key | `Models::Session` | Verified: signout deletes the key; absent session is `401` |
| Session revocation survives an elapsed index TTL | `Models::Session::TOUCH_SCRIPT`, `revoke_all` | Verified: deleting only `customer:sessions:<id>` and then fetching the session restores the digest; password-change revocation still removes the other session (red → green spec) |
| Bounded webhook queue | `Webhook::QUEUE_TTL`/`DELIVERY_TTL` = 7 d (D-queue); `claim` prunes stale members atomically, deliveries expire; 3-attempt retry cap | Unclaimed events older than 7 d are dropped; operator must schedule `bin/ots webhooks:work` (K-46) |
| Public request capability | Recipient preview/respond are public links (C2) with `:reveal`/`:respond` rate limits, strict validation and `SET NX` single answer; owner create/list/reveal stay session-scoped | Anyone holding the 128-bit link can answer once, by design |
| Per-flow rate limits | `Config.rate_limit`, `app.rb#enforce_rate_limit!` | Verified: sixteen independent scopes (conceal/reveal/signin/signup/request/respond/webhook/webhook_read/password/delete/burn/signout/passphrase/meta/metrics/metrics_auth), each boot-validated; webhook, password, delete, burn and signout burst `429` in integration specs. The shipped loopback-proxy default trusts only local hops so per-IP limits do not collapse (SA-24) |
| Exact JSON media type and uniform hardening headers | `app.rb#parse_json_body`, `HARDENING_HEADERS` | Verified: `application/jsonp` → `422`; static assets carry CSP, nosniff, frame and referrer headers |
| Session cookie hardening | `set_session_cookie` | Verified: `HttpOnly`, `SameSite=Lax`, `Secure` when `SSL=true`, path `/` |
| CSRF proof for cookie-authenticated mutations | `App#verify_csrf!` | Verified: cross-site proof absent → `403 forbidden`; same-origin conceal creates an owner receipt |
| Login/signup origin proof | `App#verify_request_origin!` | `Sec-Fetch-Site: cross-site` or an `Origin` with a different scheme, host or port → `403` before any session cookie is set; headerless API clients (curl, CLI) still work. The expected origin is derived from operator-controlled `Config.base_url`, never Rack's `X-Forwarded-*`-derived `request.*`, so hostile forwarded headers cannot steer it (K-45) |
| Owner isolation | `Customer`, `Secret.owner_index`, receipts route | Verified: one customer cannot list another's receipts; reveal keeps a 30-day receipt only for the owner (D-017) |
| Owner burn (no decrypt, no disclosure) | `Logic::BurnSecret`, `App#burn_secret_payload` | Verified: session + CSRF proof + dedicated `RATE_LIMIT_BURN`; foreign key → uniform `404` with the payload intact; replay → `404`; the receipt gets only `status: burned` and a 30-day TTL, never the payload or key (D-017) |
| Endpoint-scoped webhook deliveries | `Webhook.owned?`, `Webhook.deliveries(id:)` | Verified: an unknown or foreign `:id` returns `404`, and one owner's two endpoints do not cross-list deliveries (B8) |
| Record metadata integrity (v3) | `Models::Secret.sign_meta!/verify_meta!` | Verified: stripping `passphrase_hash` or editing `filename`/`kind` in Redis makes reveal fail with no plaintext; v1/unsigned records are rejected outright (no legacy read window). Previews verify the same MAC before rendering metadata |
| Webhook SSRF guard | `Webhook.validate_endpoint`/`pinned_address`/`post` | Verified: the public IP is resolved and validated once, stored on the endpoint, and dialed via `Net::HTTP#ipaddr` so a rebinding DNS answer cannot redirect delivery; IPv4-mapped IPv6 is treated as IPv4 |
| Hash-field CAS for rotation | `Store.rewrite_hash_field_if_unchanged` | Verified by unit spec (match rewrites, mismatch does not) |
| Backup confidentiality and restore safety | `Backup.export`/`restore` | Verified: export is `0600`; restore refuses to overwrite live keys without `--force`, rejects keys outside the restorable namespaces, and (QA 2026-11-21) refuses secret-bearing entries whose TTL is zero **or missing**, matched by key namespace so a substituted file cannot re-file a secret under another section — a TTL-less record cannot round-trip into an immortal secret |
| Request-link key redaction | `Web::RequestLogger` | Verified: `/api/v3/requests/:key` and `/request/:key` are logged as `<redacted>` |
| Env-only configuration | `lib/onetime/config.rb` | Verified |

K-21 note: the passphrase is an **access gate**, not a second encryption key (D-012).
After the gate passes, the process can decrypt with `SECRET`. Do not claim
zero-knowledge or "the server cannot decrypt".

## 3. Controls status

| Area | Status |
| --- | --- |
| Transport | HSTS emitted when `SSL=true`; the app port is published on loopback by default (`APP_BIND=127.0.0.1`); operators must opt in to `0.0.0.0` when the proxy runs on another host (verified: LAN address refused, loopback answers). **TLS termination + real hostname is the operator's host (T-70), not bundled** — rehearsed end to end by `script/tls-rehearsal.sh` |
| Passphrase guessing | Per-IP reveal limiter **plus** a per-secret budget (D-012b): 5 guesses per 900 s window keyed by the opaque secret id, checked before the passphrase gate; wrong guesses never consume | Fixed window allows a boundary burst; a distributed attacker still gets 5 guesses per link per window |
| Redis auth/TLS | **Implemented:** `--requirepass` + `REDIS_PASSWORD` (verified `NOAUTH` without it), `rediss://` for TLS. Host path to the container is closed by a narrow firewall rule against the fixed backend subnet (T-71: applied and verified on the reference host; it remains a per-host operator action that must be repeated on every deployment) |
| Key rotation | **Implemented:** `bin/ots rotate-key` re-encrypts in place with a compare-and-swap, so a secret consumed mid-rotation is skipped, never resurrected (T-65, T-105, verified) |
| Dependencies | **Implemented:** `bundler-audit` + `npm audit` in CI; 0 high-severity vulnerabilities. `npm audit` reports 5 moderate findings in dev-only transitive packages of `@vue/test-utils` (D-016); they ship no runtime code. The dev-only e2e `puppeteer-core` tree carries 9 high advisories with an evidenced waiver in K-49 (no browser download or proxy path is used, and `e2e/` is not shipped); it is not part of the production dependency gate. |
| Backups | **Implemented:** `bin/ots backup`/`restore`, ciphertext-only, TTLs preserved; owner receipts and customer zsets/set indexes restored too (T-72, T-106); RPO/RTO documented |
| Audit logging | **Implemented:** append-only `audit:events` stream for account and reveal events; plus redacted, correlated request logs (K-34). No raw IP (D-retention): a 12-hex HMAC reference rotating daily replaces it; short-lived limiter keys remain the abuse control |
| Metrics/tracing | **Implemented (metrics):** Prometheus text at `/metrics` behind `METRICS_ENABLED` — request/error counters, duration, Redis up + memory ratio (T-73, verified live). **Open:** distributed tracing |

## 4. Invariants that must not regress

1. **One-time means one-time.** Reveal uses `Store.consume` only; no read-then-delete.
2. **Wrong passphrase does not consume.** Verify before the atomic delete.
3. **No plaintext persistence.** Only `Crypto.encrypt` output is written to Redis.
4. **No plaintext in responses except the single reveal payload.**
5. **No secret material in logs, errors, or request IDs.**
6. **Opaque IDs only.** No counters, timestamps, or email-derived keys in URLs.
7. **Fail closed.** Missing `SECRET`, Redis outage, or `AUTH_MODE=full` must error, not
   silently degrade.
8. **Unknown = 404.** Do not distinguish expired vs consumed vs never-existed. Burns and
   webhook delivery listings apply the same uniform 404 to foreign identifiers.
9. **Receipts never carry secret material.** Status and timestamps only; 30-day retention
   after reveal/burn (D-017). Never log the bearer key, passphrase, or ciphertext.
10. **Nothing irreversible happens before the work succeeds.** The passphrase check and the
   decryption both run *before* `Store.consume`. A wrong passphrase, a rotated `SECRET`, or
   a corrupt record must leave the record readable, never silently destroy it (verified: with
   a rotated key the reveal answers `500` and `EXISTS` stays `1`; after switching to the new
   key the same secret reveals).

## 5. Threat model (v1)

| Threat | Mitigation | Residual risk |
| --- | --- | --- |
| Link leaked before reveal | One-time reveal, short TTL, optional passphrase | Anyone with the link first wins |
| Brute-force secret keys | 128-bit IDs + reveal rate limit | None practical |
| Spam creation | Conceal rate limit + 1 MiB cap | Distributed IPs can still spam |
| Passphrase brute force | Argon2id + 8-byte floor (D-014) + per-IP reveal limit + per-secret budget (D-012b) | A fixed window permits bursts at its boundary; no permanent lockout by design |
| Race to reveal twice | Atomic Lua compare-and-delete | None known |
| Redis dump leaked | AES-256-GCM; key only in env | With `SECRET`, all unexpired secrets open |
| Log exfiltration | Redaction, IDs only, no bodies | Application bugs could still leak |
| XSS in UI | No `v-html` for user content, no plaintext in storage, strict CSP, same-origin scripts only | CSP did not break the verified browser journey |
| CSRF | SameSite=Lax + JSON-only + origin checks | Legacy browser behavior |
| Enumeration | Uniform 404s, opaque IDs | Timing differences (not measured) |
| `SECRET` rotation | Non-destructive in-place re-encryption: `bin/ots rotate-key` rewrites every record under `OTS_NEW_SECRET` and the old key stops working (T-65, verified live) | Rotation is operator-driven and needs a restart with the new `SECRET`; until it is done a leaked `SECRET` opens everything |
| Insider with Redis write access | v3 metadata MAC covers the passphrase gate, display fields and ciphertext; AEAD covers the value | v1/unsigned records are rejected; ciphertext alone is still decryptable with `SECRET` |
| Malicious webhook destination | Creation-time + stored-IP validation, IP-pinned delivery, no redirect following | `WEBHOOK_ALLOW_PRIVATE=true` disables the guard for local testing; egress firewall is the operator's (see SECURITY_AUDIT.md) |
| Insider with host access | Out of scope (env + memory readable) | Operator trust assumed |

Explicit non-goals: protection from a compromised client, screenshots, recipient
copy/paste, or an attacker who already has the link and the passphrase.

## 6. Secret handling rules for contributors

- Never print request bodies for `/api/v3/guest/conceal`, `/api/v3/guest/secret/:key` or
  `/api/v1/share` — not even in debug.
- Specs may use literal fixture strings like `"test-secret-value"`; that is not a real
  credential. Never paste real secrets into specs, issues, or docs.
- Do not add analytics, error reporting, or APM SDKs that capture request bodies without a
  redaction review.
- Do not log ciphertext either: it is not plaintext, but combined with a leaked `SECRET`
  it is directly decryptable.
- When debugging, log `objid`, status, and duration only.

## 7. Key management

- `SECRET` is generated with `openssl rand -hex 32` and supplied via the environment
  (Compose `.env`, secret manager, or orchestrator secret).
- **Rotation is non-destructive (T-65, verified live):** `bin/ots rotate-key` re-encrypts
  every `SECRET`-encrypted value under `OTS_NEW_SECRET`: secret records, in-flight secret
  request submissions and webhook signing secrets (receipts and customer records are not
  `SECRET`-encrypted). Each record's remaining TTL is preserved, then you set `SECRET` to the
  new value and restart the web process. After
  that the old key fails and the new one reads everything (verified: 21 secrets rotated, a
  pre-rotation secret still decrypts, the old key errors).
  While the web process still holds the *old* key, reveals of rotated records answer `500`
  and the record survives (`EXISTS` is still `1`) — so the rotation window is recoverable
  rather than destructive. Switch `SECRET` and restart immediately after rotating.
- Rotating *without* that tool — deleting and regenerating `SECRET` — makes every existing
  secret undecryptable. Do not do it; the CLI path exists. Run it from a host you trust with
  the new key, and keep the old `SECRET` nowhere afterwards (`RUNBOOK.md` §1).
- Never commit `.env`; it is git-ignored. Use `.env.example` with placeholders.
- Do not reuse the web session signing material: sessions are opaque Redis tokens, not
  signed with `SECRET`.

## 8. Incident response (minimum)

1. Contain: revoke the leaked `SECRET`, flush `session:*`, rotate proxy credentials.
2. Assess: which keys were readable, over what window; Redis/backup access logs.
3. Eradicate: patch the defect; add a regression spec that fails without the fix.
4. Recover: rotate `SECRET` (accepting loss of unexpired secrets), restore from a clean
   backup if data integrity is in doubt.
5. Document: add an entry to `CHANGELOG.md` and, if user-visible, a disclosure note.
