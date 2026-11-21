# Stage 17 — Phase 0 record (staging preparation)

**Date: 2026-11-22. Status: PREPARED — no staging environment exists yet.**
Phase 0 converts the approved free-tier architecture into an executable staging plan and records
the decisions that must be explicit before any provider account or resource is created.

## 1. What is decided

| Item | Decision | Basis |
|---|---|---|
| App + API | **Render Free Web Service**, Docker build from repo `Dockerfile`, `/health`, `*.onrender.com` URL | Free plan $0, Docker builds and managed TLS verified at `render.com/pricing` and `render.com/docs/web-services` |
| Datastore | **Upstash Redis Free**, `rediss://`, token AUTH, eviction OFF, Auto Upgrade OFF | Quotas and mandatory TLS verified at `upstash.com/pricing/redis` and `/docs/redis/howto/redis-cli` |
| Worker + backups | **GitHub Actions**, SHA-pinned, `staging` environment | Schedules verified (5-min minimum, delay/drop, default-branch, 60-day public-inactivity rule) via GitHub docs API |
| Static site | **Cloudflare Pages Free** from `site/` | 500 builds/month, `<project>.pages.dev` naming verified |
| Staging isolation | **Public-but-unadvertised staging URL with synthetic data only** | See waiver below — Cloudflare Access cannot front an `onrender.com` hostname without an owned domain in a Cloudflare zone (verified at `developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/self-hosted-public-app/`), and a Render private service has no public URL (`render.com/docs/private-services`) |
| Cold start | **Accepted** (15 min idle → ~1 min wake) | Verified at `render.com/docs/free`; will be measured, not hidden, in `STAGING_TEST_REPORT.md` |
| File storage | Stay in Redis (512 KiB decoded / 1 MiB JSON cap) | `lib/onetime/logic/conceal_secret.rb:17`, `lib/onetime/config.rb:89-90,231` |

## 1a. Provisioned datastore (operator-reported 2026-11-22)

| Field | Value |
|---|---|
| Provider | Upstash Redis Free |
| Database name | `oneshotlink_redis_DB` |
| Region | Mumbai, India (`ap-south-1`) |

Not yet supplied by the operator: the database **endpoint**, **port**, and **token**, plus the
REST URL/token required by the Upstash MCP client. No credential is present in this environment
(`env | grep -i upstash` → nothing), so no connection or deployment has been attempted.

The Node-oriented `UPSTASH_REDIS_REST_*` + `@upstash/redis` + `lib/redis.ts` instructions are
**not applicable** to this Ruby application: it reads `REDIS_URL` / `REDIS_PASSWORD` and folds the
token into a `rediss://` URL (`lib/onetime/config.rb:196-212`). Adding a Node client, a `.env`
file, or MCP config changes outside this repository would violate project rules 5, 8 and 12 and
are not part of this stage. An MCP template is provided at
`deploy/free-tier/upstash-mcp.json.example` for the operator to fill with real REST credentials.

## 1b. Verified datastore connectivity and migration (2026-11-22)

Executed against `exciting-marten-210970.upstash.io:6379` with a staging token supplied at runtime
(never written to this repository — verified by grep):

```
plaintext redis:// PING      -> no PONG (connection failed, as required)
rediss:// PING               -> PONG
CONFIG GET maxmemory-policy  -> no value returned (managed Redis restricts it; UNVERIFIED)
bin/ots migrate --dry-run    -> schema: current=0 target=1 / dry-run: would apply initial-schema
bin/ots migrate              -> schema: current=1 target=1 / migrate: applied initial-schema
GET schema:version           -> 1
bin/ots migrate (re-run)     -> schema: current=1 target=1 / migrate: already current; nothing applied
```

The Upstash MCP server `upstash-redis` was added to `~/.config/opencode/opencode.json` (backup:
`opencode.json.bak-stage17`) with the operator-supplied REST URL/token. OpenCode must be
**restarted/reloaded** for the MCP server to be active. The REST credentials are unrelated to the
Ruby app, which uses `REDIS_URL=rediss://…` / `REDIS_PASSWORD`.

**Credential exposure notice:** the staging token was pasted into the operator chat. It must be
**rotated in the Upstash console** after staging verification; until then it is a known-exposed
staging credential. Never reuse it for production.

## 2. Waiver requiring operator acceptance

> I accept that the Stage 17 staging deployment will be reachable at an unadvertised
> `*.onrender.com` URL with **synthetic data only** and staging-only credentials. This is an
> explicit exception to the standing rule "do not expose publicly until the final
> release-readiness stage." No production secret, customer data, key, or payment method is
> involved. The URL will not be published in project documentation or marketing. T-70, T-71 and
> K-46 remain open; public launch remains NO-GO.

If this waiver is not accepted, the only rule-compliant alternative is a **Render private
service**, which by documented definition receives **no `onrender.com` subdomain** — so the
clean-URL requirement cannot be met simultaneously. No silent substitution will be made.

## 3. Human gates (not satisfiable from this environment)

| Gate | Evidence it is still open |
|---|---|
| Switch out of Plan mode | Done — this file was created after the mode change |
| Free Render, Upstash and Cloudflare accounts, no payment method | `env \| cut -d= -f1 \| grep -iE 'render\|upstash\|cloudflare\|...'` → `no provider credential env vars present` |
| Exact subdomain name claimability | Public probe is inconclusive: `oneshotlink.onrender.com` and a random nonsense name both resolve to Render edge IPs and return HTTP 404; only account-based creation can confirm |
| Approval to edit `.github/workflows/` (protected path) | Not granted in writing; the staging workflow is staged as a template outside the protected path |
| Acceptance of the waiver in §2 | Not yet recorded |

GitHub CLI is authenticated (`gh auth status` → `aman-ali07`, token scopes `repo`, `workflow`),
but that is CI access only — it does not provision Render, Upstash or Cloudflare resources.

## 4. Prepared artifacts

| File | Purpose |
|---|---|
| `deploy/free-tier/env.production.example` | 47-key production env contract (verified by `verify.sh`) |
| `deploy/free-tier/Dockerfile.pinned` | digest-pinned image with 60 s health start period |
| `deploy/free-tier/ops-free-tier.staging.yml` | ops workflow with `environment: staging` — **template only**; copy to `.github/workflows/` after approval |
| `deploy/free-tier/verify.sh` | non-deploying verification (`0 failures` on 15 checks) |
| `deploy/free-tier/README.md` | operator sequence and evidence requirements |

## 5. Immediate next actions once the gates close

1. **Upstash:** create one free DB; record plan/Auto-Upgrade/Eviction settings; run the TLS/AUTH probes in `deploy/free-tier/README.md` §3.
2. **Render:** create the staging web service with the env values from §4; health path `/health`, grace ≥60 s; record the deployed hostname (do not assume the exact name).
3. **Migration:** `bin/ots migrate --dry-run`, then `migrate`, then `GET schema:version` → `1` **before** the first synthetic secret.
4. **Actions:** apply the staging workflow after approval; create the `staging` environment with required reviewers and staging-only secrets.
5. **Pages:** create the static site project; verify legal pages and absolute `og:image`.
6. **Execute the test matrix** and write `STAGING_TEST_REPORT.md` with real output, including the mandatory caveat that staging evidence does not close T-70/T-71/K-46 and that no "production ready" or "zero-knowledge" claim is made (D-012).

Nothing in this file authorizes a deploy. It records the plan and the gates that remain human-owned.
