# Go-live reminder — OneShotLink (authoritative pre-launch checklist)

**Status of this note: updated 2026-11-22 (Stage 18 infrastructure verification). Public launch verdict: NO-GO.**

This is the single launch-readiness checklist. Every remaining item is classified with one of
four labels: **FIXED AND VERIFIED**, **REQUIRES HUMAN APPROVAL**, **REQUIRES SERVER OPERATOR**,
or **BLOCKED**. A green test suite proves repository behaviour, **not** that a public host is
configured. Until the operator items produce recorded evidence, call the service
**production-packaged, go-live pending** or **free-tier beta** — never "production ready".
Do not claim zero-knowledge (D-012): the passphrase is an access gate, not a second key.

Local evidence: **307 backend examples, 0 failures** (single clean run), 35 Vitest tests, eight browser
journeys, clean typecheck/build, brand sweep, dependency audits, isolated restore drill, and the
TLS rehearsal. All are **code-level** facts; none closes an operator item.

**Staging evidence (Stage 18, 2026-11-22):** four parallel `.claude/` specialists tested the
actual staging host (`https://oneshotlink.onrender.com`), the Upstash endpoint, GitHub Actions
and the local restore tooling. Full commands and verbatim output are in
`INFRASTRUCTURE_SECURITY.md §1a`; the short version is in the "Stage 18" section below. It
**narrows** several items but does not change the NO-GO verdict: T-70 is verified on the staging
hostname only, T-71 is not achieved, and K-46 has no scheduled or monitored execution.

**Zero-budget path:** the ₹0/month architecture in `FREE_TIER_DEPLOYMENT_PLAN.md`,
`PROVIDER_COMPARISON.md` and `INFRASTRUCTURE_SECURITY.md` (Render Free + Upstash Redis Free +
GitHub Actions + Cloudflare Pages) is **deployed for staging only**, with synthetic data and an
unadvertised URL. Staging evidence does not close T-70, T-71 or K-46 for production.

## Master classification (every remaining item)

