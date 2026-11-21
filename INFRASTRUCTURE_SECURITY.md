# Infrastructure security — zero-budget deployment

**Date: 2026-11-22. Status: staging verification executed and evidenced; NOT a production attestation.**
This document complements `FREE_TIER_DEPLOYMENT_PLAN.md`, `PROVIDER_COMPARISON.md` and
`STAGING_TEST_REPORT.md`. It maps the app's controls onto the deployed ₹0 **staging** stack,
records what was actually verified on that host, and separates it from what still needs
production-host evidence. **Public launch remains NO-GO.** Four parallel `.claude/` specialists
(release-infra/T-70, network-troubleshooter/T-71, security-threat-model/K-46, and
security-reviewer+quality-database/metrics-and-backup) produced the Stage 18 evidence below;
every claim was re-read against command output, not taken from a report.

## 1. Trust boundaries and data classification

| Asset | Classification | Where it lives on the free stack | Protection |
|---|---|---|---|
| Secret plaintext | Most sensitive, never persisted | Process memory during create/reveal only | AES-256-GCM under `SECRET`; Lua compare-and-delete; `no-store` responses |
| Encrypted record | Sensitive | Upstash Redis `secret:object:*` | Ciphertext + per-record salt/IV/tag; metadata MAC; Redis TLS + AUTH |
| `SECRET` | Full decryption capability | Render env + GitHub Actions environment secrets | Provider secret store; never in git, argv, logs, or backups |
| Webhook signing secrets | Sensitive | `webhook:endpoint:*` | Encrypted with `Crypto.encrypt` under `SECRET`; returned once; never logged |
| Passphrase | Sensitive | Argon2id hash inside the record only | Access gate, **not** a second key (D-012); never in receipts/audit/logs |
| Receipt metadata | Internal | `secret:receipt:*` | Identifiers/status/timestamps only; 30-day retention after terminal state |
| Customer email / role | PII | `customer:*` hashes | Included in encrypted backups; no HTTP admin route |
| Audit stream | Internal | Upstash `audit:events` | Identifiers + daily-salted IP HMAC; count-trimmed; excluded from backups |
| Backups | Sensitive (PII + ciphertext) | Encrypted artifact / private free R2 | Client-side `gpg --symmetric --cipher-algo AES256` (passphrase via stdin), 0600 source, short retention. `openssl enc` cannot do GCM |

## 1a. Stage 18 evidence ledger — executed against staging (2026-11-22)

Staging host: `https://oneshotlink.onrender.com` (Render Free, public-but-unadvertised, synthetic
data only). Datastore: Upstash Redis Free `oneshotlink_redis_DB` (ap-south-1). Repo:
`aman-ali07/OneShotLink` (public). No credentials were present in or used from this environment.

