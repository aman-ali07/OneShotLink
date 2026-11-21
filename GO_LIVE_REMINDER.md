# Go-live reminder — OneShotLink (authoritative pre-launch checklist)

**Status of this note: updated 2026-11-21. Public launch verdict: NO-GO.**

This is the single launch-readiness checklist. Every remaining item is classified with one of
four labels: **FIXED AND VERIFIED**, **REQUIRES HUMAN APPROVAL**, **REQUIRES SERVER OPERATOR**,
or **BLOCKED**. A green test suite proves repository behaviour, **not** that a public host is
configured. Until the operator items produce recorded evidence, call the service
**production-packaged, go-live pending** or **free-tier beta** — never "production ready".
Do not claim zero-knowledge (D-012): the passphrase is an access gate, not a second key.

Local evidence: **307 backend examples, 0 failures** (single clean run), 35 Vitest tests, eight browser
journeys, clean typecheck/build, brand sweep, dependency audits, isolated restore drill, and the
TLS rehearsal. All are **code-level** facts; none closes an operator item.

**Zero-budget path (2026-11-21):** a complete ₹0/month architecture has been investigated and
documented in `FREE_TIER_DEPLOYMENT_PLAN.md`, `PROVIDER_COMPARISON.md` and
`INFRASTRUCTURE_SECURITY.md` (Render Free + Upstash Redis Free + GitHub Actions + Cloudflare
Pages). It is **prepared, not executed**. It does not close T-70, T-71 or K-46 — only recorded
evidence from the deployed infrastructure does. See § "Zero-budget approval actions" below.

## Master classification (every remaining item)

| Item | Classification | Owner | Evidence / required next action |
| --- | --- | --- | --- |
| Core lifecycle, accounts, burn, passphrase gate, file secrets | **FIXED AND VERIFIED** | Repo | 307 specs + browser journeys green |
| SA-01…SA-31 security findings | **FIXED AND VERIFIED** | Repo | `SECURITY_AUDIT.md` §3/§13; no S1/S2 open in code |
| D-012b per-secret passphrase budget (900 s / 5 guesses) | **FIXED AND VERIFIED** | Repo | `RATE_LIMIT_PASSPHRASE*`, `Limiter` scope, red→green spec, decision in `DECISIONS.md` |
| D-retention (no raw IPs in audit) | **FIXED AND VERIFIED** | Repo | `audit.rb#ip_reference` daily HMAC, decision recorded |
| Backup carries `schema:version` | **FIXED AND VERIFIED** | Repo | `backup.rb`, `ops_spec` round-trip + corrupt-marker rejection specs |
| Backup/restore round-trip on isolated Redis | **FIXED AND VERIFIED** | Repo | `script/restore-drill.sh` → `RESTORE DRILL PASSED` (throwaway container only) |
| `/metrics` token auth, per-scope rate limit, version removed | **FIXED AND VERIFIED** | Repo | `metrics_spec.rb` (integration + unit) green |
| Webhook worker wrapper + SSRF/egress guard | **FIXED AND VERIFIED** | Repo | `script/webhook-worker.sh`, `docs/ops/webhook-worker.md`, `bash -n` OK |
| Protected-path review (crypto.rb, app.rb, compose.yaml) | **REQUIRES HUMAN APPROVAL** | Human | Diffs re-read; sign-off required before promotion (§ below) |
| H4 build / promote / deploy | **REQUIRES HUMAN APPROVAL** | Human | Agents report only; never auto-merge or deploy |
| H6 destructive drills on a live instance (backup restore, key rotation) | **REQUIRES HUMAN APPROVAL** | Human | Run on a copy per `RUNBOOK.md` §1/§6; agents never restore into live |
| H8 legal pages, name check, go/no-go signature | **REQUIRES HUMAN APPROVAL** | Human | Trademark/lawyer review + sign-off in `docs/GO_LIVE_HANDOFF.md` |
| Open product decisions: D-token, D-request-mode | **REQUIRES HUMAN APPROVAL** | Product | Record in `docs/DECISIONS.md` before related code (D-017 deferral stands) |
| T-70 TLS on a real hostname | **REQUIRES SERVER OPERATOR** | Operator | `HOST=https://<host> script/preflight.sh` exits 0 on target |
| T-71 Redis host firewall | **REQUIRES SERVER OPERATOR** | Operator | Target preflight passes with Redis checks, or provider isolation recorded |
| K-46 schedule/monitor worker + egress firewall | **REQUIRES SERVER OPERATOR** | Operator | Cron/systemd **or approved GitHub Actions schedule** installed; queue-age alert, egress restricted; signed delivery proven |
| Zero-budget architecture (Render/Upstash/Actions/Cloudflare) | **REQUIRES HUMAN APPROVAL** | Operator + repo owner | `FREE_TIER_DEPLOYMENT_PLAN.md`, `PROVIDER_COMPARISON.md`, `INFRASTRUCTURE_SECURITY.md` reviewed; accounts/services and the protected workflow file approved; nothing deployed |
| Set `METRICS_TOKEN` on the server; restrict scrape network | **REQUIRES SERVER OPERATOR** | Operator | Token in provider secret store; scraper IP allowlisted; keep `/metrics` off for the free beta |
| Persistent backup volume on host | **REQUIRES SERVER OPERATOR** | Operator | `/backups` on a persistent disk; free Redis is not durable |
| **Public launch** | **BLOCKED** | — | T-70/T-71/K-46 have no deployed-infrastructure evidence; zero-budget approvals unsigned |
| Claim that the ₹0 stack is deployed or that gates are closed | **BLOCKED** | — | Only provider docs and repository code were inspected; no account, service, workflow or deploy was created |

