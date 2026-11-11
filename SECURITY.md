# Security

This document separates **controls that exist and have been exercised** from **controls
that must still be implemented**. Nothing here is a claim that the system is fully
production-ready: there is no bundled TLS terminator and simplified accounts intentionally
omit full-mode features. The secret lifecycle, simple-mode accounts, UI, hardened
container, and Compose stack are implemented and covered by 68 specs, a live Puma run,
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
| Bounded Redis timeouts and reconnect | `Store.redis` env config | Configured in `Config`; health check reports Redis reachability |
| Non-root, read-only container with no secrets | `Dockerfile`, `compose.yaml` | Verified: UID 10001, read-only rootfs, no `.env` in image |
| Input limits: TTL allowlist, 1 MiB cap, passphrase 1–256; actual body read capped | `ConcealSecret`, `parse_json_body` | Verified (exact 1 MiB boundary still T-47) |
| Error hygiene: no stack traces/Redis errors, request ID only | `app.rb` error handler | Verified by 404/500 paths |
| No auto-reveal on page load (link previews cannot consume) | `RevealView.vue` | Verified by browser journey |
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

## 3. Required controls (not yet implemented)

| Area | Requirement | Task |
| --- | --- | --- |
| Transport | TLS termination, real hostname, `Secure` session cookies; HSTS is already emitted when `SSL=true` | T-70 |
| Passphrase guessing | Per-IP reveal limiter is the v1 control; no per-secret lockout (D-012) | Accepted for v1 |
| Redis auth/TLS | Compose keeps Redis off the public network, but it has no password/TLS | T-71 |
| Key rotation | Changing `SECRET` makes existing records unreadable; no re-encryption tool | T-65 |
| Dependencies | Lockfiles exist; no automated audit or image scan gate yet | T-74 |
| Backups | Redis AOF volume exists; no tested restore and no documented RPO/RTO | T-72 |
| Audit logging | Request logs are redacted and correlated; account events (signup/signin/password change) are **not** yet an audit trail | T-73 |

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

## 5. Threat model (v1)

| Threat | Mitigation | Residual risk |
| --- | --- | --- |
| Link leaked before reveal | One-time reveal, short TTL, optional passphrase | Anyone with the link first wins |
| Brute-force secret keys | 128-bit IDs + reveal rate limit | None practical |
| Spam creation | Conceal rate limit + 1 MiB cap | Distributed IPs can still spam |
| Passphrase brute force | Argon2id + IP reveal limit | Distributed guessing remains possible |
| Race to reveal twice | Atomic Lua compare-and-delete | None known |
| Redis dump leaked | AES-256-GCM; key only in env | With `SECRET`, all unexpired secrets open |
| Log exfiltration | Redaction, IDs only, no bodies | Application bugs could still leak |
| XSS in UI | No `v-html` for user content, no plaintext in storage, strict CSP, same-origin scripts only | CSP did not break the verified browser journey |
| CSRF | SameSite=Lax + JSON-only + origin checks | Legacy browser behavior |
| Enumeration | Uniform 404s, opaque IDs | Timing differences (not measured) |
| `SECRET` rotation | Documented as destructive | No re-encryption tool (T-65) |
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
- Rotating `SECRET` makes every existing secret undecryptable. There is no re-encryption
  path. Announce rotation, drain TTLs first, or add T-65 before rotating.
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
