# Production readiness

Status as of 2026-11-11. This file is deliberately stricter than "it runs": every
item is either **verified by a command**, **implemented but untested**, or **not done**.

## Verdict

The single-instance deployment (conceal → one-time reveal, optional simple-mode accounts)
is packaged and operable at production quality: fail-closed configuration, hardened
headers, trusted-proxy handling, redacted logs, bounded Redis timeouts, a non-root
read-only container, persistent Redis, health checks, dependency scanning in CI, an audit
stream, tested backup/restore, in-place key rotation, and a load-tested single-use
invariant. Simple-mode accounts, opaque sessions with revocation, CSRF checks, owner
receipts, and the dashboard are implemented and covered by backend and browser tests.

**All in-repo gates are closed**, including Redis authentication, network isolation, and
metrics. Two items remain that belong to the operator's infrastructure and cannot be
closed from the repository: **TLS termination** (T-70) and the **host-side firewall rule**
for Redis (T-71 — Compose now gives Redis an internal, egress-free network with no
published port; only a host process routing to the bridge IP is left). Until TLS is
configured on the host, do not call the deployment "production ready" in public copy, and
do not claim zero-knowledge (D-012).
Do not deploy with the default `AUTH_MODE=disabled` if you need accounts — that mode has
no accounts by design.

## Verified gates

| Gate | Evidence |
|---|---|
| Invalid deployment fails to boot | missing/short `SECRET`, bad `DEFAULT_TTL`, bad `AUTH_MODE`, malformed `TRUSTED_PROXIES` all exit 1 (`Config.validate!`) |
| Security headers on every response | CSP, HSTS only under `SSL=true`, nosniff, frame deny, referrer, permissions, COOP/CORP |
| Proxy spoofing ignored by default | `X-Forwarded-For` only honored when `REMOTE_ADDR` matches `TRUSTED_PROXIES`; integration specs cover both directions |
| Secret keys never logged | request logger redacts `/secret/:key` and `/api/v{1,3}/.../secret/:key`; unit spec asserts absence |
| Redis bounded | connect/read/write timeout + reconnect attempts from env; health endpoint checks `PING` |
| Multi-process safe | Puma cluster mode; Redis socket reset after fork; lifecycle verified with 2 workers |
| Container hardened | non-root UID 10001, read-only rootfs, `no-new-privileges`, only `/tmp` writable, no secrets in image |
| Data survives restart | Redis AOF `appendfsync everysec`, `maxmemory-policy noeviction`, named volume |
| CI gate | backend specs, Vitest + typecheck/build, container build, Compose lifecycle smoke, committed browser E2E |
| Dependency scanning | `bundler-audit` + `npm audit --audit-level=high` in the `security` CI job; both report 0 vulnerabilities. Fixed the findings: Puma 6.6.1→7.2.1 (2 high CVEs), zod 3→4.6.7 (1 high advisory) |
| OpenAPI published | `/api/v3/openapi.json` served; spec asserts every documented path is mounted and every `$ref` resolves |
| Session revocation | password change and `customers reset-password` revoke other/all sessions; verified live and by spec |
| Audit trail | append-only `audit:events` stream; identifiers only, never emails/passwords/secret values |
| Backup / restore | `bin/ots backup`/`restore`; verified live: deleted secret (404) → restored → decrypts; RPO/RTO documented |
| Key rotation | `bin/ots rotate-key`; verified live: 21 secrets rotated, pre-rotation secret still decrypts, old key fails |
| Load / single-use invariant | `script/loadtest.rb`: 400 secrets, 40 threads, 8-way race, 0 double reveals (~240 creates/s) |
| Incident runbook | `RUNBOOK.md` (key compromise, Redis loss, reveal regression, lockout, rollback) |
| Browser path | committed puppeteer journey (`e2e/journey.mjs`): create → reveal → gone and wrong/correct passphrase; zero console errors |
| Static delivery | hashed assets `Cache-Control: immutable`; shell and deep links `no-cache`/noindex; HEAD works for `/` and `/health` |

Commands used for the evidence above:

```sh
bundle exec rspec
npm --prefix frontend run typecheck && npm --prefix frontend run build
docker build -t ots-prod .
SECRET=$(openssl rand -hex 32) docker compose up -d --build
curl -fsS localhost:3000/health
docker compose exec web id          # uid=10001(ots)
```

## Open production items

These are the only two items left. Both are **infrastructure** that depends on the
operator's host and certificates, so they cannot be closed from the repository. They
block a public "production ready" claim, not local use.

Both are checked by one command that exits non-zero on any failure:

```bash
HOST=https://your.domain script/preflight.sh   # see --help
```

| Item | Risk | Owner task |
|---|---|---|
| TLS termination + real hostname | The **app side is verified**: behind a TLS terminator with `SSL=true`/`HOST`/`TRUST_PROXY`, HSTS, `Secure`/`HttpOnly`/`SameSite` cookies, HTTPS links, and XFF spoofing protection were all confirmed at runtime (and the negative controls with `SSL=false`). What remains is the operator's real hostname and certificate at the proxy — run the §4.1 checklist on the live domain. | T-70 |
| Redis network policy | Redis auth is enforced (`REDIS_PASSWORD`/`--requirepass`, verified) and TLS is available via `rediss://`. **Isolation is now in Compose:** Redis sits on an `internal: true` network with no published port, so it has no egress and is unreachable from other networks (verified). The remaining piece is the host-side rule that stops a host process from routing to the container IP — `AUTH` is enforced there, and DEPLOYMENT.md §4.0 has the nftables/ufw snippet. | T-71 |

Everything else that used to be listed here — backup/restore (T-72), dependency scanning
(T-74), key rotation (T-65), auth audit trail and session revocation (K-34), load/soak
(T-76), and the incident runbook (T-77) — is now implemented and verified; see the gates
table above.
## Accepted limitations (not bugs)

- **D-012:** a passphrase is an access gate, not a second encryption key. The server holds
  the instance key and can decrypt. This is a deliberate parity gap; do not claim
  zero-knowledge.
- **No file secrets in v1.** The record reserves `kind`/`filename`, but upload is not built.
- **No email delivery / expiration notices.** TTL expiry is Redis-only.
- **Visual parity is unmeasured** because no reference screenshots exist (K-22/K-30).

## Minimum deployment checklist

1. Generate `SECRET` with `openssl rand -hex 32`; store it in a secret manager, never in git.
2. Put the web service behind a TLS-terminating proxy; set `SSL=true`, `HOST`, and
   `TRUST_PROXY=true` plus the proxy CIDRs in `TRUSTED_PROXIES`.
3. Keep Redis private, enable auth/TLS where the platform supports it, and back up the
   `redis-data` volume.
4. Set `WEB_CONCURRENCY` and `PUMA_MAX_THREADS` to the host's capacity; leave Redis
   `maxmemory-policy noeviction` so secrets are never evicted early.
5. Configure log collection; confirm no `secret`/`passphrase`/`ciphertext`/key appears.
6. Run the lifecycle smoke test in CI or by hand after every deploy.
7. Record an explicit decision about D-012 and the open items above before calling the
   deployment production.
