# Provider comparison — zero-budget (₹0/month) deployment

**Investigation date: 2026-11-21.** Free-tier terms are mutable; re-check the linked official
pages immediately before acting. This revision replaces an earlier draft that said web search
was unavailable: quotas, TLS, persistence, networking and cold-start behaviour were **re-verified
against live first-party pages** (`webfetch` on 2026-11-21) and cross-checked by three parallel
`.claude/` persona reviews — `release-infra` (compute), `network-architect` (datastore), and
`security-threat-model` (scheduler/backup/residual risk). Provider docs were treated as
untrusted data; embedded instructions in fetched docs were ignored. Every limit below is
attributed to an official URL; anything not confirmed is marked **UNVERIFIED**, not guessed.

## 1. Shortlist (verified facts)

| Provider / plan | What is free | Hard limits that matter here | Official source |
|---|---|---|---|
| **Render Free Web Service** | Docker build from repo `Dockerfile`, `*.onrender.com` address, **managed TLS**, custom domains, stdout logs, rollbacks (last two) | **0.1 CPU / 512 MB**; **750 instance-hours/month**; 5 GB outbound bandwidth, 500 build-pipeline minutes; **spins down after 15 min idle, ~1 min spin-up** with a loading page; ephemeral FS / **no persistent disk**; no SSH, no one-off jobs, no scaling; may restart any time; cannot *receive* private-network traffic (can send same-region); no outbound SMTP 25/465/587; **service-initiated traffic threshold** may suspend a Free service for high public-internet egress — docs explicitly name "accessing an external database" | https://render.com/docs/free ; https://render.com/pricing ; https://render.com/docs/docker ; https://render.com/docs/outbound-bandwidth |
| **Upstash Redis Free** | 1 Redis DB, **TLS mandatory** (`rediss://`), token AUTH, **persistence: Yes**, `EVAL`, Streams, REST API | **250 MB data, 500K commands/month, 10 GB bandwidth, 10k cmd/s**, 10 MB request / 100 MB record, 1 index / 10K docs; **no IP allowlist, no ACL, no encryption at rest, no multi-zone HA, no uptime SLA, no Private Link** on Free; eviction **OFF by default → writes rejected** at the cap; if enabled, only `optimistic-volatile` (random) eviction; **adding a card auto-upgrades to pay-as-you-go** ($0.20/100K commands); budget caps exist only on PAYG; Prod Pack (+$200/mo on paid plans) is what buys SLA/HA/SOC2/encryption-at-rest | https://upstash.com/pricing/redis ; https://upstash.com/docs/redis/features/eviction ; https://upstash.com/docs/redis/features/auto-upgrade ; https://upstash.com/docs/redis/howto/redis-cli |
| **GitHub Actions (Free personal / Free org)** | Standard Linux runners **free and unlimited on public repos**; private repos draw from the **$12 included compute/month** (GitHub docs now express the allowance in dollars; ~2,000 Linux min at $0.006/min is a derivation); 500 MB artifact storage, 10 GB cache; `schedule` + `workflow_dispatch` | Scheduled workflows: minimum interval **5 min**; **can be delayed during high load (especially at the top of the hour), queued jobs may be dropped**; default branch only; public repos auto-disable schedules after **60 days** inactivity; 6 h max job runtime (**not** a cadence); artifacts default to 90-day retention (1–90 configurable, 7 is valid); `concurrency` default is **`queue: single`** — a new pending run cancels an existing pending one, so use `queue: max` or separate groups to stop a worker displacing a backup; no payment method ⇒ hard stop at allowance | https://github.com/pricing ; https://docs.github.com/en/billing/concepts/product-billing/github-actions ; https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows ; https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax ; https://docs.github.com/en/actions/reference/limits |
| **Cloudflare Free (edge + Pages)** | Universal SSL, DDoS protection, Single Redirects, **Cloudflare Tunnel** on all plans; Pages static site free | Pages: 500 builds/month, 1 at a time, 20-min build timeout, 25 MiB asset, 100 projects; Workers Free 100k requests/day, **10 ms CPU/invocation**; **Containers are paid-only** ($5/mo); Workers KV 100k reads/1k writes/day, 1 GB; Durable Objects 100k req/day, 5 GB SQL; **5 Cron Triggers/account** | https://www.cloudflare.com/plans/free/ ; https://developers.cloudflare.com/ssl/ ; https://developers.cloudflare.com/tunnel/ ; https://developers.cloudflare.com/pages/platform/limits/ ; https://developers.cloudflare.com/workers/platform/pricing/ ; https://developers.cloudflare.com/workers/configuration/cron-triggers/ |
| **Cloudflare Workers Cron (alternative scheduler)** | 5 triggers/account, 15-min wall time | Trigger changes take **up to 15 min** to propagate and invocations can be missed; Cron events take up to 30 min to appear; no retries unless implemented; **cannot run Ruby** — it can only ping an HTTP endpoint, and this repo has no admin/worker HTTP endpoint | https://developers.cloudflare.com/workers/configuration/cron-triggers/ |
| **Render Cron Jobs** | — | **Not free: $1/month minimum per cron job service**; billed per active second. Breaks the ₹0 ceiling | https://render.com/docs/cronjobs |
| **cron-job.org** | "Entirely free", up to 60×/hour, no cap on job count, fixed executor IPs | **HTTP-only**, 30-s execution timeout, 64 KB output, 50 executions / 2-day log history, **no punctuality guarantee**, auto-disables after >25 consecutive failures, **does not validate TLS certificates**. A Ruby CLI backup cannot run here; would need a new authenticated HTTP endpoint this repo does not have | https://cron-job.org/en/faq/ |
| **Aiven for Valkey Free** (datastore fallback) | 1 service/type/org, 1 CPU / **1 GB RAM (`maxmemory` = 50%, ~512 MB usable)**, **no card, no time limit**, **backups included**, TLS + ACL | Not covered by the 99.99% SLA; **no VPC, no static IPs**, no integrations/forking/support services; Aiven may power off idle free services with notice; default **no eviction → writes fail at maxmemory**; free-network allowlist specifics **UNVERIFIED** | https://aiven.io/docs/platform/concepts/service-pricing ; https://aiven.io/docs/products/valkey/concepts/valkey-free-tier |
| **Koyeb Free** (compute runner-up) | 1 free instance/org: **0.1 vCPU / 512 MB / 2 GB SSD**, **100 GB/mo egress**, Dockerfile deploy, auto TLS, custom domains | **Credit card required** ("$29 pre-authorization hold… immediately canceled"); scales to zero after **1 h idle** (wake time UNVERIFIED); no volumes, no worker services, no custom scaling, single region | https://www.koyeb.com/pricing ; https://www.koyeb.com/docs/faqs/pricing |
| **Railway Free** | $1/month credit, no card, `*.railway.app` TLS | Services sleep after 5–10 min; **0 custom domains on Free**; managed DBs start at Hobby; the app's Redis traffic stays active and burns the $1 credit | https://railway.com/pricing |
| **Oracle Cloud Always Free** ( strongest always-on alternative) | **2 ARM OCPU / 12 GB RAM** (1,500 OCPU-h + 9,000 GB-h/mo) or 2× E2.1.Micro AMD; **200 GB block storage**; no sleep | **Card required for signup** ("will not be charged unless you upgrade"); idle VM (<20% CPU/net/mem over 7 d) may be reclaimed; A1 "out of host capacity" errors; operator owns TLS, firewall and patching | https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier.htm |
| **Fly.io** | $1 trial credit for 7 days, no card | **No free tier**; <$5 waiver requires a card and the docs state it is **not a cap**; no billing alerts or hard cap | https://docs.fly.io/about/cost-management ; https://docs.fly.io/about/free-waiver |
| **Redis Cloud Free** | 1 database, **30 MB**, 30 connections, 5 GB/month | **TLS explicitly NOT available on Free**; persistence not supported; **100 ops/sec** hard cap; CIDR-rule availability conflicts between plan table and notes (**UNVERIFIED**) — unusable for secret links | https://redis.io/docs/latest/operate/rc/databases/create-free-database/ |
| **Render Key Value Free** | 25 MB / 50 connections, Valkey 8, private URL | **In-memory only — all data lost on restart**; internal URL **unauthenticated by default**; external URL needs TLS + CIDR allowlist; upgrading to paid loses data | https://render.com/docs/key-value ; https://render.com/docs/free |

