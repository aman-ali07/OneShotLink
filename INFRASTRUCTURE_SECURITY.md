# Infrastructure security — zero-budget deployment

**Date: 2026-11-21. Status: design and controls review, not a deployed-system attestation.**
This document complements `FREE_TIER_DEPLOYMENT_PLAN.md` and `PROVIDER_COMPARISON.md`. It maps
the app's existing controls onto the proposed ₹0 stack, names the residual risks introduced by
free tiers, and gives the commands that must produce evidence before T-70, T-71 or K-46 can be
called resolved. **Public launch remains NO-GO until then.**

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

## 2. T-71 substitute controls — network isolation NOT achieved

The app's original T-71 assumption was a host-level `nft`/`ufw` rule against a Docker bridge.
On the free stack there is **no host bridge**: the datastore is a managed service reached over
the public Internet with mandatory TLS and token AUTH. **T-71 is not reproduced**: Upstash Free
has no IP allowlist, ACL or Private Link, so only TLS + AUTH remain. The controls below are
substitutes, not isolation, and must be described that way in the handoff record.

| Control | Free-tier implementation | Evidence to record |
|---|---|---|
| Transport encryption | `REDIS_URL=rediss://…`; Upstash TLS cannot be disabled | plaintext `redis://` connection attempt fails; `PING` over `rediss://` succeeds |
| Authentication | Upstash token via `REDIS_PASSWORD`, folded into the URL by `Config.validated_redis_url` | unauthenticated `PING` returns NOAUTH; app boots and passes `/health` |
| No public listener on app host | No Redis container/port exists on Render; nothing to firewall on the host | no `redis-server` process or 6379 listener in the app environment |
| No eviction of live secrets | Upstash eviction **OFF** by default; writes rejected at 250 MB — equivalent to the app's `noeviction` invariant. **Enabling eviction is CRITICAL**: the only policy, `optimistic-volatile`, removes TTL keys first and then random keys, i.e. it can destroy unexpired secrets | `CONFIG GET maxmemory-policy`-equivalent setting recorded in console; fill test on a scratch DB shows write rejection, not silent deletion; assert Eviction checkbox is OFF |
| No accidental paid upgrade | Plan Free, **Auto Upgrade OFF**, no card added (a card converts Free to PAYG immediately) | console screenshot/export of plan and auto-upgrade setting |
| Dedup/liveness | `SET NX`, Lua CAS and TTLs are unchanged | existing specs + worker proof |

**Residual risks (must be accepted in writing):** Upstash Free has **no IP allowlist, ACL,
Private Link, encryption at rest, multi-zone HA or uptime SLA**. It lists persistence and "primary
replicas", but failover behaviour on Free is undocumented — do not claim redundancy. Access
control is password + TLS only; a leaked token grants full read **and write** datastore access.
The off-host worker also holds `SECRET`, which can decrypt every unexpired record — treat the
worker secrets as production credentials. The **500k commands/month** allowance has **UNVERIFIED**
Free over-limit behaviour (official docs describe over-limit behaviour only for PAYG/Fixed).
`script/preflight.sh` must be run with `--skip-redis`; a "PASS" there proves **nothing** about
Redis isolation. Run the provider checks above and record them in `docs/GO_LIVE_HANDOFF.md`.

## 3. T-70 — TLS, cookies and proxy trust

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
- If Cloudflare is added in front, both provider egress ranges may need to be trusted, and CDN
  logs must not capture full bearer-key paths or response bodies (the webhook-create response
  carries the one-time signing secret).
- **Verification commands** (record all output):
  ```sh
  curl -sS -o /dev/null -w 'http=%{http_code} verify=%{ssl_verify_result}\n' https://<host>/health
  curl -sSI https://<host>/ | grep -i strict-transport-security
  curl -sS -D- -o /dev/null -X POST https://<host>/api/v3/signup \
    -H 'content-type: application/json' \
    -d '{"email":"probe@example.invalid","password":"preflight-only-password-9x"}' | grep -i set-cookie
  HOST=https://<host> script/preflight.sh --skip-redis     # must exit 0
  ```
  A throwaway signup is created; use a beta instance only.

## 4. K-46 — authenticated, retrying, monitored worker

- **Execution identity:** scheduled GitHub Actions job using environment `production` secrets
  (`SECRET`, `REDIS_URL`, `REDIS_PASSWORD`). No secret on argv; repo/environment protection is
  the authentication boundary. Use pinned action SHAs per project convention.
- **Idempotency and retries:** the app claims deliveries with a Lua ZSET + `SET NX`, dedups by
  delivery id, and retries each failed delivery up to three times with backoff
  (`webhook.rb:47-54,159-198`). The workflow adds three bounded shell attempts and a job
  `timeout-minutes`. **Idempotency comes from the app's stable delivery id + `SET NX`, not from
  the workflow**: a dropped run causes a delay, never a duplicate POST. The `concurrency` groups
  use `queue: max` so a worker run cannot cancel a pending backup (GitHub's default
  `queue: single` would).
- **SSRF/egress:** `WEBHOOK_ALLOW_PRIVATE` stays unset; the app refuses private/loopback URLs,
  pins the resolved IP and follows no redirects (`webhook.rb:238-245,281-317`). Restrict worker
  egress to TCP 443 where the platform permits it; block the cloud metadata address
  `169.254.0.0/16`.
