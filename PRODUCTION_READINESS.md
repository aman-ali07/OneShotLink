# Production readiness

Status as of 2026-11-11. This file is deliberately stricter than "it runs": every
item is either **verified by a command**, **implemented but untested**, or **not done**.

## Verdict

The anonymous single-instance deployment (conceal → one-time reveal) is now packaged and
operable at production quality: fail-closed configuration, hardened headers, trusted-proxy
handling, redacted logs, bounded Redis timeouts, a non-root read-only container, persistent
Redis, health checks, and CI. Simple-mode accounts, opaque sessions, CSRF checks, owner
receipts, and the dashboard are implemented and covered by backend and browser tests. It is
**not** yet a production-grade multi-user product: several operational controls below are
still open, and full mode remains intentionally unimplemented.

Do not describe the project as "production ready" without the open items and the D-012
passphrase limitation being stated. Do not deploy with the default `AUTH_MODE=disabled` if
you need accounts — that mode has no accounts by design.

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

These are tracked in `TASKS.md`; they block a "production ready" claim, not local use.

| Item | Risk | Owner task |
|---|---|---|
| TLS termination + real hostname | HSTS/Secure cookies depend on `SSL=true`; no bundled TLS | T-70 |
| Redis auth/TLS and network policy | Redis is reachable only on the compose network, but has no password/TLS | T-71 |
| Backup/restore drill | AOF volume exists; no tested restore or documented RPO/RTO | T-72 |
| Metrics, tracing, alerting | Logs only; no latency/error/queue metrics | T-73 |
| Dependency and image scanning | No `bundler-audit`, `npm audit`, or image scan in CI | T-74 |
| Key rotation | Changing `SECRET` makes old secrets unreadable; no migration tool | T-65 |

| Auth audit trail / session revocation | Account events are not audited; password change does not revoke other sessions | K-34 |
| Load/soak test | Rate limiter and Redis behavior not tested at volume | T-76 |
| Incident runbook | No on-call procedures, key-compromise steps | T-77 |

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
