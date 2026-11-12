# Deploy — OneShotLink

Date: **2026-11-11** · Commit: **856c399** · Go from user: **NOT YET**

This is the filled-in `preflight.md`, adapted for what this app actually is: a Ruby/Roda +
Redis service that ships as a non-root container behind a Compose stack, not a Next.js app on
Vercel. Everything marked **operator** is a step a human does with their own accounts; nothing
here has been executed against a live host, and nothing is claimed to be live.

## 1. Preflight — run, with results

| Check | Command | Result |
| --- | --- | --- |
| Backend specs | `bundle exec rspec` | **PASS** — 109 examples, 0 failures |
| Browser journeys | `BASE_URL=… npm --prefix e2e test` + `run test:accounts` | **PASS in CI** (both journeys, container smoke job) — not re-run locally in this session |
| Feature parity | `parity.py replica/features.csv` | **PASS** — 63.0, must-haves **11/11** |
| Rebrand sweep | `script/brand-sweep.sh` | **PASS** — exit 0 over the 95 tracked non-prose files. The raw `sweep.py .` over the whole repo also reports 2 hits, both this checkout's directory name in loop prose (`LOOP.md`, `loop-run-log.md`) — that is why the gate scans the shipped tree (see AGENTS.md) |
| Store listing lint | `listing.py replica/launch/listing.json` | **PASS** — 0 errors, 0 warnings (draft; no store submission) |
| Production build | `npm --prefix frontend run build` | **PASS** — vue-tsc + Vite, emitted to `public/app` |
| Hardened image + stack | `docker build`, `docker compose up` | **PASS in CI** (container smoke test) |
| Go-live gate self-test | `script/preflight_selftest.sh` | **PASS** — 5/5 assertions |
| Load / soak | `script/loadtest.rb` | **PASS in CI** — 400 secrets, 40 threads, no double reveal |
| Dependency audit | `bundler-audit`, `npm audit --audit-level=high` | **PASS** — 0 vulnerabilities |

### Failing or missing — these block a launch

| # | Item | State | Who |
| --- | --- | --- | --- |
| B1 | ~~Account deletion does not exist~~ — **fixed**: `DELETE /api/v3/account` with the password, plus a "Delete account" section in the dashboard | 5 specs (wrong password leaves the account intact, no session 401, email can be re-registered, live secrets survive, audit event recorded) | done |
| B2 | **Privacy and terms are written but not served anywhere** — `site/privacy.html`, `site/terms.html` exist, the domain does not | no DNS | operator |
| B3 | **Favicon is the brief's placeholder; no OG image** | `site/favicon.svg`, brief in `replica/brand.md` §4 | design |
| B4 | **Trademark / store / handle screening not run** for the name | `replica/brand.md` §2 "to run" | human + lawyer |
| B5 | **Preflight gate has never passed on a real host**: `HOST=https://<domain> PREFLIGHT_ALLOW_SIGNUP=1 script/preflight.sh` currently fails the Redis reachability check locally, correctly | run of the script | operator |
| B6 | **Host firewall rule not applied** (host → `redis:6379` drop) | rule written in `DEPLOYMENT.md` §4.0 | operator |

No open S1/S2 defects in `KNOWN_ISSUES.md`. **Stripe live mode is not applicable**: there is
no payment code in the app, and the managed tier is deliberately unsellable until B5 passes
(`replica/launch/pricing.md` §6). **Cookie banner is not applicable**: one session cookie,
essential, no analytics — see `site/privacy.html`.

## 2. Production services

| Thing | Decision | Notes |
| --- | --- | --- |
| Redis | **Separate instance from any dev/CI Redis.** Password via `REDIS_PASSWORD`, `requirepass`, AOF `everysec`, `noeviction`, on the `internal` network only | `compose.yaml` already enforces the network and the password placeholder (`:?` so it cannot start empty) |
| Secrets | `SECRET` (≥32 bytes) and `REDIS_PASSWORD` (24 bytes) generated on the host, stored in the host's secret store or root-owned `0600` `.env` — never in git, never in a shell history | `openssl rand -hex 32` / `-hex 24` |
| Env vars | Names must match `.env.example`: `SECRET`, `HOST`, `SSL=true`, `AUTH_MODE`, `REDIS_URL`, `REDIS_PASSWORD`, `TTL_OPTIONS`, `DEFAULT_TTL`, `SESSION_TTL`, `RATE_LIMIT_*`, `MAX_SECRET_BYTES`, `TRUST_PROXY=true`, `TRUSTED_PROXIES`, `METRICS_ENABLED`, `WEB_CONCURRENCY` | Boot **rejects** invalid values with a clear message (SECRET under 32 bytes, a scheme in `HOST`, a `DEFAULT_TTL` outside `TTL_OPTIONS`, `MAX_SECRET_BYTES` over 10 MiB, non-positive limits) instead of falling back to a default |
| Email | **None.** The app sends no mail, so there is no sending domain to verify and no SPF/DKIM to configure yet | Add DKIM/SPF the day a mailer lands, not before |
| Backups | `bin/ots backup` on a systemd timer, daily, **7-day retention (policy set here; nothing enforces it yet — the timer and the pruning are operator-side)** on a separate volume; restore drilled quarterly | RTO ≈ 12.4 s measured in the T-72 drill |