| # | Control | Command run | Exact result | Verdict |
|---|---|---|---|---|
| 1 | TLS chain + HTTPS health | `curl -sS -o /dev/null -w 'http=%{http_code} verify=%{ssl_verify_result}\n' --max-time 20 https://oneshotlink.onrender.com/health` | `http=200 verify=0` | **VERIFIED on staging** |
| 2 | Public CA, not throwaway | `echo \| openssl s_client -servername oneshotlink.onrender.com -connect oneshotlink.onrender.com:443 \| openssl x509 -noout -issuer -subject -dates -ext subjectAltName` | `issuer=C = US, O = Google Trust Services, CN = WE1`; `subject=CN = onrender.com`; `notBefore=Nov 19 21:53:13 2026 GMT`, `notAfter=Feb 17 22:53:10 2027 GMT`; `DNS:onrender.com, DNS:*.onrender.com` | **VERIFIED on staging** |
| 3 | HSTS + hardening headers | `curl -sSI https://oneshotlink.onrender.com/` | `strict-transport-security: max-age=31536000; includeSubDomains`, `x-content-type-options: nosniff`, `x-frame-options: DENY`, CSP `'self'`-only, `referrer-policy: no-referrer`, `permissions-policy`, COOP/CORP `same-origin`, `x-robots-tag: noindex, nofollow` | **VERIFIED on staging** |
| 4 | HTTP→HTTPS | `curl -sS -o /dev/null -w 'code=%{http_code} redirect=%{redirect_url}\n' http://oneshotlink.onrender.com/` | `code=301 redirect=https://oneshotlink.onrender.com/` | **VERIFIED on staging** |
| 5 | Real preflight gate | `HOST=… PREFLIGHT_ALLOW_SIGNUP=1 script/preflight.sh --skip-redis` | `PREFLIGHT PASSED (1 skipped)`, **exit 0**; 7 PASS / 1 SKIP (T-71 skipped by request); `session cookie is Secure + HttpOnly + SameSite` | **VERIFIED on staging** (one authorized throwaway signup) |
| 6 | Redis network isolation | `dig +short exciting-marten-210970.upstash.io`; `nc -z -w 5 … 6379` | CNAME → 4 public A records (`13.234.196.111`, `13.200.201.38`, `3.109.113.215`, `3.111.138.221`); `Connection … 6379 port [tcp/redis] succeeded!`, `tcp_exit=0` | **T-71 NOT ACHIEVED** — endpoint publicly reachable |
| 7 | Mandatory TLS | `redis-cli -h … -p 6379 -a '' PING`; `redis-cli --tls -h … -p 6379 PING` (no token) | plaintext: `I/O error` … `Server closed the connection`, `ping1_exit=1`; TLS: `NOAUTH Authentication required` | **VERIFIED** — no PONG without TLS+token |
| 8 | Metrics hidden | `curl -sS -o /dev/null -w 'code=%{http_code}\n' https://oneshotlink.onrender.com/metrics` | `code=404`, uniform JSON `not_found` with `cache-control: no-store`, no `WWW-Authenticate`, no token/secret in headers or body | **VERIFIED on staging** (behavioural; config not attested) |
| 9 | Backup/restore tooling | `bash script/restore-drill.sh` (fresh run, throwaway Redis on `127.0.0.1:6413`, DB 15) | `Wrote 1 secret record(s) and 1 customer(s)`; `Restored …`; `live=drill-live-payload`, `spent=GONE`, `schema=1`, `migration_pending=no`; `RESTORE DRILL PASSED` | **VERIFIED locally** — tooling only, not a staging/production restore |
| 10 | Worker execution | `gh run view 44945858274 --log`; `gh run view 44945958171 --log` | `claimed=3 delivered=1 retrying=0 failed=2 skipped=0`; replay `claimed=0 delivered=0 …` | **VERIFIED manually invoked** — secrets GitHub-masked (`***`); no secret values in logs |
| 11 | Worker schedule/liveness | `gh api '…/actions/runs?event=schedule&per_page=10' --jq .total_count`; env query | `0` scheduled runs in the entire repo; 5 ops runs all `workflow_dispatch`; `staging` environment `protection_rules: 0`, `reviewers: []`; no `webhook-liveness` issue ever opened | **FAILED / OPEN** — see §4 |
| 12 | CDN in path (finding) | `dig +short oneshotlink.onrender.com` + response headers | CNAME `…cdn.cloudflare.net`; `server: cloudflare`, `cf-ray`, `cf-cache-status: DYNAMIC` | **FINDING** — contradicts the §8 "no CDN in first beta" posture |

**Independent re-run of the highest-consequence findings** (main agent, after the specialist
reports): `gh repo view --json nameWithOwner -q .nameWithOwner` → `aman-ali07/OneShotLink`;
`gh api …/actions/runs?event=schedule&per_page=10 | jq .total_count` → `0`; the five ops runs are
all `workflow_dispatch`; `gh api …/environments | jq …` → `github-pages 1` / `staging 0`;
`curl -sS -o /dev/null -w 'metrics_code=%{http_code}\n' …/metrics` → `metrics_code=404`.