| Item | Classification | Owner | Evidence / required next action |
| --- | --- | --- | --- |
| Core lifecycle, accounts, burn, passphrase gate, file secrets | **FIXED AND VERIFIED** | Repo | 307 specs + browser journeys green |
| SA-01…SA-31 security findings | **FIXED AND VERIFIED** | Repo | `SECURITY_AUDIT.md` §3/§13; no S1/S2 open in code |
| D-012b per-secret passphrase budget (900 s / 5 guesses) | **FIXED AND VERIFIED** | Repo | `RATE_LIMIT_PASSPHRASE*`, `Limiter` scope, red→green spec, decision in `DECISIONS.md` |
| D-retention (no raw IPs in audit) | **FIXED AND VERIFIED** | Repo | `audit.rb#ip_reference` daily HMAC, decision recorded |
| Backup carries `schema:version` | **FIXED AND VERIFIED** | Repo | `backup.rb`, `ops_spec` round-trip + corrupt-marker rejection specs |
| Backup/restore tooling on isolated Redis | **FIXED AND VERIFIED** | Repo | Fresh `script/restore-drill.sh` → `RESTORE DRILL PASSED` (`spent=GONE`, `schema=1`); throwaway container only — **not** a production restore |
| `/metrics` hidden when disabled | **FIXED AND VERIFIED** | Repo + staging | Live `GET /metrics` → uniform `404` with `no-store`, no auth challenge; code gate re-read (`app.rb:141-149,669-689`). Staging config value not externally attested |
| Webhook worker wrapper + SSRF/egress guard in code | **FIXED AND VERIFIED** | Repo | `script/webhook-worker.sh`, `docs/ops/webhook-worker.md`, `bash -n` OK; `WEBHOOK_ALLOW_PRIVATE` empty in the Actions env |
| Protected-path review (crypto.rb, app.rb, compose.yaml) | **REQUIRES HUMAN APPROVAL** | Human | Diffs re-read; sign-off required before promotion (§ below) |
| H4 build / promote / deploy | **REQUIRES HUMAN APPROVAL** | Human | Agents report only; never auto-merge or deploy |
| H6 destructive drills on a live instance (backup restore, key rotation) | **REQUIRES HUMAN APPROVAL** | Human | Run on a copy per `RUNBOOK.md` §1/§6; agents never restore into live |
| H8 legal pages, name check, go/no-go signature | **REQUIRES HUMAN APPROVAL** | Human | Trademark/lawyer review + sign-off in `docs/GO_LIVE_HANDOFF.md` |
| Open product decisions: D-token, D-request-mode | **REQUIRES HUMAN APPROVAL** | Product | Record in `docs/DECISIONS.md` before related code (D-017 deferral stands) |
| T-70 TLS on a real hostname | **REQUIRES SERVER OPERATOR** | Operator | **Staging verified** (public CA chain, HSTS/headers/cookie flags/301, `preflight.sh` exit 0). Production hostname + a clean preflight (all applicable checks pass; managed-Redis isolation skip recorded, never treated as proof) still required |
| T-71 Redis host firewall | **REQUIRES SERVER OPERATOR** | Operator | **NOT ACHIEVED** on Upstash Free: endpoint publicly reachable; only mandatory TLS + token AUTH verified (plaintext closed, TLS → `NOAUTH`). No IP allowlist/ACL/Private Link. Console settings + written risk acceptance required |
| Disclosed staging token | **REQUIRES SERVER OPERATOR** | Operator | Token pasted in an operator chat earlier; rotate in Upstash, update Render + GitHub secrets, redeploy, re-verify `/health`, purge transcripts |
| CDN in path on staging | **REQUIRES SERVER OPERATOR** | Operator | `…cdn.cloudflare.net` + `server: cloudflare` observed; contradicts "no CDN in first beta". Either exclude `ClientRequestURI`/`ClientRequestPath` and body logging from Logpush, or remove the CDN; verify `TRUST_PROXY`/CIDRs |
| K-46 schedule/monitor worker + egress firewall | **REQUIRES SERVER OPERATOR** | Operator | **Manual signed delivery evidenced** (run `44945858274`, HMAC + replay on file). **0 scheduled runs ever**, `staging` env has **0 protection rules**, missing-run detection **not implemented**, no queue-lag alert, no egress restriction. NOT closed even for staging on schedule/monitor |
| Zero-budget architecture ownership | **REQUIRES HUMAN APPROVAL** | Operator + repo owner | `FREE_TIER_DEPLOYMENT_PLAN.md`, `PROVIDER_COMPARISON.md`, `INFRASTRUCTURE_SECURITY.md` reviewed; staging accounts/services exist; production changes unapproved |
| Persistent backup volume on host / live encrypted export | **REQUIRES SERVER OPERATOR** | Operator | `/backups` on a persistent disk; verify a live `bin/ots backup` export + GPG artifact and a restore **on a copy**. Local drill proves tooling only |
| **Public launch** | **BLOCKED** | — | T-70 production host, T-71 isolation/risk acceptance, K-46 schedule+monitor, token rotation and CDN decision have no production evidence; human gates unsigned |
| Claim that the ₹0 stack is production-ready or that gates are closed | **BLOCKED** | — | Only staging behaviour and code were tested; no production deploy or authorization exists |

No item is left unclassified. "Code-level ready" means a command in this repository passed;
"staging-verified" means the control passed on the actual staging host; "server-level verified"
means it passed on the production host. **A rehearsal or a staging PASS is preparation, not proof.**

## Stage 18 — infrastructure security verification (evidence summary)

Four `.claude/` specialists (release-infra, network-troubleshooter, security-threat-model,
security-reviewer + quality-database) ran in parallel. Exact commands and output:
`INFRASTRUCTURE_SECURITY.md §1a`.