## 3. Host and domain (operator)

A single small VM is enough (2 vCPU / 2 GB / 20 GB SSD). Docker + Compose, Caddy in front for
automatic TLS, nothing else exposed.

```bash
# on the host, as a non-root user in the docker group
git clone https://github.com/aman-ali07/OneShotLink.git && cd OneShotLink
printf 'SECRET=%s\nREDIS_PASSWORD=%s\n' "$(openssl rand -hex 32)" "$(openssl rand -hex 24)" > .env
chmod 600 .env
docker compose up -d --build
curl -fsS http://127.0.0.1:3000/health
```

Caddyfile (proxy terminates TLS; `SSL=true` + `TRUST_PROXY=true` in `.env`):

```
app.example.com {
    reverse_proxy 127.0.0.1:3000
    header Strict-Transport-Security "max-age=31536000; includeSubDomains"
}
```

DNS — the user buys the domain and adds these; **no value below is set yet**:

| record | name | value | purpose |
| --- | --- | --- | --- |
| A | `@` | `<host IPv4>` | marketing site (`site/`) |
| A | `app` | `<host IPv4>` | the instance |
| AAAA | `@`, `app` | `<host IPv6>` | optional |
| CAA | `@` | `0 issue "letsencrypt.org"` | stops a mis-issued cert |
| TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:<you>@<domain>` | anti-spoofing until a mailer exists |

Canonical host: **`app.`** for the instance, apex for the marketing page; redirect apex →
`app.` for `/` on the instance, never the other way. Then:

```bash
HOST=https://app.example.com PREFLIGHT_ALLOW_SIGNUP=1 script/preflight.sh
```

That command is the go/no-go for B5. It must exit `0` before the managed tier or any launch
post goes out.

Firewall (B6) — only 80/443 inbound, and block the host's own path to Redis:

```bash
SUBNET=$(docker network inspect oneshotlink_backend --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}')
nft add table inet ots
nft add chain inet ots out '{ type filter hook output priority 0; policy accept; }'
nft add rule inet ots out ip daddr "$SUBNET" tcp dport 6379 drop
```

## 4. Watch it

| Need | How | State |
| --- | --- | --- |
| Uptime | External check on `GET /health` every minute, alert after 2 failures | to configure |
| Metrics | `METRICS_ENABLED=true`, Prometheus scrapes `/metrics` (off by default because it exposes traffic volume) | endpoint exists (T-73) |
| Alerts | `onetime_up == 0`, `onetime_redis_up == 0`, 5xx rate, `onetime_redis_memory_used_ratio >= 0.8` | alert expressions documented in `DEPLOYMENT.md` §5.1 |
| Status page | Public page fed by the same checks, with the last incident | not built (fix plan #7) |
| Error tracking | Self-hosted only — do not add a third-party script to a privacy product | not installed |
| Logs | One line per request, no IP, no body, secret keys redacted; kept 14 days | by design |

First week, in order: (1) create → reveal → second reveal `404` on the live domain, by hand;
(2) restore a backup into a scratch instance and confirm a secret still reveals; (3) re-run
`script/preflight.sh` after any config change; (4) watch `onetime_errors_total`; (5) check the
Redis memory ratio once traffic settles.

## 5. Rollback

```bash
git revert <sha> && docker compose up -d --build   # code
bin/ots rotate-key                                 # suspected SECRET exposure
docker compose down && docker compose up -d        # after a bad config change
```

Data rollback is `bin/ots restore` from the newest backup; anything revealed since the backup
is gone by design, so say that out loud rather than implying a full recovery. `RUNBOOK.md` has
the per-incident steps.

## 6. Mobile

Not applicable. There is no mobile app and no store submission; `replica/launch/listing.json`
exists only so the copy is linted if a wrapper is ever built.

## 7. Go/no-go

**No go.** Blocking: B2 (legal pages served), B3 (placeholder favicon, no OG image), B4
(trademark screening), B5 (preflight green on a real host), B6 (firewall). B1 is done.

When B5 and B6 are done, re-run §1 and paste the outputs here, then ask the user for the go.
Nothing in this file should be quoted as "deployed" until a live URL is recorded at the top.
