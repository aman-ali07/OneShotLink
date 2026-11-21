# Staging test report — OneShotLink

**Date: 2026-11-22. Environment: staging only. Synthetic data only. No production credentials.**
**Host: `https://oneshotlink.onrender.com` (Render Free Web Service, Docker build).**
**Datastore: Upstash Redis Free `oneshotlink_redis_DB`, region Mumbai, India (`ap-south-1`).**

> **Staging evidence — not production evidence.** These results come from a staging deployment
> using synthetic data only. They do **not** close T-70, T-71 or K-46: T-70 (TLS on a real
> hostname) — app-side checks pass on the staging hostname, but no production-host preflight is
> recorded; T-71 (Redis isolation) — **NOT ACHIEVED**, substitute controls only (TLS + token AUTH,
> no IP allowlist/ACL/Private Link), and any `preflight.sh --skip-redis` PASS proves nothing about
> isolation; K-46 (scheduled, signed webhook worker) — **OPEN**, no workflow applied and no
> signed-delivery proof. This is a free-tier beta, **not "production ready"**. The passphrase is an
> access gate, not a second encryption key; **no "zero-knowledge" or "server cannot decrypt" claim
> is made** (D-012). Public launch remains **NO-GO**.

## 1. Deployment evidence

The PR was merged and Render built the image. The build completed:
```
#24 Bundle complete! 11 Gemfile dependencies, 16 gems now installed.
#24 Gems in the group 'test' were not installed.
#33 RUN mkdir -p tmp /backups && chown -R ots:ots /app /backups
#34 exporting to image ... DONE 3.4s
==> Deploying...
==> Setting WEB_CONCURRENCY=1 by default, based on available CPUs in the instance
Puma version: 7.2.3 | Ruby version: ruby 3.3.14 | Environment: production | Workers: 1
```

The **first deploy failed** at boot with `onetime: cannot boot: SECRET must be set` — the Render
dashboard environment was missing `SECRET`. This is exactly `lib/onetime/config.rb:67-70` and the
fail-fast gate in `config.ru:8-14`. It was fixed by setting `SECRET`, `REDIS_URL`, `REDIS_PASSWORD`,
`HOST=oneshotlink.onrender.com` (no scheme), `SSL=true`, `AUTH_MODE=simple`, `TRUST_PROXY=false`,
`TRUSTED_PROXIES=` empty, `WEB_CONCURRENCY=1` in the Render dashboard and redeploying.

Verified after the fix:
```
GET /health              -> 200  {"status":"ok","redis":"ok","version":"0.1.0"}
GET /                    -> 200
GET /api/v3/config       -> 200
```

Datastore provisioning verified earlier in `docs/STAGING_PHASE0.md` §1b:
```
plaintext redis:// PING   -> no PONG (connection failed, as required)
rediss:// PING            -> PONG
CONFIG GET maxmemory-policy -> no value returned (managed Redis restricts it; UNVERIFIED)
bin/ots migrate --dry-run -> schema: current=0 target=1 / dry-run: would apply initial-schema
bin/ots migrate           -> schema: current=1 target=1 / migrate: applied initial-schema
GET schema:version        -> 1
bin/ots migrate (re-run)  -> migrate: already current; nothing applied
```

## 2. Verification matrix (executed against staging)