| Control | Evidence | Verdict |
| --- | --- | --- |
| TLS (T-70, staging) | `/health` `http=200 verify=0`; issuer Google Trust Services `WE1`, SAN `*.onrender.com`, valid to 2027-02-17; HSTS `max-age=31536000; includeSubDomains`; nosniff/frame/CSP; HTTP 301→HTTPS; `preflight.sh --skip-redis` **exit 0**, `PREFLIGHT PASSED (1 skipped)` with `Secure`+`HttpOnly`+`SameSite` cookie | **VERIFIED on staging only — T-70 still OPEN** (no production hostname; preflight must be clean on all applicable checks) |
| Redis network (T-71) | Upstash endpoint resolves to 4 public IPs and TCP/6379 is reachable (`tcp_exit=0`); plaintext PING → `I/O error`/`Server closed the connection`; TLS without token → `NOAUTH Authentication required` | **NOT ACHIEVED** — substitute controls (mandatory TLS + AUTH) verified, no isolation |
| Metrics | `GET /metrics` → `code=404`, JSON `not_found`, `cache-control: no-store`, no `WWW-Authenticate`; no token supplied | **VERIFIED** on staging (config not attested) |
| Backup/restore | Fresh `bash script/restore-drill.sh` → `RESTORE DRILL PASSED`, `live=drill-live-payload`, `spent=GONE`, `schema=1`, `migration_pending=no` (throwaway Redis, loopback `127.0.0.1:6413`) | **VERIFIED tooling only** — no staging/live restore |
| Webhook delivery | `gh run view 44945858274 --log`: `claimed=3 delivered=1 retrying=0 failed=2 skipped=0`; replay `44945958171`: `claimed=0`; GitHub-masked secrets, no values in logs; earlier receiver proof: HMAC match + no replay POST | **VERIFIED manual path only** |
| Webhook schedule/monitor | `gh api …/actions/runs?event=schedule` → `total_count: 0`; 5 ops runs all `workflow_dispatch`; `staging` env `protection_rules: 0`; no missing-run job; alert failure-only and never fired; no egress restriction | **FAILED / OPEN** — K-46 not closed |
| CDN finding | `dig` → `…cdn.cloudflare.net`; `server: cloudflare`, `cf-ray`, `cf-cache-status: DYNAMIC` | **FINDING** — operator decision required |

## Required human actions

- [ ] **H1 — Real HTTPS hostname (T-70).** Staging passed the full app-side TLS gate with a public
      CA on `*.onrender.com`. Still required: a production hostname on the real domain, `SSL=true`,
      `HOST=<host without scheme>`, verified `TRUST_PROXY`/CIDRs (or `TRUST_PROXY=false`), then
      `HOST=https://<real-host> script/preflight.sh` — clean on all applicable checks. On managed
      Redis the isolation check is intentionally skipped and must be recorded as such, never as
      proof of T-71. Proof: output in
      `docs/GO_LIVE_HANDOFF.md`. (§ T-70 below)
- [ ] **H1b — Resolve the CDN finding.** Staging is fronted by Cloudflare. Either remove it for
      the beta or configure Logpush to exclude `ClientRequestURI`/`ClientRequestPath` and
      request/response bodies, restrict log readers, and verify proxy trust. Bearer keys live in
      the URL path.
- [ ] **H2 — Redis isolation (T-71) and token rotation.** Free path: Upstash has **no** IP
      allowlist/ACL/Private Link, so T-71 is not achieved; accept that residual in writing after
      recording TLS + AUTH evidence (plaintext closed, TLS → `NOAUTH`). Console settings: Plan
      Free, Auto Upgrade OFF, Eviction OFF, no card. **Rotate the token disclosed in chat**, update
      Render + GitHub secrets, redeploy, re-verify `/health`. Self-managed path: still apply
      `DEPLOYMENT.md §4.0` on each host. (§ T-71 below)
- [ ] **H3 — Schedule and monitor the webhook worker (K-46).** Staging proved only the manual
      signed-delivery path. Required: make a **cron run actually fire**, add required reviewers to
      the `staging` environment, implement missing-run detection (the current check is prose only),
      widen queue alerting to lag/success/`unknown`, and restrict worker egress to 443 with
      `169.254.0.0/16` blocked. A single successful local delivery is **not** proof. (§ K-46 below)
- [ ] **H4 — Deploy/promote yourself.** Agents never push, deploy, or auto-merge.
- [ ] **H5 — Approve protected-path edits.** See the review table below.
- [ ] **H6 — Run destructive drills on a copy yourself.** The isolated restore drill passed but is
      **not** a production restore. Never let an agent restore into a live instance or rotate `SECRET`.
- [ ] **H7 — Record remaining product decisions.** D-012b and D-retention are now recorded;
      D-token and D-request-mode remain.
- [ ] **H8 — Legal pages, name check, go/no-go signature.**

