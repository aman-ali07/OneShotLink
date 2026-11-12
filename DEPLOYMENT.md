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
| `REDIS_URL` | no | `redis://127.0.0.1:6379/0` | Redis/Valkey connection URL; `rediss://` enables TLS |
| `REDIS_PASSWORD` | compose **yes** | — | Redis auth password; folded into the URL by `Config.validated_redis_url` and never logged |
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
| `PUMA_WORKER_TIMEOUT` | no | `60` | Seconds a worker may take to boot before Puma stops it (`config/puma.rb`) |
| `PORT` | no | `3000` | Puma bind port inside the container (`config/puma.rb`); Compose publishes `APP_PORT` |
| `RACK_ENV` | no | `development` | `production` in the image |
| `METRICS_ENABLED` | no | `false` | Serve `/metrics` (Prometheus text); `404` when off |

Two Compose-only variables are read by `compose.yaml`, not by `Config`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `APP_PORT` | `3000` | Host port published by Compose |
| `APP_BIND` | `0.0.0.0` | Host interface the port is published on. Use `127.0.0.1` when the TLS proxy runs on the same host, so the app port is not reachable from the internet |
| `REDIS_MAXMEMORY` | `256mb` | Redis memory ceiling. It is what gives `maxmemory-policy noeviction` meaning, and it is required for `onetime_redis_memory_used_ratio` to exist at all |

## Accounts and the CLI

Set `AUTH_MODE=simple` to expose `/signup`, `/signin`, `/signout`, `/dashboard`, and owner
receipts. With the default `disabled`, account routes return `403` and the anonymous
conceal/reveal flow is unchanged. `full` remains intentionally unimplemented (`501`).

Create a customer non-interactively (the password never appears in argv):

```bash
OTS_PASSWORD='a long unique password' \
  docker compose exec -e OTS_PASSWORD web ruby bin/ots customers create --email person@example.com
```

Or run `ruby bin/ots customers create --email ...` in an interactive terminal for a hidden
prompt. The full command set (all verified in the production container):

| Command | Purpose |
| --- | --- |
| `customers create --email EMAIL` | Create a customer |
| `customers reset-password --email EMAIL` | Set a new password **and revoke all sessions** |
| `customers list` | List customers (id, email, role) |
| `customers show --email EMAIL` | Show one customer |
| `customers set-role --email EMAIL --role customer\|admin` | Change role |
| `health` | Validate config, Redis, and stored-key count |
| `backup --out FILE` | Export encrypted records |
| `restore --in FILE` | Restore from a backup |
| `rotate-key` | Re-encrypt all secrets under `OTS_NEW_SECRET` |
| `version` | Print the version |