**What remains unverifiable from this environment** (recorded, not claimed away): provider console
settings (Plan Free, Auto Upgrade OFF, Eviction OFF, no payment card); eviction policy
(`CONFIG GET maxmemory-policy` returned no value on managed Redis); Upstash 500k-command
over-limit behaviour; HA/failover/persistence on Free; an authenticated `PONG` with a valid token
(no credential here); app-internal env (`METRICS_ENABLED`, `HOST` form, `TRUSTED_PROXIES`);
cold-start timing was probed after a 16-minute idle window (first `/health` 200 in 0.635s, no 503 — see `STAGING_TEST_REPORT.md §4`, so the documented spin-down remains unobserved rather than disproved); and the receiver-side signed-POST /
HMAC-match / replay proof (recorded in `STAGING_TEST_REPORT.md §4`, not independently re-derivable
through `gh`). The staging token was pasted into an operator chat earlier and must be treated as
disclosed — rotate it, update Render + GitHub secrets, redeploy, re-verify `/health`, and purge
transcripts (operator action).

## 1b. Production-readiness fixes executed (2026-11-22)

| Fix | Command / evidence | Status |
|---|---|---|
| `staging` environment required reviewer | `gh api -X PUT repos/aman-ali07/OneShotLink/environments/staging -F 'reviewers[][id]=132501232'` → `protection_rules: 1`, reviewer `aman-ali07` | **DONE** (operator action no longer needed) |
| Worker liveness monitor | `.github/workflows/ci.yml` now has a `worker-liveness` job on CI's long-registered schedule; manual dispatch run `44948498621` logged `last successful ops run: 2026-11-21T20:22:41Z (29m ago)` / `worker healthy; no action` | **DONE in branch**, needs merge to `main` for the schedule to register |
| Live staging backup export | `bin/ots backup --out /out/stage18-staging-dump.json` → `Wrote 1 secret record(s) and 23 customer(s)`; `stat` → `600 24378`; parsed JSON `format=2`, `schema_version=1`, all nine namespaces present, 1 encrypted `secret:object` (`cipher=aes-256-gcm`, `v=3`, `meta_mac` present, no `secret_value`/`plaintext`), 24 receipts, 23 customers. The only synthetic string in the dump is a customer email | **VERIFIED** on staging data, file kept outside the repo at `/tmp/opencode/` |
| Cold start | 16-min idle probe: first `/health` 200 in 0.635s, 20/20 probes 200, reveal 200 in 0.572s — no spin-down observed | **PROBED**, documented caveat remains |

Still human-owned: rotate the disclosed token, choose the CDN posture, record Upstash console
settings, and give the final go/no-go signature. `ops-free-tier.yml` still shows **0 scheduled
runs**; the new CI-based monitor is the mitigation pending merge.

## 2. T-71 substitute controls — network isolation NOT achieved

The app's original T-71 assumption was a host-level `nft`/`ufw` rule against a Docker bridge.
On the free stack there is **no host bridge**: the datastore is a managed service reached over
the public Internet with mandatory TLS and token AUTH. **T-71 is not reproduced**: Upstash Free
has no IP allowlist, ACL or Private Link, so only TLS + AUTH remain. The controls below are
substitutes, not isolation, and must be described that way in the handoff record.