## Protected-path review (requirement 7 — re-read, pending human sign-off)

| Path | What changed | Review result |
| --- | --- | --- |
| `lib/onetime/crypto.rb` | Reject any stored `cipher` value other than `aes-256-gcm` before constructing `OpenSSL::Cipher`; typed integrity error instead of raw `RuntimeError`. | Sound. AEAD key/IV/tag path unchanged; no plaintext or key handling changed. Spec proves tampering fails closed. **Needs human approval.** |
| `lib/onetime/web/app.rb` | Canonical `HARDENING_HEADERS` shared by default headers and static assets; strict JSON media type; redacted audit references; metadata MAC on previews; separate limiter scopes (respond/burn/metrics/passphrase); `/metrics` bearer-token gate. | Sound. No auth bypass introduced; reveal still verify→decrypt→consume; request key never logged. **Needs human approval.** |
| `compose.yaml` | `TRUST_PROXY=true` + loopback-only trusted proxies; `APP_BIND=127.0.0.1`; `REDISCLI_AUTH` in healthcheck; all new limiter scopes and `METRICS_TOKEN` passed through. | Sound for the documented same-host proxy topology; `client_id` ignores XFF unless the direct peer is trusted. **Needs human approval.** |

Full diff review notes are in `SECURITY_AUDIT.md §14`.

## T-70 — real HTTPS hostname (free tier, ₹0)

1. **Already evidenced on staging:** `https://oneshotlink.onrender.com` serves `/health` with
   `verify=0`, a Google Trust Services public certificate covering `*.onrender.com`, HSTS, the
   full hardening header set, a `Secure`+`HttpOnly`+`SameSite` session cookie, an HTTP→HTTPS 301,
   and `PREFLIGHT PASSED (1 skipped)` (exit 0). This validates the app/proxy side, **not** T-70.
2. Deploy on the production hostname; set app env **in the provider's dashboard**, never in git:
   `SECRET` (new, not the staging one), `REDIS_URL`/`REDIS_PASSWORD`, `HOST=<host without scheme>`,
   `SSL=true`, `TRUST_PROXY=true` with verified proxy CIDRs (or `false` if unverified), and
   `METRICS_TOKEN` if metrics are enabled. Note the two `HOST` forms: preflight takes a **URL**,
   the app takes `host:port` with no scheme.
3. Check: `curl -fsS https://<host>/health` and `HOST=https://<host> script/preflight.sh` —
   on managed Redis, `--skip-redis` is mandatory, so the gate must otherwise be clean; on a
   self-managed stack use the full preflight with 0 skips. The preflight creates a throwaway
   signup — run it on a beta instance. Rehearse locally with `script/tls-rehearsal.sh --with-redis`.
4. Record the exact output in `docs/GO_LIVE_HANDOFF.md`. Without a production hostname and that
   output T-70 stays open. Proxy trust: `INFRASTRUCTURE_SECURITY.md §3`.

## T-71 — host Redis firewall (free, ₹0)

1. Keep Redis on Compose's `backend` network (`internal: true`, no published port) and require
   `REDIS_PASSWORD` — already correct in code.
2. On a self-managed host add one narrow rule (built into the OS, no paid product):
   ```sh
   ufw deny out to 10.77.13.0/24 port 6379 proto tcp
   # or: nft add rule inet ots out ip daddr 10.77.13.0/24 tcp dport 6379 drop
   ```
   `script/host-firewall.sh` prints the exact rules and is a dry run unless `--apply` is passed.
   Reapply on every new host. A cloud network policy with the same intent also works.
3. Verify: a host process must fail `nc -zv 10.77.13.2 6379` while create/reveal/gone still works;
   `script/tls-rehearsal.sh --with-redis` reports 0 skips.
4. On managed Redis there is no host bridge to block. The ₹0 path is **Upstash Redis Free**:
   mandatory `rediss://` TLS + token AUTH, eviction OFF, **Auto Upgrade OFF**, no card, one
   database (250 MB / 500k commands / 10 GB). Stage 18 confirmed the substitute controls —
   plaintext connections are closed and tokenless TLS returns `NOAUTH` — but the endpoint is
   publicly reachable, so **T-71 is not achieved**. Record console settings, accept the residual
   in writing, **rotate the disclosed token**, and use `script/preflight.sh --skip-redis` for TLS
   only. Do not claim a host rule. Details: `INFRASTRUCTURE_SECURITY.md §2`.