No item is left unclassified. "Code-level ready" means a command in this repository passed;
"server-level verified" means the same control passed on the actual public host with output in
`docs/GO_LIVE_HANDOFF.md`. A rehearsal is preparation, not proof.

## Required human actions

- [ ] **H1 — Real HTTPS hostname (T-70).** On the free path: Render Free managed TLS on
      `*.onrender.com` (or Cloudflare Universal SSL). Set `SSL=true`, `HOST=<host without scheme>`,
      verify proxy CIDRs before enabling `TRUST_PROXY`. Proof: `HOST=https://<real-host>
      script/preflight.sh --skip-redis` exits 0. (§ T-70 below)
- [ ] **H2 — Redis isolation (T-71).** Free path: Upstash Redis Free with mandatory `rediss://`
      TLS, token AUTH, eviction OFF, **Auto Upgrade OFF**, no card, no host bridge — record the
      provider settings and prove plaintext connections fail. Self-managed path: still apply
      `DEPLOYMENT.md §4.0` on each host. (§ T-71 below)
- [ ] **H3 — Schedule the webhook worker (K-46).** Free path: approved GitHub Actions schedule
      with environment secrets, retries and queue-liveness alerts (workflow content in
      `FREE_TIER_DEPLOYMENT_PLAN.md §6`). Self-managed path: `script/webhook-worker.sh` under
      cron/systemd with egress restricted. Proof: signed delivery + HMAC + replay check.
- [ ] **H4 — Deploy/promote yourself.** Agents never push, deploy, or auto-merge.
- [ ] **H5 — Approve protected-path edits.** See the review table below.
- [ ] **H6 — Run destructive drills on a copy yourself.** The isolated restore drill in this
      repo is evidence the tooling works; it is **not** a production restore. Never let an agent
      restore into a live instance or rotate `SECRET`.
- [ ] **H7 — Record remaining product decisions.** D-012b and D-retention are now recorded;
      D-token and D-request-mode remain.
- [ ] **H8 — Legal pages, name check, go/no-go signature.**

## Protected-path review (requirement 7 — re-read, pending human sign-off)

| Path | What changed | Review result |
| --- | --- | --- |
| `lib/onetime/crypto.rb` | Reject any stored `cipher` value other than `aes-256-gcm` before constructing `OpenSSL::Cipher`; typed integrity error instead of raw `RuntimeError`. | Sound. AEAD key/IV/tag path unchanged; no plaintext or key handling changed. Spec proves tampering fails closed. **Needs human approval.** |
| `lib/onetime/web/app.rb` | Canonical `HARDENING_HEADERS` shared by default headers and static assets; strict JSON media type; redacted audit references; metadata MAC on previews; separate limiter scopes (respond/burn/metrics/passphrase); `/metrics` bearer-token gate. | Sound. No auth bypass introduced; reveal still verify→decrypt→consume; request key never logged. **Needs human approval.** |
| `compose.yaml` | `TRUST_PROXY=true` + loopback-only trusted proxies; `APP_BIND=127.0.0.1`; `REDISCLI_AUTH` in healthcheck; all new limiter scopes and `METRICS_TOKEN` passed through. | Sound for the documented same-host proxy topology; `client_id` ignores XFF unless the direct peer is trusted. **Needs human approval.** |

Full diff review notes are in `SECURITY_AUDIT.md` §14.

## T-70 — real HTTPS hostname (free tier, ₹0)

1. Deploy the existing `Dockerfile` to a free container host (e.g. a Render free web service) or
   run Caddy with a free Let's Encrypt certificate. The provider supplies a valid certificate.
2. Set app env **in the provider's dashboard**, never in git: `SECRET=$(openssl rand -hex 32)`,
   `REDIS_URL`/`REDIS_PASSWORD`, `HOST=<free-hostname-without-scheme>`, `SSL=true`,
   `TRUST_PROXY=true`, `TRUSTED_PROXIES=<proxy CIDR>`, and `METRICS_TOKEN` if metrics are enabled.
   Note the two `HOST` forms: the preflight takes a **URL**, the app takes `host:port` with no scheme.
3. Check: `curl -fsS https://<host>/health` and `HOST=https://<host> script/preflight.sh --skip-redis`
   (exit 0) when Redis is managed — host-firewall probes cannot apply without a host bridge. On a
   self-managed stack use the full preflight. The preflight creates a throwaway signup — run it on a
   beta instance. Rehearse free locally with `script/tls-rehearsal.sh --with-redis`.
