# Zero-budget deployment plan — OneShotLink

**Date: 2026-11-21. Budget ceiling: ₹0/month. Status: prepared, NOT executed, NOT verified.**

This plan designs a free-tier beta deployment **without rewriting the application**. It uses
Render Free (managed TLS for the Puma container), Upstash Redis Free (TLS + AUTH + durable
storage), GitHub Actions (external webhook worker and backups), and Cloudflare Pages Free
(static marketing site). See `PROVIDER_COMPARISON.md` for the first-party evidence and limits.
`INFRASTRUCTURE_SECURITY.md` covers the controls and residual risks.

**Evidence revision (2026-11-21):** quotas, TLS, persistence, cold-start and network limits were
re-verified against live official pages (`webfetch` on `render.com/docs/free`,
`upstash.com/pricing/redis`, `upstash.com/docs/redis/features/eviction`) and cross-checked by
three parallel `.claude/` persona reviews (`release-infra`, `network-architect`,
`security-threat-model`). Two findings changed the risk register: Render may suspend a Free
service for high public-internet egress **including "accessing an external database"** (our
topology), and Upstash eviction — if ever enabled — randomly drops TTL keys first, which would
destroy live secrets. Both are addressed in §3, §4 and §10. Nothing was deployed.

**Verdict up front:** the architecture is *feasible at ₹0 for a beta*, but **T-70, T-71 and K-46
are not resolved by this document**. They are resolved only when the operator executes the
steps below on the real infrastructure and records the command output. Public launch stays
**NO-GO** until then.

## 1. Architecture (no code rewrite)

```
Browser ──HTTPS (Render managed cert)──> Render Free Web Service
                                          │ Dockerfile build, Puma, /health
                                          │ rediss:// + password
                                          ▼
                                     Upstash Redis Free
                                  (single DB, TLS, AUTH, eviction OFF,
                                   Durable Storage, no IP allowlist on Free)

GitHub Actions schedule (external, 2×/hour) ──same REDIS_URL/SECRET──> bin/ots webhooks:work
GitHub Actions schedule (external, daily)    ──same REDIS_URL/SECRET──> bin/ots backup --out
                                                               │
                                                               ▼
                                          encrypted dump -> private artifact / free R2

Cloudflare Pages Free ──> static site/ (privacy, terms, og image) ──> marketing hostname

Fallback (still ₹0, human-approved switch): Aiven Valkey Free (~512 MB usable, backups
included) if Upstash Free is suspended or its token is exposed — no TLS-downgrade, no rewrite.
```

**Why this shape:** the app is stateless (all state is in Redis), so a separately scheduled
process can run the exact same image/CLI against the same Redis. The web service *sleeps*
after 15 minutes on Render Free and has no cron/one-off jobs, so it must never be treated as
the worker host. No Rails/ORM/queue rewrite is introduced. **Verified constraint:** Render's
free docs allow suspending a service that makes a high volume of public-internet requests and
name *"accessing an external database"* as an example — our Redis is external. Keep command
volume bounded (§7/§10) and treat a suspension notice as an incident, not a curiosity.

## 2. Phase 0 — accounts and safeguards (before creating anything)

1. Create accounts **without adding any payment method**: Render, Upstash, GitHub, Cloudflare.
2. In Upstash: confirm plan **Free**, set **Auto Upgrade = OFF**, leave eviction **OFF**.
3. In Render: set the build-pipeline **spend limit** and skip adding a card.
4. In GitHub: prefer a **public** repo (standard runners free); if private, set a hard Actions
   budget and `timeout-minutes`/`concurrency` in every workflow.
5. Generate secrets **on the provider side**; never in git or shell history:
   ```sh
   openssl rand -hex 32   # SECRET
   openssl rand -hex 24   # REDIS_PASSWORD (Upstash token is issued by the console)
   openssl rand -hex 24   # METRICS_TOKEN (only if /metrics is enabled)
   openssl rand -hex 24   # BACKUP_PASSPHRASE (encrypts dumps before upload)
   ```