A password change from the UI **also revokes every other live session** and keeps the
caller signed in (verified); `reset-password` revokes all of them. The Redis session TTL
slides on activity; the browser cookie has a fixed `SESSION_TTL` max-age (default 14
days) and is `Secure` only when `SSL=true`.

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
export REDIS_PASSWORD="$(openssl rand -hex 24)"
export HOST=localhost:3000
docker compose up -d --build
curl -fsS http://localhost:3000/health
```

`compose.yaml` runs `web` and `redis`. Redis uses AOF (`appendfsync everysec`),
`maxmemory-policy noeviction`, and `requirepass` (auth is mandatory — set
`REDIS_PASSWORD`); the web container is read-only with `/tmp` as tmpfs. Set `APP_PORT` to
change the published port. Do not commit `.env`; inject `SECRET` and `REDIS_PASSWORD` from
your secret manager or shell.

```bash
docker compose ps
docker compose logs web
docker compose down          # keeps the redis-data volume
docker compose down -v       # deletes secrets and receipts — destructive
```

The Compose project is named `oneshotlink`, so every resource it creates is prefixed
`oneshotlink_`: the volumes `oneshotlink_redis-data` (Redis AOF) and `oneshotlink_backup-data`
(mounted at `/backups` for `bin/ots backup`), and the networks `oneshotlink_frontend`
(public plane) and `oneshotlink_backend` (internal, no gateway).
The project was renamed from its pre-R-09 working title (see `git log -p compose.yaml`); an
instance started before that rename keeps its data only if you address it by the old
project name (`docker compose --project-name <old-name> ...`). No data has been migrated by
the rename itself.

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

### 4.0 Redis network isolation (T-71)

Compose puts Redis on an **`internal: true`** network (`backend`) and publishes no port
for it. An internal Docker network has no gateway, so Redis has:

- **no egress** — it cannot reach the internet, so a compromise in Redis has no
  outbound exfiltration path;
- **no ingress** from outside that network — only `web` (the sole other member) can
  reach `redis:6379`.

`web` is attached to `backend` (to reach Redis) and `frontend` (which carries the
published port). Verified: from a container on an unrelated bridge network the Redis
port is unreachable, `nc` to `1.1.1.1:443` fails, and DNS does not resolve — while the
app still creates, reveals, and restores secrets normally.

**Residual risk the host must close.** Docker attaches the host to every bridge it
creates, so a process *on the host* can still route to the container IP. Redis still
requires `AUTH` there (`NOAUTH Authentication required` without the password), which is
defence in depth, but the host must block the path. The backend subnet is **fixed in
`compose.yaml`** (`REDIS_SUBNET`, default `10.77.13.0/24`) rather than auto-assigned, so
this rule keeps matching across redeploys; it sits outside Docker's default
`172.17.0.0/16`–`172.31.0.0/16` pool, so a dynamic network cannot take it.

```bash
# nftables: drop host -> backend Redis only (one narrow rule, no other traffic)
nft add table inet ots
nft add chain inet ots out '{ type filter hook output priority 0 ; policy accept ; }'
nft add rule inet ots out ip daddr "${REDIS_SUBNET:-10.77.13.0/24}" tcp dport 6379 drop

# ufw equivalent, if you use ufw instead of nftables
ufw deny out to 10.77.13.0/24 port 6379 proto tcp
```

Pick the form your host already uses (`systemctl is-active ufw` vs `nftables`). The bare
`nft add` above is **runtime-only**: on reboot it is gone unless you persist it
(`nft list ruleset > /etc/nftables.conf` plus `systemctl enable nftables`, or your distro's
equivalent). On a host that runs **ufw**, prefer the ufw form — ufw owns its ruleset and
saves it to `/etc/ufw/user.rules`, so it survives reboots without a second unit, and a
hand-rolled `nft` table can be lost the next time someone flushes or reloads nftables. To
revert either form: `nft delete table inet ots` or `ufw delete deny out to 10.77.13.0/24
port 6379 proto tcp`.

Verify it, rather than assuming it: `script/tls-rehearsal.sh --with-redis` runs the real
`script/preflight.sh` and prints `PASS host cannot reach Redis at 10.77.13.2:6379`. A host
process must still fail to connect (`nc -zv 10.77.13.2 6379` times out) while the app
keeps working (create → reveal → gone). On a ufw host, `ufw status numbered` must list
`10.77.13.0/24 6379/tcp DENY OUT`, and `grep 10.77.13 /etc/ufw/user.rules` must show the
`ufw-user-output` tuple — that file is what makes it survive a reboot.

If a cloud/provider network policy (Kubernetes NetworkPolicy, a VPC security group for the
Docker bridge subnet) is available, use that instead — the goal is the same: only the
`web` container may open `redis:6379`.

### 4.1 Verify TLS on the live domain (T-70)

Run the automated gate instead of the manual probes below:

```bash
HOST=https://secrets.example.com script/preflight.sh
```

It encodes every check in this section plus the Redis isolation checks, prints
`PREFLIGHT PASSED` and exits `0` only when all pass, and exits non-zero otherwise
(see `--help` for `--cacert`, `--resolve`, and `--skip-redis`).

> Two different `HOST`s: `script/preflight.sh` takes a **URL** (`https://secrets.example.com`),
> while the app's `HOST` in `.env` is **host:port with no scheme** — `Config.base_url`
> prepends it. Setting the app's `HOST` to a URL produces `https://https://…` links and a
> broken session cookie, so keep the two forms apart. Set
`PREFLIGHT_ALLOW_SIGNUP=1` to include the session-cookie check. The commands below
are kept as reference for what it checks:

```bash
H=https://secrets.example.com

# 1. HTTPS only, certificate chain valid
curl -sS -o /dev/null -w 'http=%{http_code} verify=%{ssl_verify_result}\n' "$H/health"
# expect: http=200 verify=0

# 2. HSTS present (requires SSL=true)
curl -sSI "$H/" | grep -i strict-transport-security
# expect: strict-transport-security: max-age=31536000; includeSubDomains

# 3. Session cookie is Secure + HttpOnly + SameSite
curl -sS -D- -o /dev/null -X POST "$H/api/v3/signup" \
  -H 'content-type: application/json' \
  -d '{"email":"probe@example.com","password":"correct-horse-battery-staple"}' \
  | grep -i set-cookie
# expect: ...; secure; httponly; samesite=lax

# 4. Plain HTTP redirects to HTTPS (the proxy terminates, not the app)
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' http://secrets.example.com/
# expect: 301/308 to https://...
```

**Rate-limit identity.** With `TRUST_PROXY=true`, confirm the proxy is overwriting (not
blindly appending) `X-Forwarded-For` and that `TRUSTED_PROXIES` lists the proxy CIDR. A
spoofed leftmost value must not create a new bucket — the app walks the header
right-to-left and stops at the first untrusted hop.

### 4.2 Deploy-day sequence (first go-live)

One pass, in order, on the real host. Every step ends in a check — do not move on
until it passes. If a step fails, stop: `/` and `/health` behaving differently on a
public hostname is usually DNS, the proxy, or `SSL`/`HOST` not being set.

**0. Prerequisites.** Docker + Compose on the host, ports 80/443 open, and a DNS
record already pointed at it (step 1 proves propagation, so create it first).

**1. DNS resolves to this host.**

```bash
dig +short secrets.example.com
# expect: the host's public IPv4 (and AAAA if you publish IPv6)
```

**2. Secrets and configuration.** Generate fresh values on the host and write them to
`.env` (never commit it; the values stay in that file):

```bash
printf 'SECRET=%s\nREDIS_PASSWORD=%s\n' \
  "$(openssl rand -hex 32)" "$(openssl rand -hex 24)" >> .env
```

Then set, in the same `.env`:

```ini
HOST=secrets.example.com          # no scheme; links and cookie flags follow it
SSL=true                          # HSTS, Secure cookies, https:// links
AUTH_MODE=simple                  # or disabled for a pure secret-sharing instance
TRUST_PROXY=true
TRUSTED_PROXIES=127.0.0.1/32      # the proxy's CIDR — nothing wider
APP_BIND=127.0.0.1                # proxy runs on this host
METRICS_ENABLED=true              # only if /metrics is not public-facing
```

Check: `docker compose config >/dev/null` (a YAML/interpolation error fails here, not at
boot) and `docker compose config | grep -c 'SECRET='` is not 0.

**3. Bring the stack up.** `docker compose up -d --wait`. The healthcheck gates startup,
so this returning 0 means Redis and the app are both healthy.

Check: `docker compose ps` shows `web` and `redis` both `healthy`; `curl -s
http://127.0.0.1:3000/health` returns `{"status":"ok","redis":"ok",...}`; `curl -s
http://<host-lan-ip>:3000/health` must **fail** — with `APP_BIND=127.0.0.1` the app port
is reachable from the proxy and nothing else.

**4. Terminate TLS.** nginx and Caddy both forward to `127.0.0.1:3000`; the app never
serves TLS itself. Minimal Caddy (`/etc/caddy/Caddyfile`):