| Control | Free-tier implementation | Evidence on staging / still required |
|---|---|---|
| Transport encryption | `REDIS_URL=rediss://…`; Upstash TLS cannot be disabled | **VERIFIED this stage**: plaintext PING closed at TLS handshake; TLS without token → `NOAUTH`. Authenticated `PONG` was recorded in the earlier staging run (`STAGING_PHASE0.md §1b`), not re-run here (no credential) |
| Authentication | Upstash token via `REDIS_PASSWORD`, folded into the URL by `Config.validated_redis_url` | **VERIFIED this stage**: no PONG of any kind without a token. App boot with token + `/health redis=ok` recorded earlier |
| No public listener on app host | No Redis container/port exists on Render; nothing to firewall on the host | **Topology fact**: Render runs the app image only. Correction to a prior premise — this *workstation* has a loopback-only `redis-server 127.0.0.1:6379` and a transient drill container on `127.0.0.1:6413`; neither is published on `0.0.0.0` nor part of staging |
| No eviction of live secrets | Upstash eviction **OFF** by default; writes rejected at 250 MB — equivalent to the app's `noeviction` invariant. **Enabling eviction is CRITICAL**: the only policy, `optimistic-volatile`, removes TTL keys first and then random keys, i.e. it can destroy unexpired secrets | **UNVERIFIED on managed Redis**: `CONFIG GET maxmemory-policy` returned no value; operator must record the console Eviction=OFF setting. The 250 MB write-rejection behaviour is a local measurement only |
| No accidental paid upgrade | Plan Free, **Auto Upgrade OFF**, no card added (a card converts Free to PAYG immediately) | console screenshot/export of plan and auto-upgrade setting — operator-only |
| Dedup/liveness | `SET NX`, Lua CAS and TTLs are unchanged | existing specs + worker proof |

**Residual risks (must be accepted in writing):** Upstash Free has **no IP allowlist, ACL,
Private Link, encryption at rest, multi-zone HA or uptime SLA**. It lists persistence and "primary
replicas", but failover behaviour on Free is undocumented — do not claim redundancy. Access
control is password + TLS only; a leaked token grants full read **and write** datastore access —
and the staging token has already been disclosed in chat, so rotation is required. The off-host
worker also holds `SECRET`, which can decrypt every unexpired record — treat the worker secrets
as production credentials. The **500k commands/month** allowance has **UNVERIFIED** Free
over-limit behaviour. `script/preflight.sh --skip-redis` PASS proves **nothing** about Redis
isolation; record the provider checks in `docs/GO_LIVE_HANDOFF.md`.

## 3. T-70 — TLS, cookies and proxy trust

**Staging result (not production closure):** all app-side checks on
`https://oneshotlink.onrender.com` passed — system-trust chain (`verify=0`), public CA
(Google Trust Services `WE1`, SAN `*.onrender.com`), HSTS, hardening headers, `Secure`/`HttpOnly`/
`SameSite` cookie, HTTP→HTTPS 301, and the real `preflight.sh` exiting 0 with one authorized
skip (T-71). T-70 requires a **real production hostname with a clean preflight** — every
applicable TLS/header/cookie check passing; on managed Redis the isolation check is necessarily
skipped and must be recorded as such, never treated as proof. Staging's shared `*.onrender.com`
domain is not a production hostname. **T-70 remains OPEN.**

**CDN finding:** the staging host resolves via `…cdn.cloudflare.net` and returns
`server: cloudflare` / `cf-ray`. A CDN *is* in the path, contrary to §8's "no CDN in first beta"
posture. Operator must verify that Cloudflare Logpush excludes `ClientRequestURI` /
`ClientRequestPath` (bearer keys are in the path), that response-body logging is off, and that
`TRUST_PROXY` / forwarded-header handling is correct for both provider egress ranges. None of
this is externally verifiable. Header origin (app vs proxy injection) is also not attributable
from outside, and `HOST`/`TRUSTED_PROXIES` values cannot be read remotely.

- Render Free provides **managed TLS** on `*.onrender.com`; set the app's `HOST` to that exact
  hostname **without a scheme**. `SSL=true` gives `Secure`/`HttpOnly`/`SameSite` cookies and HSTS
  (`max-age=31536000; includeSubDomains`). `HOST` as a URL yields `https://https://…` links and a
  broken cookie origin (`DEPLOYMENT.md §4.1`).