6. Decide `AUTH_MODE`. `disabled` keeps guest sharing but returns 403 on all webhook/account
   routes — K-46 then has no work to drain. Plan uses **`simple`** so webhooks are usable;
   accept that account records live only in free Redis (see §8).

## 3. Phase 1 — Upstash Redis Free (T-71 substitute controls, not isolation)

1. Create one free Redis database in a region near the Render service.
2. Copy the **`rediss://`** connection string and password from the console. TLS is mandatory
   on Upstash and cannot be disabled; `redis://` will fail (https://upstash.com/docs/redis/howto/redis-cli).
3. Verify the access controls actually present on Free:
   ```sh
   # TLS is mandatory; a plaintext connection must fail.
   redis-cli -u redis://<host>:6379 PING          # expect: connection failure
   REDISCLI_AUTH='<token>' redis-cli -u 'rediss://<host>:6379' PING   # expect PONG
   REDISCLI_AUTH='<token>' redis-cli -u 'rediss://<host>:6379' INFO clients | head
   REDISCLI_AUTH='<token>' redis-cli -u 'rediss://<host>:6379' CONFIG GET maxmemory-policy
   ```
   Expect `noeviction`-equivalent behaviour (eviction off by default: writes rejected at the
   250 MB ceiling). **Record**: plan = Free, Auto Upgrade = OFF, eviction = OFF, TLS required,
   password required, no public host port, no IP allowlist on Free (residual risk in
   `INFRASTRUCTURE_SECURITY.md`).
4. **T-71 classification after this step:** **substitute controls only — network isolation is NOT
   achieved.** Upstash Free offers TLS + token AUTH and persistence, but no IP allowlist, ACL or
   Private Link; the host firewall from self-hosted T-71 has no equivalent here. The controls are
   **not verified** until the deployed app and worker have only worked over `rediss://` and the
   provider settings are recorded. `script/preflight.sh` must be run with `--skip-redis` because
   there is no host bridge to probe — **a PASS there proves nothing about Redis isolation**;
   record the provider settings and token-handling controls in `docs/GO_LIVE_HANDOFF.md` instead.

## 4. Phase 2 — Render Free Web Service (T-70 data plane)

1. **New → Web Service → Language: Docker → connect the repo.** Render builds the repository
   `Dockerfile` (https://render.com/docs/docker). No `render.yaml` is required.
2. Plan: **Free** (0.1 CPU / 512 MB). Build command: default Dockerfile build. Start command:
   leave empty (image `CMD` runs Puma). Health check path: **`/health`**.
   Live docs confirm managed TLS and custom domains on Free, 750 instance-hours/month, a
   **15-minute idle spin-down with ~1-minute spin-up**, an ephemeral filesystem, and no SSH,
   one-off jobs, persistent disks or scaling. `/robots.txt` is answered by Render while spun
   down and does **not** wake the service. Critically, Render *"may suspend a Free web service
   that initiates an uncommonly high volume of traffic over the public internet"* and explicitly
   lists *"accessing an external database"* — so the Upstash connection pattern must stay
   bounded (§7). Overage without a card **suspends** rather than bills.
3. Set environment variables in the Render dashboard (never in git):

   | Variable | Value for the beta | Why |
   |---|---|---|
   | `SECRET` | 32+ byte random hex | Encrypts every secret + metadata MAC + audit IP salt |
   | `REDIS_URL` | `rediss://…` from Upstash | TLS mandatory |
   | `REDIS_PASSWORD` | Upstash token | AUTH; code folds it into the URL |
   | `HOST` | `<app>.onrender.com` (no scheme) | Link/cookie origin; must match the public host exactly |
   | `SSL` | `true` | Secure cookies + HSTS |
   | `TRUST_PROXY` | `true` only if Render proxy CIDRs are confirmed; otherwise `false` | Rate-limit identity vs. spoofing (see §7) |
   | `TRUSTED_PROXIES` | verified proxy CIDRs, or empty | Boot fails on malformed CIDR; empty = trust none |
   | `AUTH_MODE` | `simple` | Enables webhooks/accounts (K-46) |
   | `WEB_CONCURRENCY` | `1` | 512 MB free instance; 2 workers + preload may be too heavy |
   | `PUMA_MAX_THREADS` | `5` | Matches existing default |
   | `METRICS_ENABLED` | `false` | Avoid exposing traffic volume on a public host |
   | `METRICS_TOKEN` | empty while metrics off; 24-byte hex if enabled | Endpoint is a 404 without it |
   | `WEBHOOK_ALLOW_PRIVATE` | **unset** | Keep SSRF protection on |
   | `TTL_OPTIONS` / `DEFAULT_TTL` | defaults `1800,43200,86400,259200` / `86400` | Bound blast radius |
   | `MAX_SECRET_BYTES` | `1048576` | Existing cap |
   | `RATE_LIMIT_*` | defaults from `.env.example` | Per-scope budgets |
   | `LOG_LEVEL` | `info` | No debug bodies |

   Render injects `PORT`; Puma already reads it (`config/puma.rb:4`), so do not hard-code a
   port. Verify the actual value in the first deploy log.
4. First deploy may take several minutes (npm + apt + bundle in the Dockerfile). Health-check
   grace must be **≥60 s**; initial 503s while Redis TLS connects are expected.
5. Smoke:
   ```sh
   curl -fsS https://<app>.onrender.com/health        # {"status":"ok","redis":"ok"}
   HOST=https://<app>.onrender.com script/preflight.sh --skip-redis   # must exit 0
   ```
   The preflight creates a throwaway signup — run against a beta instance only.
6. **T-70 classification after this step:** managed TLS is configured, but **not verified** until
   the preflight exit code, certificate chain, HSTS, headers, cookie flags and HTTP→HTTPS
   redirect are recorded on the real hostname. Optional Cloudflare fronting (Universal SSL,
   DDoS, Tunnel) is described in `PROVIDER_COMPARISON.md` but adds a second proxy hop that must
   be reflected in `TRUSTED_PROXIES`; skip it for the first beta.

## 5. Phase 3 — Cloudflare Pages Free (static site, legal pages)

1. Create a Pages project from `site/` with the free plan (500 builds/month). Verify
   `site/privacy.html`, `site/terms.html`, favicon and an absolute `og:image` URL resolve.
2. This closes the "legal pages live" part of the go-live checklist; it does **not** host the app
   (Workers Free cannot run Puma, and Containers are paid-only).

## 6. Phase 4 — external worker and backups (K-46)

The app has no HTTP admin route that can trigger the worker, so a Cloudflare Cron cannot drive
it without new code. GitHub Actions is the documented ₹0 scheduler that can run Ruby directly
against the same Redis. **Adding/changing `.github/workflows/` is a protected-path edit and
requires explicit operator approval before it is committed or pushed.**

### 6.1 Scheduled workflow (proposed content; do not apply without approval)

```yaml
name: ops-free-tier
on:
  schedule:
    - cron: "17,47 * * * *"     # off-hour minutes: high-load delays cluster at :00
    - cron: "23 3 * * *"        # daily backup
  workflow_dispatch:

permissions:
  contents: read                 # least privilege by default; elevate only in the webhooks job

concurrency:
  # GitHub's current default is `queue: single`: a new pending run CANCELS an
  # existing pending one. A single group could therefore replace a pending backup
  # with a later worker run. `queue: max` keeps pending runs; the backup job also
  # gets its own group below. (Two separate workflows are equally valid.)
  group: ots-ops-${{ github.ref }}
  queue: max
  cancel-in-progress: false

jobs:
  webhooks:
    if: github.event.schedule != '23 3 * * *'
    runs-on: ubuntu-latest
    timeout-minutes: 5
    environment: production      # optional: require review before secrets are available
    permissions:                 # only this job needs to open an alert issue
      contents: read
      issues: write
    env:
      SECRET: ${{ secrets.SECRET }}
      REDIS_URL: ${{ secrets.REDIS_URL }}
      REDIS_PASSWORD: ${{ secrets.REDIS_PASSWORD }}
      WEBHOOK_ALLOW_PRIVATE: ""
    steps:
      - uses: actions/checkout@PINNED_SHA       # replace with a full commit SHA before applying
      - uses: ruby/setup-ruby@PINNED_SHA        # replace with a full commit SHA before applying
        with:
          ruby-version: "3.3"
          bundler-cache: true
      - name: Drain queued deliveries (bounded retries)
        run: |
          set -e
          for attempt in 1 2 3; do
            if timeout 120 bundle exec ruby bin/ots webhooks:work 20; then exit 0; fi
            echo "worker attempt $attempt failed; backing off" >&2
            sleep $((attempt * 10))
          done
          exit 1
      - name: Alert on sustained queue depth
        if: failure()
        run: |
          # Rediss URL: use redis-cli with TLS; never print the token.
          # The "run never happened" case is monitored separately by comparing
          # the last successful run timestamp via the GitHub API (see notes).
          depth=$(redis-cli -u "$REDIS_URL" ZCARD webhook:queue 2>/dev/null || echo unknown)
          echo "webhook queue depth: $depth"
          if [ "$depth" != "unknown" ] && [ "$depth" -gt 200 ]; then
            existing=$(gh issue list --label webhook-liveness --state open --json number --jq length)
            if [ "$existing" = "0" ]; then
              gh issue create --label webhook-liveness \
                --title "Webhook queue backlog (depth $depth)" \
                --body "Scheduled worker did not drain the queue; check run logs."
            fi
          fi

  backup:
    if: github.event.schedule == '23 3 * * *'
    runs-on: ubuntu-latest
    timeout-minutes: 10
    environment: production
    concurrency:                 # never let a worker run displace a pending backup
      group: ots-ops-backup-${{ github.ref }}
      queue: max
      cancel-in-progress: false
    env:
      SECRET: ${{ secrets.SECRET }}
      REDIS_URL: ${{ secrets.REDIS_URL }}
      REDIS_PASSWORD: ${{ secrets.REDIS_PASSWORD }}
      BACKUP_PASSPHRASE: ${{ secrets.BACKUP_PASSPHRASE }}
    steps:
      - uses: actions/checkout@PINNED_SHA       # replace with a full commit SHA before applying
      - uses: ruby/setup-ruby@PINNED_SHA        # replace with a full commit SHA before applying
        with: { ruby-version: "3.3", bundler-cache: true }
      - name: Export and client-side encrypt
        run: |
          set -euo pipefail
          umask 077
          bundle exec ruby bin/ots backup --out /tmp/dump.json
          # `openssl enc` does NOT support AEAD ciphers (aes-256-gcm fails with
          # "AEAD ciphers not supported"). GPG symmetric AES256 is the canonical
          # zero-cost tool: integrity-protected, passphrase read from stdin,
          # never from argv or the process list.
          printf '%s' "$BACKUP_PASSPHRASE" | gpg --batch --yes \
            --pinentry-mode loopback --passphrase-fd 0 \
            --symmetric --cipher-algo AES256 \
            -o /tmp/dump.json.gpg /tmp/dump.json
          rm -f /tmp/dump.json
      - uses: actions/upload-artifact@PINNED_SHA   # replace with a full commit SHA before applying
        with:
          name: ots-backup-${{ github.run_id }}
          path: /tmp/dump.json.gpg
          retention-days: 7
```

Notes on the workflow (the YAML above is **proposed, not applied** — protected path):
- **Authenticated execution** = GitHub Environment `production` + repo secrets; no secret is
  passed on argv. Enable **required reviewers** on the environment; pin **full commit SHAs** for
  every `uses:` action (the `PINNED_SHA` tokens above are placeholders to replace), and never
  introduce `pull_request_target` or untrusted code into this workflow. The job holds the same
  decryption capability as the app — see `INFRASTRUCTURE_SECURITY.md` §8 R1.
- **Idempotency** comes from the app's stable delivery id + `SET NX` claim (`webhook.rb`), not from
  the shell retries. A dropped run causes a *delay*, never a duplicate POST; the three bounded
  shell attempts only cover transient runner failures.
- **Concurrency** is deliberately split: GitHub's default `queue: single` would cancel a pending
  backup and replace it with a later worker run. Both groups use `queue: max` with
  `cancel-in-progress: false`.
- **Monitoring** = queue depth plus one de-duplicated GitHub issue on failure, **and** a separate
  liveness check on the *last successful run timestamp* via the GitHub API — GitHub can delay or
  drop scheduled runs under load (especially at the top of the hour, hence `:17`/`:47`), and
  public repos auto-disable schedules after **60 days** of inactivity. `hashFiles('/tmp/…')` was
  removed: it searches the workspace, so that guard was always true. Artifacts default to 90-day
  retention; `retention-days: 7` is valid and must stay short.
- **Backup** = ciphertext JSON is PII-bearing; encrypt it client-side with a separate
  passphrase, use short artifact retention, and never upload `SECRET`. Prefer a private free R2
  bucket with lifecycle deletion over artifacts: 7 days is shorter than the 30-day receipt
  lifecycle. Restore drill must be done on a scratch Redis (`script/restore-drill.sh`), not the
  live database. Restore also needs the historical `SECRET` if a rotation happened.
- **Rejected schedulers:** Cloudflare Cron (5 triggers, up to 15-min propagation, invocations can
  be missed, cannot run Ruby and this repo has no admin HTTP endpoint), cron-job.org (HTTP-only,
  30-s timeout, no TLS-certificate validation, auto-disables after 25 failures), and **Render Cron
  Jobs ($1/month minimum — breaks the ₹0 ceiling)**. GitHub Actions is the only reviewed free
  scheduler that can run the Ruby CLI directly.
- If the repository is private, the two schedules consume the **$12 Actions allowance** (GitHub
  docs now express it as $12 rather than a fixed minute count; ~2,000 Linux minutes is a
  derivation at $0.006/min). Keep timeouts tight and monitor usage.

### 6.2 Prove K-46 end to end (operator evidence)

1. Register a public test endpoint (`AUTH_MODE=simple` required) and save the one-time signing
   secret. Keep `WEBHOOK_ALLOW_PRIVATE` unset.
2. Create a secret to emit `secret.created`, run the workflow manually with
   `workflow_dispatch`, and verify a signed POST reached the receiver:
   ```sh
   grep -i '^X-OneShotLink-' /tmp/ots-hook.request
   printf '%s' '<raw body>' | openssl dgst -sha256 -hmac "$SIGNING_SECRET"
   ```
3. Run the job again with the same delivery id: no second POST (idempotency).
4. Record: scheduled run timestamps, queue depth before/after, signature verification, and a
   screenshot/log of the alert path. **Only then** may K-46 be marked verified.

## 7. Hardening specific to this stack

- **Proxy trust (T-70 correctness).** `TRUSTED_PROXIES` must cover every hop. If Render's egress
  CIDRs cannot be confirmed, set `TRUST_PROXY=false`: rate limiting then uses the proxy IP as a
  single bucket (coarse but fail-safe), while Origin proof still uses `Config.base_url` and is
  not spoofable via `X-Forwarded-Host`. Never put the app's `HOST` as a URL with a scheme.
- **Origin lock.** Render publishes only through its proxy for the free tier; do not add a
  second direct exposure. If an off-host proxy (Cloudflare Tunnel) is used, restrict the origin
  to proxy traffic and re-check XFF trust.
- **`/metrics`.** Leave `METRICS_ENABLED=false` on the free tier; traffic volume, error rates and
  Redis memory are operationally sensitive. If enabled, set a high-entropy `METRICS_TOKEN` and
  block `/metrics` at the edge. **Correction to an earlier draft:** wrong-token attempts *are*
  throttled — `app.rb:676-681` calls `enforce_rate_limit!(:metrics_auth)` on a failed token and
  returns a uniform 404 (then 429 when the budget is spent); successful scrapes use the separate
  `RATE_LIMIT_METRICS` scope at `app.rb:683`. This matches `INFRASTRUCTURE_SECURITY.md` §5.
- **Webhooks.** Session + CSRF + owner scoping, SSRF guard, resolved-IP pinning and HMAC
  signing are already enforced. Keep `WEBHOOK_ALLOW_PRIVATE` unset in the worker, restrict
  worker egress to TCP 443, and disable provider response-body logging (the create response
  contains the signing secret once).
- **Admin.** All admin operations are CLI-only (`bin/ots`); there is no HTTP audit/role route.
  Render Free has no SSH, but dashboard access equals admin capability — restrict membership
  and use environment protection rules for the Actions secrets.
- **Logs.** App logs are redacted by design; CDN/proxy logs are not — disable URL query/body
  logging on any CDN in front of the app, because secret keys are bearer capabilities.

## 8. Data, storage and backup behaviour to verify after deploy

| Property | Existing behaviour (evidence) | Post-deploy command |
|---|---|---|
| Encryption at rest | AES-256-GCM + HKDF per record; no plaintext in Redis (`spec/unit/crypto_spec.rb`, `spec/integration/secrets_api_spec.rb:125-133`) | create a secret, `REDISCLI_AUTH=… redis-cli -u rediss://… GET secret:object:<id>` → ciphertext only |
| Single use | Lua compare-and-delete; 8-way race → exactly one winner (`spec/unit/store_spec.rb:12-29`, `secrets_api_spec.rb:162-175`) | reveal once → 200, replay → 404 |
| Expiry / 30-day receipt | TTL on object + receipt; terminal transition sets 30-day receipt TTL (`receipt_lifecycle_spec.rb:48-104`) | `TTL secret:receipt:<id>` ≈ 2592000 after reveal/burn |
| Backups / restore | format 2, schema marker, 0600, `--force` guard, TTL/zset preservation (`spec/unit/ops_spec.rb:138-310`) | `bin/ots backup --out /tmp/dump.json`; `script/restore-drill.sh` on scratch Redis |
| Degraded storage | Redis outage/full → 503 + Retry-After, no secret loss (`web_spec.rb:68-114`) | stop/saturate scratch Redis, assert 503 and intact records |
| Full suite | backend suite green per the current `AGENTS.md` status line (the count is moving during this research pass — re-run before any deploy and record the actual output) | `docker run … ots-dev bundle exec rspec` (see `TESTING.md`) |

## 9. Cost breakdown (₹0/month target)

| Item | Plan | Monthly cost | Quota / cost trigger |
|---|---|---|---|
| Web service | Render Free (Docker) | ₹0 | 0.1 CPU/512 MB; 750 instance-hours; 5 GB egress; 500 build min; card absent = suspend at quota |
| Redis | Upstash Free | ₹0 | 250 MB, 500k commands, 10 GB bandwidth; card = auto-upgrade to PAYG (forbidden) |
| Scheduler | GitHub Actions (public repo) | ₹0 | standard Linux runners free; private repo $12 allowance; 5-min minimum cadence, runs may be dropped |
| Static site | Cloudflare Pages Free | ₹0 | 500 builds/month, 20-min timeout |
| TLS | Render managed cert + Cloudflare Universal SSL | ₹0 | no custom domain purchase |
| Domain | use `*.onrender.com`, `*.pages.dev` | ₹0 | custom domain only after revenue |
| Backups | Actions artifact (7-day retention) or free R2 10 GB-month | ₹0 | client-side encrypted; no paid storage |
| **Total** | | **₹0** | **any payment method, card, larger instance, paid DB, or domain breaks the ceiling** |

## 10. Documented limitations / risks (read before enabling)

- **Cold starts:** Render Free sleeps after 15 minutes idle and takes about a minute to wake;
  visitors see a loading page. `/robots.txt` does **not** wake it. Link recipients may hit 503
  during wake-up; secrets keep ticking toward TTL.
- **Downtime:** Render may restart the free service at any time, with no SLA. Backups and the
  worker must not depend on it being awake.
- **Data loss:** Upstash Free lists *persistence: Yes* and *high availability: Primary Replicas*,
  but **no multi-zone HA, no documented automatic failover and no uptime SLA**; an earlier draft
  saying "no replica redundancy" was overstated. At 250 MB, **eviction OFF** means writes are
  rejected (app surfaces 503) — verified. **Enabling eviction is a CRITICAL defect:** Upstash's
  only policy, `optimistic-volatile`, removes TTL keys first and then random keys, which can
  destroy an unexpired secret. The **500,000 commands/month** figure is an included allowance;
  exact behaviour when a Free database exceeds it is **UNVERIFIED** (official over-limit
  descriptions cover only PAYG/Fixed) — confirm in the console during the first deploy. Free
  Redis is **not** a sole durable store — keep the encrypted off-platform backup.
- **Quotas/provider restrictions:** no IP allowlist, ACL, private link or encryption at rest on
  Upstash Free; no SSH, one-off jobs or persistent disk on Render Free; GitHub scheduled workflows
  can be delayed or dropped (especially at the top of the hour) and public repos disable them
  after 60 days of inactivity; **Render Cron Jobs cost $1/month minimum and are rejected**;
  Cloudflare Workers Free cannot run Ruby or host the app.
- **Provider traffic suspension:** Render may suspend a Free service for high public-internet
  egress and names "accessing an external database" — this app's every request touches Upstash.
  Keep command volume bounded, alert at 70–80% of the 500k allowance, and treat a suspension
  notice as an incident (fallback: Aiven Valkey Free).
- **Security residuals:** off-host worker holds the instance `SECRET` (full decryption capability
  for every unexpired record — accept in writing); **no Redis network isolation at all** on Free
  (TLS + token only); proxy CIDR lists can drift, and Render's inbound proxy CIDRs are
  UNVERIFIED; Cloudflare Logpush `http_requests` **will** record the full secret-key path in
  `ClientRequestURI` unless that field is excluded — so **no CDN in the first beta**. See
  `INFRASTRUCTURE_SECURITY.md`.
- **No "production ready" claim:** this is a free-tier beta only. Do not claim zero-knowledge;
  the passphrase is an access gate (D-012).

## 11. Deployment feasibility assessment

| Gate | Assessment |
|---|---|
| Technical fit | **Feasible**: no app rewrite; Dockerfile builds on Render; Redis command set maps to Upstash; CLI worker/backups run off-host. |
| Cost | **Feasible at ₹0** if no card is ever added and quotas are respected. |
| T-70 | **Prepared, not resolved**: managed TLS is available free; needs real-host preflight evidence. |
| T-71 | **Not achieved (substitute controls only)**: TLS + token AUTH + eviction-off are available free, but there is **no network isolation** (no IP allowlist/ACL/Private Link on Free). Needs recorded provider settings and deployed-app proof; `preflight.sh --skip-redis` PASS does not prove isolation. |
| K-46 | **Prepared, not resolved**: GitHub Actions can run the worker; needs an approved workflow, a successful signed delivery and liveness monitoring. |
| Public launch | **NO-GO** until the three gates above are verified on the actual deployed infrastructure and recorded in `GO_LIVE_REMINDER.md` / `docs/GO_LIVE_HANDOFF.md`. |

## 12. Actions requiring your approval (do not proceed without them)

1. Approve creating **free accounts without payment methods** on Render, Upstash and Cloudflare.
2. Approve the **exact env values** (especially `AUTH_MODE=simple`, `HOST`, proxy-trust choice).
3. Approve adding `.github/workflows/ops-free-tier.yml` and the repo secrets/environment
   protection rules (protected path; currently **not** added).
4. Approve the client-side backup encryption passphrase and artifact/R2 destination.
5. Approve running the preflight and recording its output on the real hostname.
6. Approve the final go/no-go signature. No commit, push, deploy, key rotation, or restore will
   be performed by an agent.
