# Deployment

> **Status: production image and Compose stack built and smoke-tested (2026-11-11).**
> The container runs as UID 10001 with a read-only rootfs, two Puma workers, a persistent
> Redis volume, and a `/health` check. TLS, Redis auth, backups, and monitoring are still
> operator responsibilities listed in [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md).

## 1. Environment variables

All configuration is read from the environment by `lib/onetime/config.rb`. Values shown
are the code defaults; `SECRET` has no default and is required.

| Variable | Required | Default | Meaning |
| --- | --- | --- | --- |
| `SECRET` | **yes** | — | Instance-wide encryption secret; ≥ 32 bytes. `openssl rand -hex 32` |
| `HOST` | no | `localhost:3000` | Public host **including port**, used for links |
| `SSL` | no | `false` | `true` when behind TLS; makes links/cookies `https`/`Secure` |
| `REDIS_URL` | no | `redis://127.0.0.1:6379/0` | Redis/Valkey connection URL |
| `REDIS_TIMEOUT` | no | `5` | Connect/read/write timeout in seconds |
| `REDIS_RECONNECT_ATTEMPTS` | no | `2` | Reconnect attempts before surfacing an error |
| `AUTH_MODE` | no | `disabled` | `disabled` \| `simple` \| `full` (`full` → 501) |
| `UI_ENABLED` | no | `true` | Serve the built SPA |
| `TTL_OPTIONS` | no | `1800,43200,86400,259200` | Comma-separated TTLs in seconds |
| `DEFAULT_TTL` | no | `86400` | Must be a member of `TTL_OPTIONS` |
| `SESSION_TTL` | no | `1209600` | Session lifetime in seconds (14 days) |
| `RATE_LIMIT_CONCEAL` | no | `30` | Conceal requests per window per client |
| `RATE_LIMIT_REVEAL` | no | `60` | Reveal attempts per window per client |
| `RATE_LIMIT_SIGNIN` | no | `10` | Signup + signin attempts per window per client |
| `RATE_LIMIT_WINDOW` | no | `60` | Window length in seconds |
| `MAX_SECRET_BYTES` | no | `1048576` | Maximum secret payload (1 MiB) |
| `TRUST_PROXY` | no | `false` | Honor `X-Forwarded-For` **only** from `TRUSTED_PROXIES` |
| `TRUSTED_PROXIES` | no | empty | Comma-separated CIDRs of proxies allowed to set the client IP |
| `WEB_CONCURRENCY` | no | `0` (image sets `2`) | Puma workers; 0 runs a single process |
| `PUMA_MIN_THREADS` / `PUMA_MAX_THREADS` | no | `1` / `5` | Per-worker thread pool |
| `LOG_LEVEL` | no | `info` | `debug`\|`info`\|`warn`\|`error` |
| `PORT` | no | `3000` | Puma bind port (`config/puma.rb`) |
| `RACK_ENV` | no | `development` | `production` in the image |

## Accounts and the CLI

Set `AUTH_MODE=simple` to expose `/signup`, `/signin`, `/signout`, `/dashboard`, and owner
receipts. With the default `disabled`, account routes return `403` and the anonymous
conceal/reveal flow is unchanged. `full` remains intentionally unimplemented (`501`).

Create a customer non-interactively (the password never appears in argv):

```bash
OTS_PASSWORD='a long unique password' \
  docker compose exec -e OTS_PASSWORD web bin/ots customers create --email person@example.com
```

Or run `bin/ots customers create --email ...` in an interactive terminal for a hidden
prompt. `bin/ots customers reset-password --email ...` sets a new password; existing
sessions are not revoked in this build (K-34). The Redis session TTL slides on activity;
the browser cookie has a fixed `SESSION_TTL` max-age (default 14 days) and is `Secure`
only when `SSL=true`.
| `APP_PORT` | no | `3000` | Host port published by Compose |

`.env.example` contains placeholder values only. Never commit `.env`.

## 2. Docker image

Multi-stage build in `Dockerfile`:

1. `node:24-bookworm-slim` runs `npm ci` and `npm run build` for `frontend/`; the output
   lands in `public/app`.
2. `ruby:3.3-slim` installs gems without the test group into the bundle path.
3. The runtime stage installs only `curl`/`libssl3`, creates UID/GID 10001, copies the
   app and assets, drops privileges, exposes `3000`, and health-checks `/health`.

Runtime requirements: `SECRET` and reachable Redis. The image contains **no** secrets and
no `.env`; do not copy one into the build context.

## 3. Quick start (verified)