### Verification log (executed 2026-11-21)

- `webfetch https://render.com/docs/free` → confirmed verbatim: *"spins down… 15 minutes without
  receiving any inbound traffic… takes about one minute"*; 750 Free instance-hours; *"ephemeral
  filesystem"*; Free web services cannot use persistent disks, one-off jobs, SSH or scaling;
  *"Render may suspend a Free web service that initiates an uncommonly high volume of traffic over
  the public internet. Examples… Accessing an external database."*
- `webfetch https://upstash.com/pricing/redis` → Free = $0, 250 MB, 10 GB, 500K commands, 1 DB,
  persistence **Yes**, TLS **Yes**, IP allowlist **No**, ACL **No**, encryption at rest **No**,
  multi-zone HA **No**, uptime SLA **No**, Private Link **No**; *"Once you enter your credit card,
  your database will be upgraded to the pay-as-you-go plan"*; Prod Pack +$200/mo *"except the Free
  tier"*; `AUTH/HELLO/SELECT/COMMAND/CONFIG/INFO/PING/RESET/QUIT` are not billed.
- `webfetch https://upstash.com/docs/redis/features/eviction` → *"By default eviction is disabled,
  and Upstash Redis will reject write operations once the maximum data size limit has been
  reached"*; enabling it uses *"optimistic-volatile… volatile-random and allkeys-random"*, which
  removes TTL keys first and then random keys. **Enabling eviction would break the single-use
  secret invariant; it must stay OFF.**