- **Origin proof** is derived from `Config.base_url`, not from `X-Forwarded-Host`; the app never
  trusts forwarded host headers (`app.rb:503-509`). This is why proxy mistakes cannot be turned
  into cross-site login.
- **Rate-limit identity** is the one proxy-sensitive control: `client_id` walks `X-Forwarded-For`
  right-to-left only when the immediate peer is in `TRUSTED_PROXIES` (`app.rb:174-207`). If the
  proxy CIDRs cannot be verified, set `TRUST_PROXY=false`: all users share one bucket (coarse
  but fail-safe) rather than letting a spoofed XFF mint unlimited buckets. A malformed CIDR
  fails boot (`config.rb:216-222`).
- **Verification commands** (record all output; §1a shows the staging results):
  ```sh
  curl -sS -o /dev/null -w 'http=%{http_code} verify=%{ssl_verify_result}\n' https://<host>/health
  curl -sSI https://<host>/ | grep -i strict-transport-security
  HOST=https://<host> script/preflight.sh --skip-redis     # must exit 0
  ```
  A throwaway signup is created when `PREFLIGHT_ALLOW_SIGNUP=1`; use a beta instance only.

## 4. K-46 — authenticated, retrying, monitored worker: NOT CLOSED

- **Applied workflow:** `.github/workflows/ops-free-tier.yml` exists on the default branch and
  is `state: active` (workflow id `426262390`) — the `deploy/free-tier/` template was actually
  applied. (Its first comment lines still say "PROPOSED… not applied"; cosmetic, no security
  effect.) All `uses:` refs are pinned to full SHAs.
- **Manual execution works, without leaking secrets:** run `44945858274` logged
  `claimed=3 delivered=1 retrying=0 failed=2 skipped=0`; replay `44945958171` logged
  `claimed=0 delivered=0 retrying=0 failed=0 skipped=0`. Env blocks in the log are GitHub-masked
  (`SECRET: ***`, `REDIS_URL: ***`, `REDIS_PASSWORD: ***`); a 285-line scan found no token/PAT/
  signature values. `WEBHOOK_ALLOW_PRIVATE:` is empty, so the SSRF guard is on.
- **Receiver-side delivery proof:** `STAGING_TEST_REPORT.md §4` records one signed POST whose
  `X-OneShotLink-Signature` matched an independently computed HMAC-SHA256, with a replay that
  produced no second POST. This is earlier recorded evidence, not independently re-derivable
  via `gh` in this stage.

**Findings that keep K-46 open (all from live `gh` API/run queries):**

| Dimension | Result |
|---|---|
| Scheduled (cron) runs | **0 total** in the repo (`total_count: 0`); all 5 ops runs were `workflow_dispatch`. The `17,47 * * * *` + `23 3 * * *` crons have never fired on staging. |
| `staging` environment protection | `protection_rules: 0`, `reviewers: []` — the documented "required reviewers are the authentication boundary" is **unfulfilled**. All four secret *names* exist (`SECRET`, `REDIS_URL`, `REDIS_PASSWORD`, `BACKUP_PASSPHRASE`); no values were printed. |
| Missing-run detection | **Not implemented** — only a comment in the workflow and prose in `deploy/free-tier/README.md §5`. No job/script checks the last-successful-run timestamp. A silently stopped worker is undetected. |
| Queue-depth alert | Present but `if: failure()` only, `>200` threshold, dedup by `gh issue`. No delivery-age check; when Redis is unreachable it logs `webhook queue depth: unknown` and opens nothing. No `webhook-liveness` issue has ever existed. |
| Worker egress | `WEBHOOK_ALLOW_PRIVATE` is empty (app SSRF guard on), but **no egress restriction to TCP 443 and no `169.254.0.0/16` block** exists in the workflow — the §4 operator control is unimplemented on GitHub-hosted runners. |