```bash
export SECRET="$(openssl rand -hex 32)"
export HOST=localhost:3000
docker compose up -d --build
curl -fsS http://localhost:3000/health
```

`compose.yaml` runs `web` and `redis`. Redis uses AOF (`appendfsync everysec`) and
`maxmemory-policy noeviction`; the web container is read-only with `/tmp` as tmpfs. Set
`APP_PORT` to change the published port. Do not commit `.env`; inject `SECRET` from your
secret manager or shell.

```bash
docker compose ps
docker compose logs web
docker compose down          # keeps the redis-data volume
docker compose down -v       # deletes secrets and receipts — destructive
```

## 4. Reverse proxy and TLS

- Terminate TLS at Caddy/nginx/Traefik and proxy to `web:3000`.
- Set `SSL=true` and `HOST=secrets.example.com` so generated links and cookie flags match.
- Do not expose port 3000 publicly without TLS: URLs contain secret keys.
- Set `TRUST_PROXY=true` and list **only** the proxy CIDRs in `TRUSTED_PROXIES`
  (for example `10.0.0.0/8,2001:db8::/32`). The app ignores `X-Forwarded-For` from any
  other address, so a direct client cannot spoof its rate-limit identity.
- The proxy should overwrite, not blindly append, forwarding headers.
- Cap request bodies at the proxy (for example nginx `client_max_body_size 2m`) in addition
  to the app's 1 MiB secret cap; the app also caps the bytes it actually reads for JSON.
- The app sets CSP, HSTS (when `SSL=true`), nosniff, frame-deny, no-referrer,
  Permissions-Policy, COOP, and CORP. Do not weaken CSP at the proxy.

## 5. Health checks

| Check | Expected |
| --- | --- |
| `GET /health` | `200` when the app can `PING` Redis; `503` otherwise |
| Compose `redis` healthcheck | `redis-cli ping` → `PONG` |
| Container `HEALTHCHECK` | curl `/health` with 3s timeout |

The health body must not include Redis URLs, keyspace counts, or configuration values.
The app returns `503` when Redis is unreachable, so a platform load balancer can remove it.

## 6. Persistence and backup

- Redis AOF (`appendonly yes`, `everysec`) is the system of record; Compose mounts the
  `redis-data` volume.
- A minimal backup/restore drill (not yet automated, T-72):

```bash
docker compose exec -T redis redis-cli BGSAVE
docker run --rm -v onetime-secret_redis-data:/data -v "$PWD":/backup alpine \
  tar czf /backup/redis-data.tgz -C /data .
# restore into a clean volume only after stopping web
```

- Backups contain ciphertext, Argon2id passphrase hashes, and (after M3) session tokens.
  Encrypt backups at rest and restrict access.
- Restoring a backup restores sessions too; flush `session:*` if the backup leaked.
- `noeviction` prevents silent loss before TTL; monitor memory and alert at 80%.
- Losing Redis loses all unexpired secrets. Make that explicit to operators.

## 7. Upgrades and rollback

1. Read [CHANGELOG.md](CHANGELOG.md); check for schema/`schema:version` changes (none yet).
2. Back up Redis (AOF/RDB) before upgrading.
3. Deploy the new image; health check must pass before routing traffic.
4. Rollback: redeploy the previous image tag. Redis data is backward compatible within
   v1; if a migration ran, restore the backup instead of downgrading blindly.

Image tags: `:dev`, `:vX.Y.Z`, and `:latest` for the newest stable. Pin a digest in
production.

## 8. Scaling and constraints

- The app is stateless; scale horizontally behind the proxy. All instances must share one
  Redis (sessions and secrets are not replicated).
- Rate limits are per Redis, not per instance — good.
- A single Redis is a single point of failure. Sentinel/Cluster is out of scope; document
  the outage behaviour (503 health, 500 API) for operators.
- Long secrets and high TTLs dominate memory; cap `MAX_SECRET_BYTES` and `TTL_OPTIONS`.

## 9. `SECRET` rotation

Rotating `SECRET` makes existing secrets undecryptable (there is no re-encryption tool,
T-65). Options:

- Drain: stop creating secrets, wait `max(TTL_OPTIONS)`, then rotate.
- Accept loss: rotate immediately, delete `secret:object:*` (they can only fail), keep
  sessions unless compromised.
- Future: add a re-encryption migration before supporting in-place rotation.

## 10. Full mode (not supported)

`AUTH_MODE=full` is reserved for PostgreSQL 17 + RabbitMQ 4.3 + Rodauth. No such services
are wired, and the API returns `501 not_configured`. A `docker-compose.full.yml` may be
added as documentation only (T-53); it must not be presented as working.