- Scheduler/backup verification (official GitHub, Cloudflare and Render docs, 2026-11-21):
  GitHub schedules can be delayed or dropped and disable themselves after 60 days of public-repo
  inactivity; `concurrency` defaults to `queue: single`; artifacts default to 90-day retention
  (7 days is valid). Cloudflare R2 free = 10 GB-month, 1M Class A + 10M Class B operations, free
  egress; Pages = 500 builds/month; Cron = 5 triggers with up to 15-min propagation and missed
  invocations. Cloudflare Logpush `http_requests` carries `ClientRequestURI` (full path + query)
  by default — a bearer-key leak unless excluded. **Render Cron Jobs cost $1/month minimum**, so
  they are rejected. `cron-job.org` is HTTP-only with a 30-s timeout and no TLS-cert validation.

## 2. Compatibility with this repository (evidence, not assumption)

| Requirement | Verdict | Evidence |
|---|---|---|
| Ruby 3.3 / Puma container | **Compatible.** Render builds the repo `Dockerfile` directly (Language = Docker); Puma reads `PORT` (`config/puma.rb:4`). 512 MB ⇒ set `WEB_CONCURRENCY=1`. | `Dockerfile`, `config/puma.rb`, https://render.com/docs/docker |
| Redis command set | **Compatible with caveats.** App uses single-DB Redis: `EVAL` Lua CAS, `MULTI`, `SET NX EX`, `KEEPTTL`, `SCAN MATCH`, `XADD MAXLEN ~`, `ZADD`/`EXPIRE`, `INFO memory`, `PING`. Upstash supports EVAL (app already passes all keys via `keys:`, so opt-in strict key locking is irrelevant), Streams, SCAN, and `MULTI/EXEC` **over TCP only** — the app connects with `rediss://` TCP. `KEEPTTL` support is **UNVERIFIED** explicitly (Redis parity only) and must be smoke-tested. Upstash's Lua uses a **global lock by default**, so scripts must stay short — the app's CAS/limiter scripts already are. `INFO` is not billed but may be restricted; `Store.memory_stats` swallows errors, so the memory-ratio metric can silently disappear. | `lib/onetime/store.rb`, `lib/onetime/limiter.rb`, `lib/onetime/audit.rb`, https://upstash.com/docs/redis/commands/scripting/eval , https://upstash.com/docs/redis/commands/streams/xadd |
| **Database** | **No second datastore is needed or wanted.** Redis is the only datastore (D-002/D-004); `AUTH_MODE=full` (the only feature that would need Postgres + RabbitMQ) is deliberately 501. **Render Postgres Free is rejected** — 1 GB, expires 30 days after creation, no backups, data deleted after the grace period. Managed DBs on Railway start at Hobby. | `ARCHITECTURE.md` §5/§11, `DEPLOYMENT.md` §11, https://render.com/docs/free |
| `AUTH_MODE` | `disabled` = guest sharing only, webhook/account routes 403; `simple` enables them so K-46 has work to drain, with the account/data-loss caveat documented. | `lib/onetime/config.rb`, `lib/onetime/web/app.rb`, `API.md` |
| Boot contract | `Config.validate!` runs in `config.ru` and fails fast: `SECRET` ≥32 B, `HOST` without scheme, valid TTL/rate-limit/Redis URL/proxy CIDRs. No payment method involved. | `config.ru`, `lib/onetime/config.rb` |
| Health / cold start | Image HEALTHCHECK: 30 s start period; Compose: 15 s; CI tolerates 60 s. Render's ~1 min wake is at the edge — set platform health-check grace ≥60 s and expect initial 503s. `/robots.txt` does **not** wake a spun-down service (Render answers it itself). | `Dockerfile`, `compose.yaml`, `script/preflight*.sh`, https://render.com/docs/free |
| Backup / restore as a job | **Compatible.** `bin/ots backup`/`restore` need only Redis env + the same `SECRET`; output is ciphertext + emails + receipt metadata (0600), written to a writable path (`/tmp` on the runner). Must be client-side encrypted and copied off immediately. | `bin/ots`, `lib/onetime/backup.rb`, `DEPLOYMENT.md` §6 |
| Webhook worker off-host | **Compatible.** App is stateless; worker claims with Lua, dedups with `SET NX`, retries 3 times, needs only Redis + `SECRET` + outbound 443. `flock` in `script/webhook-worker.sh` is host-local; Redis locks handle cross-host races. | `lib/onetime/webhook.rb`, `bin/ots`, `script/webhook-worker.sh` |
| Worker on the sleeping web service | **Rejected.** Render Free has no one-off jobs or always-on background process and sleeps after 15 min. | https://render.com/docs/free |