**Consequence:** `STAGING_TEST_REPORT.md §4`'s "CLOSED for staging" is correct only for the
*manual signed-delivery* dimension. On "scheduled + monitored" K-46 is **NOT closed for staging
either**. Operator actions: make a real scheduled run fire, add required reviewers to the
`staging` environment, implement missing-run detection, widen the queue alert to lag/success
cases and `unknown`, and restrict worker egress.

- **Idempotency and retries:** the app claims deliveries with a Lua ZSET + `SET NX`, dedups by
  delivery id, and retries each failed delivery up to three times with backoff
  (`webhook.rb:47-54,159-198`). The workflow adds three bounded shell attempts and a job
  `timeout-minutes`. **Idempotency comes from the app's stable delivery id + `SET NX`, not from
  the workflow**: a dropped run causes a delay, never a duplicate POST. `concurrency.queue: max`
  prevents a worker run from cancelling a pending backup.
- **Proof still required before K-46 is resolved:** a scheduled run firing on cadence, an
  automated missing-run alert, environment reviewers, queue-lag alerting, restricted egress,
  plus the recorded signed delivery/HMAC/replay (already on file for staging).

## 5. Protecting the sensitive HTTP surfaces

**Metrics evidence this stage:** `GET /metrics` on staging → `code=404` with JSON `not_found`,
`cache-control: no-store`, full hardening headers, and **no** `WWW-Authenticate`, 401 or 403 —
the endpoint is not advertised. No token was guessed or supplied. Code-level controls re-read:
`app.rb:141-149` (`metrics_authorized?` — empty token fails closed, then
`Crypto.secure_compare`), `app.rb:669-689` (`METRICS_ENABLED` gate, uniform 404, `:metrics_auth`
on failure vs `:metrics` on success), `config.rb:100-101` (≥32-byte token), `config.rb:53`
(default off), `request_logger.rb:35-54` (no headers/body/cookies/IP logged), and
`metrics.rb:93-94` (build version deliberately not rendered; `/health` still reports `version`).
The staging config values themselves are not externally attested.

| Surface | Existing control | Free-tier deployment rule |
|---|---|---|
| `/metrics` | Uniform 404 unless `METRICS_ENABLED=true` **and** a bearer token passes constant-time compare; token never logged | Keep `METRICS_ENABLED=false`. If enabled: high-entropy `METRICS_TOKEN`, edge IP restriction, wrong-token attempts throttled by the separate `RATE_LIMIT_METRICS_AUTH` scope (default 5) before the 404 is returned |
| Webhook create/list/delete/deliveries | Session + origin/CSRF proof, owner scoping, uniform 404 for foreign ids, `RATE_LIMIT_WEBHOOK` on mutations, private-URL refusal, IP pinning, HMAC signing | Use `AUTH_MODE=simple`; never set `WEBHOOK_ALLOW_PRIVATE`; disable CDN response-body logging (CDN is present on staging — see §3); keep signing secret out of issues/logs |
| Account/receipt/burn/delete | Session + CSRF, per-scope rate limits, password re-prompt for account deletion, uniform 404 for foreign secrets | Same TLS/origin rules; shorten `SESSION_TTL` if the beta does not need 14-day sessions |
| Admin (`bin/ots`: customers, roles, audit, backup, rotate, migrate) | CLI-only — **no HTTP admin/audit/role routes exist** | Restrict Render dashboard membership and GitHub environment reviewers (currently 0 — see §4); shell/`docker exec` access equals full admin. Do not expose any future admin HTTP route publicly |
| Access logs | Method, redacted path, status, duration, request id; no body/query/cookies/IP (`request_logger.rb:23-54`) | Set `LOG_LEVEL=info`; keep short provider log retention; never log `bin/ots conceal/reveal` stdout |

## 6. Backup security and restore safety