## K-46 — schedule the webhook worker (free, ₹0)

Use `script/webhook-worker.sh` (flock, no overlapping runs, refuses `WEBHOOK_ALLOW_PRIVATE=true`,
no secret in argv). Full cron/systemd units, egress firewall and verification steps are in
`docs/ops/webhook-worker.md`. Minimum cron:

```cron
* * * * * OTS_PROJECT_DIR=/srv/onetime-secret /srv/onetime-secret/script/webhook-worker.sh >> /var/log/ots-webhook-worker.log 2>&1
```

On the **free-tier path**, the applied workflow is `.github/workflows/ops-free-tier.yml` with
`environment: staging` and four secrets. Stage 18 found it **active on the default branch** and
proved a manual signed delivery, but also found **zero scheduled runs**, **no required reviewers**
on the environment, **no missing-run detection**, a failure-only queue alert that has never fired,
and **no egress restriction**. Fix all five before treating K-46 as closed. GitHub schedules can
be delayed or dropped and public repos disable them after 60 days of inactivity, so monitor
*missing* runs; keep `workflow_dispatch` for manual proofs. Operator action: add reviewers, make a
cron run fire, implement external last-success checks, widen alerting, restrict egress, and prove
a signed delivery again. Production scheduling is not authorized.

## Zero-budget approval actions (staging executed; production pending)

Staging resources exist; production changes remain unapproved. Operator/repo-owner approval is
required for all of the following before any production state change:

1. Production secrets (a **new** `SECRET`, new Redis token) in Render and a protected GitHub
   environment with required reviewers; no payment methods anywhere.
2. A custom production hostname/TLS chain and the CDN decision (§ H1b).
3. Rotation of the disclosed staging token and purge of the transcript that carried it.
4. The live backup encryption passphrase and artifact/R2 destination.
5. Running the deployed preflight and provider-isolation checks, and recording output in
   `docs/GO_LIVE_HANDOFF.md`.
6. The final go/no-go signature. No commit, push, deploy, key rotation or production restore is
   performed by an agent.

## Reality check before buying a VPS

Free tiers can host a beta with three honest caveats: free compute sleeps (cold starts take tens
of seconds — **not yet measured**); free Redis is not durable (encrypted secrets still expire by
TTL); free tier cannot close T-71 by itself (record the provider's isolation). Buy a VPS/domain
only when cold starts, Redis restarts, backup/storage needs, or tier caps justify it; then reapply
T-71 and re-run the full preflight.

## Where the detailed versions live

- `INFRASTRUCTURE_SECURITY.md` — trust boundaries, Stage 18 evidence ledger, proxy/TLS/worker controls, residual risks.
- `STAGING_TEST_REPORT.md` — Stage 17 staging build, journeys and earlier delivery proof.
- `FREE_TIER_DEPLOYMENT_PLAN.md` — exact ₹0 config, deployment steps, cost breakdown, verification commands.
- `PROVIDER_COMPARISON.md` — first-party free-tier limits and why each provider was chosen or rejected.
- `RELEASE_CHECKLIST.md` — signable release gate with the same classification.
- `PRODUCTION_READINESS.md` — strict evidence table.
- `docs/GO_LIVE_HANDOFF.md` — operator sequence and approval line.
- `DEPLOYMENT.md §4.0/§4.1/§4.2` — Redis firewall, live TLS checks, deploy order.
- `RUNBOOK.md` — incident response and key-rotation/restore drills.
- `SECURITY_AUDIT.md §7/§13/§14` — E2EE non-claim, findings and protected-path review.

**Final assessment: NO-GO for public launch.** Stage 18 produced real staging evidence: TLS,
metrics hiding and restore tooling verified within scope; Redis isolation not achieved; webhook
scheduling and monitoring absent; CDN in path; staging token disclosed. T-70 needs a production
hostname, T-71 needs provider risk acceptance and token rotation, and K-46 needs a real schedule
plus missing-run detection. Human gates remain unsigned. Only production-host evidence can change
this verdict — and none of it was fabricated here.