```
secrets.example.com {
	encode zstd gzip
	reverse_proxy 127.0.0.1:3000 {
		header_up X-Forwarded-For {remote_host}
	}
}
```

Minimal nginx, with the body cap the app assumes:

```nginx
server {
	listen 443 ssl http2;
	server_name secrets.example.com;
	ssl_certificate     /etc/letsencrypt/live/secrets.example.com/fullchain.pem;
	ssl_certificate_key /etc/letsencrypt/live/secrets.example.com/privkey.pem;
	client_max_body_size 2m;
	location / {
		proxy_pass http://127.0.0.1:3000;
		proxy_set_header Host $host;
		proxy_set_header X-Forwarded-For $remote_addr;   # overwrite, never $proxy_add_...
		proxy_set_header X-Forwarded-Proto $scheme;
	}
}
server { listen 80; server_name secrets.example.com; return 301 https://$host$request_uri; }
```

Check: `curl -sSI https://secrets.example.com/ | grep -i strict-transport` → the HSTS
header from the app (if it is missing, `SSL=true` did not take effect or the proxy strips
it).

**5. Close the host path to Redis (T-71).** Apply the rule from §4.0 in the form your
firewall uses, then check it with the gate in step 6 rather than by eye.

**6. Run the go-live gate.**

```bash
HOST=https://secrets.example.com PREFLIGHT_ALLOW_SIGNUP=1 script/preflight.sh
```

It must print `PREFLIGHT PASSED` with `0` failures and exit 0. The cookie check creates a
throwaway account (`preflight-<ts>@example.invalid`); delete it afterwards with
`docker compose exec web ruby bin/ots customers list` /
`... set-role`, or leave it — it has no access. Rehearse this whole flow on a scratch
host first with `script/tls-rehearsal.sh --with-redis` (§4.0, `TESTING.md` §3.2).

**7. Prove a real secret round-trip on the public hostname.** In a browser: create a
secret with a passphrase, open the link in a private window from the LAN (wrong
passphrase rejected, secret preserved, correct passphrase reveals once, reload shows
gone). Automated equivalent:
`BASE_URL=https://secrets.example.com npm --prefix e2e test`.

**8. First backup, and prove it restores.** Backups contain ciphertext only, so a dump is
useless without `SECRET` — store it off the host and keep `SECRET` in the same secret
manager:

```bash
docker compose exec web ruby bin/ots backup --out /backups/dump.json
docker cp "$(docker compose ps -q web):/backups/dump.json" ./dump-$(date +%F).json
docker compose exec web ruby bin/ots health      # config + Redis reachable
```

Check the dump is non-empty and record its size; schedule it more often than your
shortest TTL (§6). A restore drill is `bin/ots restore --in FILE` on a scratch stack.

**9. Watch it.** Point your scraper at `/metrics` (§5.1) and alert on `onetime_up == 0`,
`onetime_redis_up == 0`, `/health` non-200, and Redis memory > 80% (the policy is
`noeviction`, so pressure means failed writes, not silent loss). Confirm one alert can
actually fire — a channel nobody has seen fire is not a channel.

**10. Record the deployment.** Tag the commit you deployed (`git tag -a deploy-$(date
+%F) -m "first go-live"`), note the deployed image digest, and keep `RUNBOOK.md` next to
the credentials: §1 `SECRET` compromise, §2 Redis loss, §3 double reveal, §4 lockout, §6
rollback.

After go-live, the two things that silently rot are the certificate (renewal) and the
Redis firewall rule (a host rebuild). Both are checked by `script/preflight.sh` — run it
after any change to the host, not only on day one.

## 5. Health checks

| Check | Expected |
| --- | --- |
| `GET /health` | `200` when the app can `PING` Redis; `503` otherwise |
| Compose `redis` healthcheck | `redis-cli ping` → `PONG` |
| Container `HEALTHCHECK` | curl `/health` with 3s timeout |

The health body must not include Redis URLs, keyspace counts, or configuration values.
The app returns `503` when Redis is unreachable, so a platform load balancer can remove it.