- **Monitoring:** queue depth (`ZCARD webhook:queue`), last successful workflow run, and a
  de-duplicated GitHub issue for sustained backlog. GitHub can delay or drop scheduled runs and
  public repos auto-disable schedules after 60 days of inactivity — the monitor must detect
  *absence* of runs, not just failing runs.
- **Proof required before K-46 is resolved:** a signed POST to a test receiver, HMAC verification
  with the one-time signing secret, a replay that produces no second POST, and recorded
  liveness/alerts. See `FREE_TIER_DEPLOYMENT_PLAN.md §6.2`.

## 5. Protecting the sensitive HTTP surfaces

| Surface | Existing control | Free-tier deployment rule |
|---|---|---|
| `/metrics` | Uniform 404 unless `METRICS_ENABLED=true` **and** a bearer token passes constant-time compare; token never logged | Keep `METRICS_ENABLED=false`. If enabled: high-entropy `METRICS_TOKEN`, edge IP restriction, wrong-token attempts are throttled by the separate `RATE_LIMIT_METRICS_AUTH` scope (default 5) before the 404 is returned |
| Webhook create/list/delete/deliveries | Session + origin/CSRF proof, owner scoping, uniform 404 for foreign ids, `RATE_LIMIT_WEBHOOK` on mutations, private-URL refusal, IP pinning, HMAC signing | Use `AUTH_MODE=simple`; never set `WEBHOOK_ALLOW_PRIVATE`; disable CDN response-body logging; keep signing secret out of issues/logs |
| Account/receipt/burn/delete | Session + CSRF, per-scope rate limits, password re-prompt for account deletion, uniform 404 for foreign secrets | Same TLS/origin rules; shorten `SESSION_TTL` if the beta does not need 14-day sessions |
| Admin (`bin/ots`: customers, roles, audit, backup, rotate, migrate) | CLI-only — **no HTTP admin/audit/role routes exist** | Restrict Render dashboard membership and GitHub environment reviewers; shell/`docker exec` access equals full admin. Do not expose any future admin HTTP route publicly |
| Access logs | Method, redacted path, status, duration, request id; no body/query/cookies/IP (`request_logger.rb:23-54`) | Set `LOG_LEVEL=info`; keep short provider log retention; never log `bin/ots conceal/reveal` stdout |

## 6. Backup security and restore safety

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
   export time. Treat a missing backup as an incident, not a nuisance.

## 7. Spending safeguards as security controls

Resource exhaustion is both an availability and a cost risk. Enforce before launch: no payment
method on Render/Upstash/Cloudflare; Upstash Auto Upgrade **OFF**; Render build-pipeline spend
limit; GitHub hard budget/timeouts/concurrency and short artifact retention; no larger runners,
autoscaling, dedicated IPs, persistent disks or purchased domains. If any provider emails a
quota warning, treat it as an incident and pause the scheduler before investigating.

## 8. Residual risk register (requires operator acceptance)

| Risk | Why it matters on free tiers | Mitigation / acceptance |
|---|---|---|
| Sleeping web service | ~1 min cold start after 15 min idle; link recipients may see 503 | Honest beta copy; no always-on claims; worker runs externally |
| No Redis IP allowlist/ACL | Leaked token = full datastore access | Token in provider secret store only; rotate on suspicion; no token in logs/issues |
| Worker holds `SECRET` | Can decrypt every unexpired secret | Environment protection, egress restriction, short-lived credentials where possible |
| Upstash no HA/SLA/replicas | Provider incident can lose live secrets | Encrypted off-platform backup more often than shortest TTL; document RPO/RTO |
| Quota exhaustion | 250 MB → writes rejected (verified); 500k commands/month included, **Free over-limit behaviour UNVERIFIED**; bandwidth overage → Render/Upstash throttling | eviction off (fail closed with 503), alerts at 70–80%, low rate limits, no card, record first-deploy over-limit observation |
| Proxy/CIDR drift | Rate-limit buckets collapse or spoofing widens | Prefer `TRUST_PROXY=false` unless CIDRs verified; re-run preflight after provider changes |
| CDN/proxy logs | Cloudflare Logpush `http_requests` **will** record the full secret-key path in `ClientRequestURI` unless that field is excluded; keys are bearer capabilities | **No CDN in first beta**; if added, exclude `ClientRequestURI`/`ClientRequestPath`, disable request/response-body fields, shortest retention, restricted log-reader roles |
| GitHub schedule drops/60-day disable | Webhooks silently stop | Liveness monitor detects missing runs; manual `workflow_dispatch`; keep repo active |

## 9. Verification gate (evidence required)

```sh
# Code level (already green; re-run after any change)
/tmp/opencode/run-rspec.sh                         # backend suite green; record actual count/output

# Deployed infrastructure (operator runs; record output in docs/GO_LIVE_HANDOFF.md)
HOST=https://<host> script/preflight.sh --skip-redis        # T-70: exit 0
redis-cli -u redis://<host>:6379 PING                       # T-71: must fail
REDISCLI_AUTH='<token>' redis-cli -u 'rediss://<host>:6379' PING  # T-71: PONG
Workflow run log + signed POST + HMAC check + replay check   # K-46
```

**Assessment:** none of T-70, T-71 or K-46 is resolved by this document. They become resolved
only when the deployed-infrastructure commands above pass and their output is recorded. Until
then the public launch verdict stays **NO-GO**, as stated in `GO_LIVE_REMINDER.md`.