**Restore evidence:** a fresh `bash script/restore-drill.sh` run completed with
`RESTORE DRILL PASSED`. The script proves isolation at `script/restore-drill.sh:2-6,9-22,30-35,56`:
a throwaway `redis:7.4-alpine` container published only on `127.0.0.1:6413`, DB 15 only, a test
`SECRET_VALUE` printed nowhere, and a `trap cleanup EXIT` that removes the container and temp
files. Output: `live=drill-live-payload`, `spent=GONE` (the consumed secret was **not**
resurrected), `schema=1`, `migration_pending=no`. This proves **the tooling works**, not a
staging/production restore; no live data was touched.

Backup properties re-read against code and specs: format v2 with `schema_version`
(`backup.rb:20-26,44-49,98`; `ops_spec.rb:183-198`); `0600` source file via
`File.open(..., 0o600)` + atomic rename (`backup.rb:54-61`; `ops_spec.rb:232-238`); TTL, zset and
set restoration including scores (`backup.rb:202-253`; `ops_spec.rb:281-315,338-353`); and the
`--force` overwrite guard (`backup.rb:77,89-92`; `ops_spec.rb:240-254`).

1. Run `bin/ots backup --out /tmp/dump.json` as a one-shot job with the same Redis env and
   `SECRET`. The dump is `0600` JSON containing ciphertext, Argon2id hashes, customer emails,
   receipt metadata and webhook config — **no plaintext or `SECRET`**, but PII-bearing.
