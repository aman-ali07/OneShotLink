# Security

This document separates **controls that exist and have been exercised** from **controls
that must still be implemented**. Nothing here is a claim that the system is fully
production-ready: there is no bundled TLS terminator and simplified accounts intentionally
omit full-mode features. The secret lifecycle, simple-mode accounts, UI, hardened
container, and Compose stack are implemented and covered by 118 specs, a live Puma run,
two headless-browser journeys, and a container smoke test.

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
| Argon2id password hashing + bcrypt legacy verify | `lib/onetime/password.rb` | Verified; K-03 resolved |
| Fixed-window rate limiter in Lua | `lib/onetime/limiter.rb`, `app.rb` | Verified: `429` + `Retry-After` integration spec |
| Generic 404 for expired/consumed/unknown | `Onetime::NotFound` | Verified over HTTP |
| `Cache-Control: no-store` + nosniff/frame/referrer headers | `lib/onetime/web/app.rb` | Verified by live curl and spec |
| Strict CSP, HSTS under `SSL=true`, COOP/CORP, Permissions-Policy | `app.rb` constants | Verified by spec and live `curl -I`; browser journey passes under CSP |
| Boot validation fails closed | `Config.validate!`, `config.ru` | Verified: missing/short `SECRET`, bad TTL/auth/proxy config exit 1 |
| Trusted-proxy-only `X-Forwarded-For` | `App#client_id`, `TRUSTED_PROXIES` | Verified by integration specs (spoof ignored, trusted hop honored) |
| Redacted request logs | `Web::RequestLogger` | Verified: secret keys absent; only method/path/status/duration/request ID |
| Bounded Redis timeouts and reconnect | `Store.redis` env config | Verified live: with Redis stopped, `/health` → `503 degraded`, writes → `503` + `Retry-After`, and the instance recovers without a restart |
| Non-root, read-only container with no secrets | `Dockerfile`, `compose.yaml` | Verified: UID 10001, read-only rootfs, no `.env` in image |
| Input limits: TTL allowlist, `MAX_SECRET_BYTES` cap, passphrase 8–256 bytes (an empty string means none); the body actually read is capped on both the JSON and the form path | `ConcealSecret`, `App#read_body_within_limit!` | Verified: exact boundary accepts N and rejects N+1 (`413`); a 7-byte passphrase is `422` and writes nothing, 8 bytes is accepted and enforced (D-014, T-47); a chunked form body with no `Content-Length` is refused with `413` and writes nothing (K-37) |
| Error hygiene: no stack traces/Redis errors, request ID only | `app.rb` error handler | Verified by 404/500 paths. A Redis outage answers `503 service_unavailable` + `Retry-After` on both API versions (never a `500`, never the driver's message) |
| No auto-reveal on page load, and no GET consumes a secret (link previews are safe) | `RevealView.vue`, `app.rb#peek_payload` | Verified in the browser and over HTTP: `GET /api/v3/guest/secret/:key` answers metadata only, three GETs in a row leave the key intact, and only `POST …/reveal` consumes (K-35 resolved). The v1 GET is still destructive — that contract is frozen (API.md §4) |
| No plaintext in URL, localStorage, or sessionStorage | SPA state only | Verified: `localStorage === "{}"` after create; URL contains only the key |
| No `v-html` for user content | SPA templates | Code review; CSP now blocks inline/third-party scripts |
| Argon2id customer passwords (bcrypt legacy verify then rehash) | `Models::Customer`, `Password` | Verified: no plaintext password in Redis; duplicate email cannot race |
| Opaque sessions with sliding TTL; SHA-256 Redis key | `Models::Session` | Verified: signout deletes the key; absent session is `401` |
| Session cookie hardening | `set_session_cookie` | Verified: `HttpOnly`, `SameSite=Lax`, `Secure` when `SSL=true`, path `/` |
| CSRF proof for cookie-authenticated mutations | `App#verify_csrf!` | Verified: cross-site proof absent → `403 forbidden`; same-origin conceal creates an owner receipt |
| Owner isolation | `Customer`, `Secret.owner_index`, receipts route | Verified: one customer cannot list another's receipts; reveal removes the receipt |
| Env-only configuration | `lib/onetime/config.rb` | Verified |

K-21 note: the passphrase is an **access gate**, not a second encryption key (D-012).
After the gate passes, the process can decrypt with `SECRET`. Do not claim
zero-knowledge or "the server cannot decrypt".

## 3. Controls status

| Area | Status |
| --- | --- |
| Transport | HSTS emitted when `SSL=true`; the app port stays private with `APP_BIND=127.0.0.1` when the proxy runs on the same host (verified: LAN address refused, loopback answers). **TLS termination + real hostname is the operator's host (T-70), not bundled** — rehearsed end to end by `script/tls-rehearsal.sh` |
| Passphrase guessing | Per-IP reveal limiter is the v1 control; no per-secret lockout (D-012, accepted) |
| Redis auth/TLS | **Implemented:** `--requirepass` + `REDIS_PASSWORD` (verified `NOAUTH` without it), `rediss://` for TLS. Host path to the container is closed by one narrow firewall rule against the fixed backend subnet (T-71, applied and proven: the real preflight passes with 0 skips) |
| Key rotation | **Implemented:** `bin/ots rotate-key` re-encrypts in place (T-65, verified) |
| Dependencies | **Implemented:** `bundler-audit` + `npm audit` in CI; 0 vulnerabilities (T-74) |
| Backups | **Implemented:** `bin/ots backup`/`restore`, ciphertext-only, TTLs preserved; RPO/RTO documented (T-72, verified) |
| Audit logging | **Implemented:** append-only `audit:events` stream for account and reveal events; plus redacted, correlated request logs (K-34) |
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
8. **Unknown = 404.** Do not distinguish expired vs consumed vs never-existed.
9. **Nothing irreversible happens before the work succeeds.** The passphrase check and the
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
| Passphrase brute force | Argon2id + 8-byte floor (D-014) + per-IP reveal limit | Distributed guessing above the floor remains possible |
| Race to reveal twice | Atomic Lua compare-and-delete | None known |
| Redis dump leaked | AES-256-GCM; key only in env | With `SECRET`, all unexpired secrets open |
| Log exfiltration | Redaction, IDs only, no bodies | Application bugs could still leak |
| XSS in UI | No `v-html` for user content, no plaintext in storage, strict CSP, same-origin scripts only | CSP did not break the verified browser journey |
| CSRF | SameSite=Lax + JSON-only + origin checks | Legacy browser behavior |
| Enumeration | Uniform 404s, opaque IDs | Timing differences (not measured) |
| `SECRET` rotation | Non-destructive in-place re-encryption: `bin/ots rotate-key` rewrites every record under `OTS_NEW_SECRET` and the old key stops working (T-65, verified live) | Rotation is operator-driven and needs a restart with the new `SECRET`; until it is done a leaked `SECRET` opens everything |
| Insider with host access | Out of scope (env + memory readable) | Operator trust assumed |

Explicit non-goals: protection from a compromised client, screenshots, recipient
copy/paste, or an attacker who already has the link and the passphrase.

## 6. Secret handling rules for contributors

- Never print request bodies for `/secret` or `/conceal` endpoints — not even in debug.
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
  every secret, receipt and customer record under `OTS_NEW_SECRET`, preserving each record's
  remaining TTL, then you set `SECRET` to the new value and restart the web process. After
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