## 3. Decision

**Recommended ₹0 stack:** Render Free Web Service (Dockerfile, managed TLS) **+** Upstash Redis
Free (`rediss://`, AUTH, eviction OFF, no card) **+** GitHub Actions scheduled job for the
webhook worker and backups **+** Cloudflare Pages Free for the static marketing site. Optional
Cloudflare edge in front of Render adds Universal SSL/DDoS but adds a second proxy hop that must
be reflected in `TRUSTED_PROXIES` and may leak bearer keys in CDN logs — it is **not** required
to close T-70 because Render already provides managed TLS.

**"Most secure compatible" rationale:** every alternative that removes a free-tier weakness also
breaks the ₹0 ceiling or the app: Koyeb removes the traffic-suspension clause but **requires a
card**; Oracle Always Free gives an always-on VM with disk but **requires a card** and full VM
ops; Railway has no custom domain and its $1 credit is consumed by Redis traffic; Fly.io has no
free tier; Cloudflare Workers/Containers cannot run Ruby/Puma; Redis Cloud Free has **no TLS**;
Render KV Free **loses all data on restart**; Cloudflare KV/Durable Objects need a full rewrite.
The chosen stack's two sharpest risks — no Redis IP allowlist and Render's external-egress
suspension threshold — are mitigated operationally in `FREE_TIER_DEPLOYMENT_PLAN.md` §7/§10 and
`INFRASTRUCTURE_SECURITY.md` §2/§8, and neither is hidden.

**Rejected:** Koyeb, Railway, Fly.io, Oracle Always Free (card required or ops cost), Render Free
Key Value (no persistence), Redis Cloud Free (no TLS), Render Postgres Free (30-day expiry, no
backups), Cloudflare Workers as a Ruby worker (no Ruby runtime, no worker HTTP endpoint in this
repo), Cloudflare KV/DO (not a drop-in). **Aiven Valkey Free** is the recorded datastore fallback
(~512 MB usable + backups) if Upstash Free is suspended or its token is exposed.

## 4. Spending safeguards (configure before any service is created)

| Provider | Safeguard |
|---|---|
| Render | **Do not add a payment method.** Set the build-pipeline **spend limit**; watch 750 h / 5 GB / 500 min; disable auto-deploy on unexpected PRs; no disks, dedicated IPs, autoscaling or larger instances. Keep external traffic well below the service-initiated threshold (no SCAN floods; use the documented rate limits). |
| Upstash | **Do not add a card** — it converts the DB to PAYG immediately. Confirm plan = Free, **Auto Upgrade OFF**, **eviction OFF**; alert on 500K commands/month, 250 MB, 10 GB bandwidth; only one database. Never enable "Eviction". |
| GitHub | Prefer a **public repository** (standard runners free); if private, set a hard budget below $12, `timeout-minutes`, `concurrency`, no larger runners, short artifact retention; no payment method. Scheduled jobs can be dropped — monitor last successful run. |
| Cloudflare | Free plan only; no paid Workers/Pages add-ons; keep Pages within 500 builds/month. |
| Global | No domain purchase (use `*.onrender.com` / `*.pages.dev`), no metered object storage beyond free R2, no paid alerting/status page. No agent adds a card, deploys, rotates a key or restores a backup. |

## 5. Unverified / flagged (do not treat as fact)

- Render's exact injected `PORT` value and whether a Cloudflare Tunnel request counts as "inbound"
  for the 15-min idle timer are **not documented**; verify during the first deploy.
- **Upstash `KEEPTTL` support** is inferred from Redis parity, not explicitly documented — smoke-test
  the exact command set on the free endpoint before relying on rotation/CAS rewrites.
- Upstash's older FAQ figure "10,000 requests/day" conflicts with the pricing page's 500,000
  commands/month; treat the **pricing page** as authoritative (fetched 2026-11-21).
- Redis Cloud Free's CIDR-rule availability conflicts between its plan table and notes; Aiven free
  TLS/allowlist defaults were not fully enumerated. Neither provider is in the chosen stack.
- Koyeb free wake time and third-party free Redis availability were not verified.
- Free-tier pages change; re-check all links before an operator executes the plan.