### 5.1 Metrics and alerting (T-73)

Set `METRICS_ENABLED=true` and scrape `GET /metrics` (Prometheus text format). It is off
by default because the series reveal traffic volume. Counters are per-process, so scrape
every worker, or scrape the load-balanced address.

Suggested alert thresholds:

| Alert | Expression | Meaning |
| --- | --- | --- |
| Redis down | `onetime_redis_up == 0` for 1m | The app cannot reach Redis; `/health` is 503 |
| Redis memory | `onetime_redis_memory_used_ratio >= 0.8` for 5m | `noeviction` means writes will start failing near the limit |
| Error rate | `rate(onetime_errors_total[5m]) > 0.05` | 5xx share rising |
| Latency | `rate(onetime_request_duration_seconds_sum[5m]) / rate(onetime_request_duration_seconds_count[5m])` | Mean latency per route family |

`family` is a fixed label set (`health`, `metrics`, `web`, `api_v1`, `api_v3_guest`,
`api_v3`, `other`), never a secret key, so cardinality stays bounded. Distributed
tracing is not included.

`onetime_redis_memory_used_ratio` is only exported when Redis has a `maxmemory` set
(`maxmemory_bytes` is otherwise `0` and the gauge is omitted, which would make the
docstring's alert silently unmatchable). Compose sets it via `REDIS_MAXMEMORY`; if you
run Redis outside Compose, set `maxmemory` there or alert on
`onetime_redis_memory_used_bytes` against the host's RAM instead.

## 6. Persistence and backup

- Redis AOF (`appendonly yes`, `everysec`) is the system of record; Compose mounts the
  `redis-data` volume.
- **Application-level backup (verified).** `bin/ots backup` exports every secret record,
  every receipt, and the customer records — all still encrypted under `SECRET` (no
  plaintext, sessions excluded) — to one JSON file. `bin/ots restore` loads it back,
  preserving each record's remaining TTL:

```bash
# The root filesystem is read-only; /backups is a writable named volume
# (backup-data) owned by the app user, so this path persists across restarts.
docker compose exec web ruby bin/ots backup --out /backups/dump.json
docker compose exec web ruby bin/ots restore --in /backups/dump.json

# Copy the dump off the host's Docker volume with docker cp:
docker cp "$(docker compose ps -q web):/backups/dump.json" ./dump.json
```

  `/backups` is writable because the image creates it owned by the app user, so the volume
  inherits that ownership on first use. Do not use `/tmp`: it is a tmpfs and is wiped on
  restart. If you write a dump outside `/backups`, read it back with
  `docker exec <web> cat <path> > dump.json` — `docker cp` cannot read from the tmpfs on a
  read-only container.

  Verified end to end: a deleted secret (HTTP `404`) decrypts again after restore.

- **RPO/RTO (measured):** schedule `bin/ots backup` more often than your shortest TTL
  (e.g. hourly) so the exposure window is bounded. A clean-volume drill measured RTO
  ≈ **12 s** locally (1.5 s backup + 10.5 s restart + 1.7 s restore for 81 secrets); see
  RUNBOOK.md.
- Keep the AOF-volume snapshot as a kernel-level backstop; the `bin/ots` export is the
  portable one because it does not depend on the Redis file format version.
- Backups contain ciphertext and Argon2id hashes only — useless without `SECRET`, and
  only a holder of the current `SECRET` can restore-and-read them. Encrypt at rest and
  restrict access. Sessions are deliberately **not** exported.
- `noeviction` prevents silent loss before TTL; monitor memory and alert at 80%.
- Losing Redis without a backup loses all unexpired secrets. Make that explicit to
  operators; see [RUNBOOK.md](RUNBOOK.md) §2.

## 7. Upgrades and rollback

1. Read [CHANGELOG.md](CHANGELOG.md); check for schema/`schema:version` changes (none yet).
2. Back up Redis (AOF/RDB) before upgrading.
3. Deploy the new image; health check must pass before routing traffic.
4. Rollback: redeploy the previous image tag. Redis data is backward compatible within
   v1; if a migration ran, restore the backup instead of downgrading blindly.

Image tags: `:dev`, `:vX.Y.Z`, and `:latest` for the newest stable. Pin a digest in
production.

## 8. Redis hardening (auth and TLS)

Redis is the system of record, so it must not be reachable unauthenticated.

- **Authentication (default in Compose, verified).** `compose.yaml` starts Redis with
  `--requirepass ${REDIS_PASSWORD}` and the web service receives the same value. The app
  folds it into the connection URL via `Config.validated_redis_url`; the password never
  appears in logs. Verified: `redis-cli ping` without the password returns
  `NOAUTH Authentication required.`; with it, `PONG`.
- **TLS.** Point `REDIS_URL` at `rediss://host:6380/db` when Redis terminates TLS
  (managed Redis/Valkey, or a stunnel sidecar). The scheme is validated at boot so a typo
  fails closed.
- **Network policy (operator).** Keep the Redis port off the public interface. In Compose
  it is already only on the internal network (no `ports:` mapping); on a host or
  Kubernetes cluster, restrict it with a firewall/NetworkPolicy. This is the one part of
  Redis hardening that lives outside the repository.

## 9. Scaling and constraints

- The app is stateless; scale horizontally behind the proxy. All instances must share one
  Redis (sessions and secrets are not replicated).
- Rate limits are per Redis, not per instance — good.
- A single Redis is a single point of failure. Sentinel/Cluster is out of scope. The
  outage behaviour is: `/health` and every Redis-backed route answer `503
  service_unavailable` with `Retry-After`, and they recover without a restart — an outage
  is never reported as a generic `500`.
- **When Redis reaches `maxmemory`** (with `noeviction`) every write is rejected with the
  same `503`, and so is every reveal — the atomic consume is a Lua `EVAL`, which Redis
  refuses to run at the ceiling. Nothing is lost: measured on a 6 MB stack, the write that
  crossed the ceiling got `503` + `Retry-After: 5`, and the earlier secrets revealed
  normally once `maxmemory` was raised. Note that TTLs keep running while storage is full,
  so a secret can expire before the operator frees space — alert on the ratio below 0.8 to
  make that window unreachable in practice. Runbook: [RUNBOOK.md](RUNBOOK.md) §2b.
- **Sizing the ceiling.** Measured on the default 256 MB: a 200-secret load test (161
  creates/s) left Redis at 1.36 MB, i.e. ~7 KB per small secret, so 256 MB holds roughly
  35,000 live secrets. Secrets approach the 1 MiB cap when they are large, so size it as
  `expected live secrets × typical size`, and re-check on the real host rather than trusting
  this ratio.
- Long secrets and high TTLs dominate memory; cap `MAX_SECRET_BYTES` and `TTL_OPTIONS`.

## 10. `SECRET` rotation

In-place rotation is supported and non-destructive (verified). The `rotate-key` command
re-encrypts every stored secret from the current key to a new one, preserving each
record's remaining TTL:

```sh
NEW=$(openssl rand -hex 32)
docker compose exec -e OTS_NEW_SECRET="$NEW" web ruby bin/ots rotate-key
# then set SECRET=$NEW in the environment/secret manager and restart web:
docker compose up -d --force-recreate web
```

After rotation, a secret created before the change still decrypts under the new key, and
the old key can no longer decrypt it (`spec/unit/ops_spec.rb` asserts both directions).
Rotation protects data **at rest going forward**; anything already decrypted is not
un-disclosed. See [RUNBOOK.md](RUNBOOK.md) §1 for the compromise playbook.

## 11. Full mode (not supported)

`AUTH_MODE=full` is reserved for PostgreSQL 17 + RabbitMQ 4.3 + Rodauth. No such services
are wired, and the API returns `501 not_configured`. A `docker-compose.full.yml` may be
added as documentation only (T-53); it must not be presented as working.