4. Record the exact output in `docs/GO_LIVE_HANDOFF.md`. Without it T-70 stays open. Exact env values
   and Render steps: `FREE_TIER_DEPLOYMENT_PLAN.md §4`; proxy trust: `INFRASTRUCTURE_SECURITY.md §3`.

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
4. On managed Redis there is no host bridge to block. The documented ₹0 path is **Upstash Redis
   Free**: mandatory `rediss://` TLS + token AUTH, eviction OFF, **Auto Upgrade OFF**, no card,
   one database (250 MB / 500k commands / 10 GB). Prove a plaintext `redis://` connection fails,
   record the provider settings, and use `script/preflight.sh --skip-redis` for TLS checks. Do not
   claim a host rule. Details: `FREE_TIER_DEPLOYMENT_PLAN.md §3`, `INFRASTRUCTURE_SECURITY.md §2`.

## K-46 — schedule the webhook worker (free, ₹0)

Use `script/webhook-worker.sh` (flock, no overlapping runs, refuses `WEBHOOK_ALLOW_PRIVATE=true`,
no secret in argv). Full cron/systemd units, egress firewall and verification steps are in
`docs/ops/webhook-worker.md`. Minimum cron:

```cron
* * * * * OTS_PROJECT_DIR=/srv/onetime-secret /srv/onetime-secret/script/webhook-worker.sh >> /var/log/ots-webhook-worker.log 2>&1
```

On the **free-tier path**, a sleeping Render service is not a worker. Use the proposed GitHub
Actions schedule in `FREE_TIER_DEPLOYMENT_PLAN.md §6` (environment-protected secrets, three
bounded retries, queue-depth issue alerts, `workflow_dispatch` for manual runs). It needs explicit
approval before the protected `.github/workflows/` file is added. GitHub schedules can be delayed
or dropped and public repos disable them after 60 days of inactivity, so monitor *missing* runs.
A single successful local delivery is **not** proof the schedule keeps working; the operator owns
queue-age monitoring and the egress firewall.

## Zero-budget approval actions (pending — nothing executed)

The ₹0 architecture is designed but no infrastructure was created. Operator/repo-owner approval
is required for all of the following before any state changes:

1. Free accounts **without payment methods** on Render, Upstash, Cloudflare (GitHub already exists).
2. Creating the Upstash database and the Render service with the exact env values in
   `FREE_TIER_DEPLOYMENT_PLAN.md §2–§4` (including `AUTH_MODE=simple` and the proxy-trust choice).
3. Adding `.github/workflows/ops-free-tier.yml` and its environment secrets (protected path).
4. The client-side backup encryption passphrase and artifact/R2 destination.
5. Running the deployed preflight and provider-isolation checks, and recording output in
   `docs/GO_LIVE_HANDOFF.md`.
6. The final go/no-go signature. No commit, push, deploy, key rotation or production restore is
   performed by an agent.

## Reality check before buying a VPS

Free tiers can host a beta with three honest caveats: free compute sleeps (cold starts take tens
of seconds); free Redis is not durable (encrypted secrets still expire by TTL); free tier cannot
close T-71 by itself (record the provider's isolation). Buy a VPS/domain only when cold starts,
Redis restarts, backup/storage needs, or tier caps justify it; then reapply T-71 and re-run the
full preflight.

## Where the detailed versions live

- `FREE_TIER_DEPLOYMENT_PLAN.md` — exact ₹0 config, deployment steps, cost breakdown, verification commands, feasibility assessment.
- `PROVIDER_COMPARISON.md` — first-party free-tier limits and why each provider was chosen or rejected.
- `INFRASTRUCTURE_SECURITY.md` — trust boundaries, proxy/TLS/worker controls, residual risks.
- `RELEASE_CHECKLIST.md` — signable release gate with the same classification.
- `PRODUCTION_READINESS.md` — strict evidence table.
- `docs/GO_LIVE_HANDOFF.md` — operator sequence and approval line.
- `DEPLOYMENT.md §4.0/§4.1/§4.2` — Redis firewall, live TLS checks, deploy order.
- `RUNBOOK.md` — incident response and key-rotation/restore drills.
- `SECURITY_AUDIT.md §7/§13/§14` — E2EE non-claim, findings and protected-path review.
- `IMPLEMENTATION_PLAN.md §5–§7/§13` — decisions, operator actions, this pass.

**Final assessment: NO-GO for public launch.** Code-level readiness is GO, and a complete ₹0
architecture has been prepared, but **nothing was deployed**: T-70/T-71 have no target-host
evidence, K-46 has no scheduler or signed-delivery proof, the protected workflow edit awaits
approval, and the free-tier accounts/services are not created. Public launch stays NO-GO until
the deployed-infrastructure commands in `INFRASTRUCTURE_SECURITY.md §9` pass and their output is
recorded. Only that evidence can change this verdict.