| Gate | Command | Result |
|---|---|---|
| TLS / headers / cookies | `HOST=https://oneshotlink.onrender.com PREFLIGHT_ALLOW_SIGNUP=1 script/preflight.sh --skip-redis` | `PREFLIGHT PASSED (1 skipped)`; HTTPS 200 + valid chain, HSTS `max-age=31536000; includeSubDomains`, nosniff/frame/CSP, `Secure`+`HttpOnly`+`SameSite` cookie, HTTP→HTTPS 301. Redis checks skipped — **proves nothing about isolation** |
| Core lifecycle + passphrase + file | `BASE_URL=… npm --prefix e2e test` | `{"ok":true,...,"wrongMessage":"That passphrase is not correct. The secret has not been viewed.","errors":[]}` |
| Terminal/edge states | `npm --prefix e2e run test:states` | exit 0, `"errors":0` |
| File secret | `npm --prefix e2e run test:file` | `{"ok":true,"filename":"fixture.bin","bytes":8,"replay":404,"errors":[]}` |
| Accounts | `npm --prefix e2e run test:accounts` | `accounts journey ok` |
| Secret requests | `npm --prefix e2e run test:requests` | `"ok": true`, key issued, no errors |
| Webhook API (queue/listing only) | `npm --prefix e2e run test:webhooks` | `"ok": true`, endpoint registered, no errors — **does not prove delivery** |
| Mobile | `npm --prefix e2e run test:mobile` | exit 0, 20 checks, no errors |
| Accessibility | `BASE_URL=… CHROME_PATH=/usr/bin/google-chrome npm --prefix e2e run test:a11y` | `a11y gate passed: 0 WCAG 2.2 AA violations` across 40 states; negative control `{"name":"negative-control-image-alt","detected":true}` |
| API passphrase contract | manual `curl`: create with passphrase → wrong → correct | wrong → `401 {"code":"invalid_passphrase","message":"That passphrase is not correct. The secret has not been viewed."}`; correct → `200` with plaintext; record intact |
| Backup / restore | `bash script/restore-drill.sh` (throwaway Redis, no production data) | `RESTORE DRILL PASSED`; `live=drill-live-payload`, `spent=GONE`, `schema=1`, `migration_pending=no` |
| Datastore state | `redis-cli -u rediss://…` | `ZCARD webhook:queue` → `0`; `GET schema:version` → `1`; 10 `secret:object:*` keys from synthetic journeys |

## 3. Defect found and fixed during staging

The first run of `e2e/journey.mjs` timed out waiting for `[role=alert]` after a wrong passphrase,
while the API correctly returned 401. Browser instrumentation showed the submit button was still
`disabled` (`aria-busy="true"`, "Revealing…") when the test typed and clicked again — remote
latency meant the first reveal request had not settled. With an explicit wait for
`form button[type=submit]:not([disabled])`, the alert appeared, the field cleared, and the
correct passphrase revealed:

```
alert: That passphrase is not correct. The secret has not been viewed.
field cleared: true
revealed: browser-debug-3
```

This was a **test race**, not an application defect. `e2e/journey.mjs` now waits for the button to
re-enable before both passphrase submissions; the full journey then passed. This change is
tracked in T-146.

## 4. Gates NOT closed (do not claim as tested)

| Gate | Status | Why |
|---|---|---|
| K-46 scheduled, signed webhook worker | **OPEN** | `.github/workflows/ops-free-tier.yml` is absent — only the staging template `deploy/free-tier/ops-free-tier.staging.yml` exists. Queue depth is 0 and the webhook E2E only proves queue/listing, not a signed POST, HMAC verification, replay idempotency or liveness alerts |
| Cold-start measurement | **NOT RUN** | Requires leaving the service idle >15 min, then timestamped `/health` probes; the service was continuously exercised during verification. Procedure is in the integration plan; run before final sign-off |
| Provider quota over-limit | **UNVERIFIED** | Upstash Free behavior above 500k commands/month is not documented; `CONFIG GET maxmemory-policy` returned no value on managed Redis |
| Redis network isolation (T-71) | **NOT ACHIEVED** | Upstash Free has no IP allowlist/ACL/Private Link; TLS + token only |
| Production TLS chain / real hostname | **OPEN** | Staging `*.onrender.com` is not a production hostname; no production-host preflight recorded |
| Public exposure | **NO-GO** | No public release authorized; staging URL must stay unadvertised |

## 5. Result

All **executed** staging gates passed: build, boot, health, TLS/HSTS/cookies, eight browser
journeys, API passphrase contract, a11y with negative control, datastore migration marker, and
backup/restore. The two functional gaps are K-46 worker proof and the cold-start measurement; the
security gates T-70/T-71 remain operator-owned. **Staging is functionally usable for beta
testing; public launch stays NO-GO.**