2. Encrypt it client-side with `gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0
   --symmetric --cipher-algo AES256` (passphrase piped from `BACKUP_PASSPHRASE`, never in argv)
   before uploading to a private Actions artifact (7-day retention) or a private free R2 bucket.
   `openssl enc` with an AEAD cipher is **invalid** (OpenSSL's `enc` has never supported GCM);
   don't substitute bare CBC without a MAC. Delete the plaintext file immediately.
3. Never commit dumps; never restore into the live instance. Use `script/restore-drill.sh` on a
   scratch Redis. Verify format v2, `schema_version`, TTLs, zsets, and the `--force` overwrite
   guard (`spec/unit/ops_spec.rb:138-310`).
4. Schedule more often than the shortest TTL; a restored secret gets only the TTL it had at
   export time. Treat a missing backup as an incident, not a nuisance. The encryption passphrase
   and artifact/R2 destination are operator-owned and were not verifiable here.

## 7. Spending safeguards as security controls

Resource exhaustion is both an availability and a cost risk. Enforce before launch: no payment
method on Render/Upstash/Cloudflare; Upstash Auto Upgrade **OFF**; Render build-pipeline spend
limit; GitHub hard budget/timeouts/concurrency and short artifact retention; no larger runners,
autoscaling, dedicated IPs, persistent disks or purchased domains. If any provider emails a
quota warning, treat it as an incident and pause the scheduler before investigating. Provider
console settings were not inspectable in this stage.

## 8. Residual risk register (requires operator acceptance)

| Risk | Why it matters on free tiers | Mitigation / acceptance |
|---|---|---|
| Sleeping web service | ~1 min cold start after 15 min idle; link recipients may see 503 | Honest beta copy; no always-on claims; worker runs externally. **Probed** after 16 min idle: first `/health` 200 in 0.635s, all 20 probes 200, no 503; documented spin-down not observed — treat as an open caveat, not a measured failure |
| No Redis IP allowlist/ACL | Leaked token = full datastore access; staging token already disclosed in chat | **Rotate now**, update Render + GitHub secrets, redeploy, re-verify health; token in provider secret store only; no token in logs/issues |
| Worker holds `SECRET` | Can decrypt every unexpired secret | Environment protection (**currently 0 rules** on `staging`), egress restriction (**not implemented**), short-lived credentials where possible |
| Upstash no HA/SLA/replicas | Provider incident can lose live secrets | Encrypted off-platform backup more often than shortest TTL; document RPO/RTO |
| Quota exhaustion | 250 MB → writes rejected (verified locally); 500k commands/month included, **Free over-limit behaviour UNVERIFIED**; bandwidth overage → Render/Upstash throttling | eviction off (fail closed with 503), alerts at 70–80%, low rate limits, no card, record first-deploy over-limit observation |
| Proxy/CIDR drift | Rate-limit buckets collapse or spoofing widens | Prefer `TRUST_PROXY=false` unless CIDRs verified; re-run preflight after provider changes |
| CDN/proxy logs — **OBSERVED, not hypothetical** | `dig` shows `…cdn.cloudflare.net` and responses carry `server: cloudflare`; Cloudflare Logpush `http_requests` **will** record the full secret-key path in `ClientRequestURI` unless excluded; keys are bearer capabilities | If CDN stays, exclude `ClientRequestURI`/`ClientRequestPath`, disable request/response-body fields, shortest retention, restricted log-reader roles — or remove the CDN for the beta; operator decision required |
| GitHub schedule never fired | 0 scheduled runs; all worker runs were manual; public repos can disable schedules after 60 days | Make a cron run fire, implement missing-run detection, keep repo active; do not rely on manual dispatch |

## 9. Verification gate — what was run and what remains

**Executed in Stage 18 (output recorded in §1a):**

```sh
curl -sS -o /dev/null -w 'http=%{http_code} verify=%{ssl_verify_result}\n' https://oneshotlink.onrender.com/health   # 200 / 0
curl -sSI https://oneshotlink.onrender.com/                                      # HSTS + hardening headers
curl -sS -o /dev/null -w 'code=%{http_code} redirect=%{redirect_url}\n' http://oneshotlink.onrender.com/           # 301 → https
HOST=https://oneshotlink.onrender.com PREFLIGHT_ALLOW_SIGNUP=1 script/preflight.sh --skip-redis                    # exit 0, 1 skipped
echo | openssl s_client -servername oneshotlink.onrender.com -connect oneshotlink.onrender.com:443 | openssl x509 -noout -issuer -subject -dates -ext subjectAltName
dig +short exciting-marten-210970.upstash.io; nc -z -w 5 exciting-marten-210970.upstash.io 6379                    # publicly reachable
redis-cli -h exciting-marten-210970.upstash.io -p 6379 -a '' PING                 # I/O error / server closed
redis-cli --tls -h exciting-marten-210970.upstash.io -p 6379 PING                 # NOAUTH Authentication required
curl -sS -o /dev/null -w 'code=%{http_code}\n' https://oneshotlink.onrender.com/metrics                             # 404
bash script/restore-drill.sh                                                      # RESTORE DRILL PASSED (throwaway)
gh run view 44945858274 --log | grep 'claimed='                                  # claimed=3 delivered=1 ...
gh api 'repos/aman-ali07/OneShotLink/actions/runs?event=schedule&per_page=10' --jq .total_count                     # 0
```

**Still operator-owned (not run here; no credentials/authority):** a custom production hostname
with a preflight exit 0 and every applicable check passing (T-70; the managed-Redis isolation
skip is expected and recorded, not proof); provider-console evidence for Upstash plan/Auto
Upgrade/Eviction and accepted no-isolation residual (T-71); rotating the disclosed staging token;
CDN log-field exclusion or removal; a real scheduled webhook run, `staging` environment reviewers,
missing-run detection, queue-lag alerting and worker egress restriction (K-46); a live encrypted
backup export/inspection and a restore **on a copy**; and the final
signed go/no-go.

**Assessment:** T-70 is **verified on the staging hostname only, not closed**; T-71 is **not
achieved** (substitute controls TLS + token AUTH verified, no isolation); K-46 is **not closed**
(manual signed delivery evidenced, schedule and monitoring absent); metrics hiding and restore
tooling are **verified** within their stated scope. None of these results authorizes a public
"production ready" claim. The verdict stays **NO-GO**, as stated in `GO_LIVE_REMINDER.md`.
