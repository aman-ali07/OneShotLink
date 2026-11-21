# Free-tier production preparation — OneShotLink

**Status: prepared, NOT deployed, NOT publicly reachable. Date: 2026-11-21.**
This directory contains the *preparation artifacts* for the approved ₹0 architecture in
`FREE_TIER_DEPLOYMENT_PLAN.md` and `PROVIDER_COMPARISON.md`. It does not create accounts,
add payment methods, push a workflow, rotate a key, or deploy. Public launch stays **NO-GO**
until T-70 (real TLS hostname), T-71 (Redis isolation substitute controls) and K-46 (scheduled
worker proof) have target-host evidence recorded in `docs/GO_LIVE_HANDOFF.md`.

## 1. What is here

| File | Purpose | Applied? |
|---|---|---|
| `env.production.example` | Complete production environment contract (47 Config keys + platform keys); placeholders only, no secrets | **No** — copy values into the Render dashboard |
| `Dockerfile.pinned` | Proposed hardened image: registry-digest base images, bundler pinned to `Gemfile.lock`, 60 s health start period, no dev scripts | **No** — protected `Dockerfile` unchanged; apply only with approval |
| `Dockerfile.pinned.dockerignore` | Build-context allowlist (drops `docs/`, `site/`, `e2e/`, `examples/`, `.claude/`, `.serena/`, `*.md`, most of `replica/`) | **No** — used automatically when building with `-f deploy/free-tier/Dockerfile.pinned` |
| `ops-free-tier.yml` | Proposed GitHub Actions workflow: one-off migrate, 30-min webhook worker, daily encrypted backup, SHA-pinned actions | **No** — protected `.github/workflows/` unchanged; apply only with approval |
| `verify.sh` | Local, non-deploying verification of all of the above; optional clean-build reproducibility check | **Yes** — run it |

The repository's existing `Dockerfile`, `compose.yaml`, `config.ru`, `config/puma.rb` and
`.github/workflows/` were **not modified**. `compose.yaml` remains the local rehearsal stack;
Render builds a Dockerfile directly and never reads Compose.

## 2. Target topology (unchanged from the approved plan)

```
Browser ──TLS (Render managed cert)──> Render Free web service (Dockerfile, Puma, /health)
                                          │ rediss:// + token
                                          ▼
                                     Upstash Redis Free (TLS, AUTH, eviction OFF)
GitHub Actions (external, SHA-pinned) ──> bin/ots migrate (once) / webhooks:work / backup
Cloudflare Pages Free ──> site/ (privacy, terms, og image)
```

## 3. Operator sequence (no agent action)

1. **Accounts, no payment method.** Render, Upstash, GitHub, Cloudflare. Upstash: plan Free,
   **Auto Upgrade OFF**, **Eviction OFF**; no card anywhere.
2. **Provision Redis.** Create one free DB, copy the `rediss://` host and token. Verify with
   `REDISCLI_AUTH='<token>' redis-cli -u 'rediss://<host>:6379' PING` → `PONG`, and confirm a
   plaintext `redis://` connection fails. Record the plan/Auto-Upgrade/Eviction settings.
3. **Set Render env vars** from `env.production.example`. The three traps:
   - `REDIS_URL` must be `rediss://…`. `Config.redis_url` falls back to
     `redis://127.0.0.1:6379/0` (`lib/onetime/config.rb:181-183`) and the code does **not**
     enforce TLS, so an omitted value boots but every request returns 503.
   - `HOST` is `host:port` with **no scheme**; a URL produces `https://https://…` links.
   - `TRUST_PROXY=false` for the first beta (Render proxy CIDRs and XFF overwrite behaviour are
     UNVERIFIED). Do not copy `.env.example`'s loopback CIDRs.
4. **Run the migration once before first web boot**, from an authenticated runner with the same
   `SECRET`/`REDIS_URL`/`REDIS_PASSWORD`: `bin/ots migrate --dry-run`, then `bin/ots migrate`,
   then `GET schema:version`. `Migrate.apply!` only stamps `schema:version` with `SET NX` and
   refuses corrupt/newer markers; it never rewrites `secret:object:*` bytes. Caveat: the CLI
   records an `admin.migrated` audit `XADD` **even on `--dry-run`**, so dry-run is not strictly
   read-only. On a full 250 MB Upstash DB with eviction off, the XADD and the stamp are rejected —
   treat that as an incident, not a retry loop.
5. **Deploy the image.** Health check path `/health`, initial delay/grace **≥60 s** (Render Free
   wakes in ~1 min after 15 min idle). `/health` is a Redis `PING` liveness check: 200 `ok`, 503
   `degraded` when Redis is unreachable. A *full* Redis still answers PING, so capacity is not
   visible there; with `METRICS_ENABLED=false` (the beta default) there is no memory-ratio alert
   either — alert manually on Upstash console `used_memory` and command count.
6. **Apply the ops workflow** (only after approval): copy `ops-free-tier.yml` to
   `.github/workflows/`, create the `production` environment with required reviewers, add the
   secrets `SECRET`, `REDIS_URL`, `REDIS_PASSWORD`, `BACKUP_PASSPHRASE`, and keep `GITHUB_TOKEN`
   permissions at `contents: read` except the webhook job's `issues: write`.
7. **Publish the static site** from `site/` to Cloudflare Pages (500 builds/month).
8. **Prove the gates on real infrastructure** and record output in `docs/GO_LIVE_HANDOFF.md`:
   TLS chain/HSTS/cookie flags/redirect (T-70), provider settings + no plaintext Redis (T-71
   substitute controls), and a signed webhook POST + replay check + liveness alert (K-46).

## 4. Reproducible build

The root `Dockerfile` uses mutable tags (`node:24-bookworm-slim`, `ruby:3.3-slim x2`). The
proposed `Dockerfile.pinned` resolves them to digests captured from the registry on 2026-11-21:

| Tag | Digest |
|---|---|
| `node:24-bookworm-slim` | `sha256:dc26ae92c9fb15cf6b1d63e20f0944b2efe0f115b20e00be48fb23fceb061c54` |
| `ruby:3.3-slim` | `sha256:37d45ed5edf175280231e7361ac53bdccdcd476147a74d70cd44b8a7704ef85e` |

`Gemfile.lock` pins Ruby 3.3.13p207 / Bundler 2.5.22; the image installs that exact bundler and
runs `bundle _2.5.22_ install`. `frontend/package-lock.json` (lockfileVersion 3) is honoured by
`npm ci`. Apt package versions are **not** pinned — for bit-for-bit rebuilds years later, point
apt at a dated `snapshot.debian.org` repository. This is recorded as a residual, not claimed away.

Verification command (from the repository root, Docker required, no deploy):

```sh
bash deploy/free-tier/verify.sh --verify-build
```

It builds the pinned image twice with `--pull --no-cache`, compares `docker image inspect
--format '{{.Id}}'`, and fails if the IDs differ. Build output and the two IDs are recorded in
§8 once the run completes. The ordinary (fast) check is `bash deploy/free-tier/verify.sh`.

## 5. CI/CD preparation

The existing `.github/workflows/ci.yml` already pins all `uses:` refs to full SHAs, gates on
security/backend/frontend, runs the container lifecycle smoke, SDK examples, load test, preflight
self-test, browser journeys and the WCAG gate. Gaps identified by the DevOps review that need
operator approval to change (protected path):

- No `bin/ots migrate --dry-run` / apply gate — the CLI currently has **no caller in CI**.
- Health loop (`ci.yml:102-105`) has no explicit exhaustion assertion; `docker compose up -d
  --wait` would be stronger.
- `docker build` at `ci.yml:98` omits `--pull`, so a stale cached base can be reused.
- No `timeout-minutes` (matters if the repo becomes private and draws the $12 allowance).
- `test:mobile` is invoked twice (`ci.yml:125-126`).
- The failure-only log dump (`ci.yml:156-158`) is useful but not an artifact upload.

**Liveness of missing scheduled runs** cannot be checked inside a workflow that did not run;
monitor the last successful run timestamp via the GitHub API and keep repo activity alive
(public repos disable schedules after 60 days of inactivity).

## 6. Logging and secrets

- App logs go to stderr at `LOG_LEVEL=info`; `RequestLogger` uses `PATH_INFO` only, never query,
  body, cookies or IP, and redacts secret/request bearer keys. Boot logs only version/env/auth/
  ui/ssl. Never set `LOG_LEVEL=debug` on a public instance.
- `Cli.backup` prints the dump path and `Cli.reveal` prints plaintext — do not copy those stdout
  lines into shared CI logs or issues.
- Secrets live in the Render dashboard and the GitHub `production` environment, never in git,
  the image, argv, logs or artifacts. `.env` is ignored; `.env.example` uses boot-rejected
  `CHANGE-ME` sentinels. Backups are GPG-encrypted client-side with a separate passphrase
  (`BACKUP_PASSPHRASE` piped on stdin) and kept for 7 days; prefer a private free R2 bucket with
  lifecycle deletion for anything longer than the 30-day receipt lifecycle.
- `WEBHOOK_ALLOW_PRIVATE` is **not boot-validated** (`lib/onetime/webhook.rb:281`); the Actions
  worker calls `bin/ots` directly, so the env must set it empty. Only `script/webhook-worker.sh`
  refuses it, and that script is not used on Render.
- Render log retention/forwarding is an operator choice; record the window in the handoff doc.

## 7. Development-only configuration removed or overridden

| Dev default | Source | Production value |
|---|---|---|
| `HOST=localhost:3000`, `SSL=false` | `config.rb:21-22` | real Render hostname, `true` |
| `REDIS_URL=redis://127.0.0.1:6379/0` | `config.rb:181-183` | `rediss://…` (code does not enforce — verified by `verify.sh`) |
| `AUTH_MODE=disabled` | `config.rb:23` | `simple` (webhooks need accounts) |
| `TRUST_PROXY=true` + loopback CIDRs | `.env.example:73-74` | `false`, empty CIDRs (beta decision) |
| `WEB_CONCURRENCY=2` | `.env.example:84`, `compose.yaml:87` | `1` for 512 MB |
| `REDIS_URL=redis://redis:6379/0`, `REDIS_MAXMEMORY`, `APP_BIND`, `APP_PORT`, `REDIS_SUBNET` | `compose.yaml:53,16,96,142` | Compose-only; never set on Render |
| `VITE_API_PROXY`, `OTS_URL`, `OTS_ALLOW_INSECURE`, `WEBHOOK_ALLOW_PRIVATE` | `.env.example:103-112` | unset |
| `script/` shipped in the image | root `Dockerfile:46` | not copied in `Dockerfile.pinned` |
| docs/site/e2e/examples/ planning prose in build context | root `.dockerignore` | excluded by `Dockerfile.pinned.dockerignore` |

## 8. Evidence (executed 2026-11-21, no deploy)

`bash deploy/free-tier/verify.sh` → **0 failures**:

```
PASS env contract covers 47 Config keys
PASS no active ^SSL=false
PASS no active ^REDIS_URL=redis://
PASS no active ^TRUST_PROXY=true
PASS no active ^HOST=localhost
PASS no active ^WEBHOOK_ALLOW_PRIVATE=true
PASS no active ^AUTH_MODE=full
PASS SECRET is a non-working placeholder
PASS YAML parsed: deploy/free-tier/ops-free-tier.yml jobs = ['migrate', 'webhooks', 'backup']
PASS all 7 uses: refs are 40-hex SHAs
PASS Gemfile.lock present
PASS frontend/package-lock.json present
PASS pinned image uses registry digests
PASS bundler pinned to Gemfile.lock version
PASS compose config --quiet
== result: 0 failure(s) ==
```

Migration path on a throwaway Redis (DB 14, local Docker, no production data):

```
$ docker run -d --name ots-stage16-redis -p 6397:6379 redis:7.4-alpine
$ SECRET=… REDIS_URL=redis://127.0.0.1:6397/14 \
  docker run --rm --network=host -v "$PWD":/app -v ots-bundle:/bundle \
    -e BUNDLE_PATH=/bundle -e SECRET -e REDIS_URL -w /app ots-dev \
    bundle exec ruby bin/ots migrate --dry-run
schema: current=0 target=1
dry-run: would apply initial-schema
$ … bin/ots migrate
schema: current=1 target=1
migrate: applied initial-schema
$ docker exec ots-stage16-redis redis-cli -n 14 GET schema:version
1
$ … bin/ots migrate          # idempotent re-run
schema: current=1 target=1
migrate: already current; nothing applied
```

Smoke test of the pinned image (`ots-verify-a`, scratch Redis on a private Docker network,
no public exposure):

```
/health -> {"status":"ok","redis":"ok","version":"0.1.0"}
POST /api/v3/guest/conceal -> 201, secret_key issued
GET  /api/v3/guest/secret/<key>          -> preview, no secret_value
POST /api/v3/guest/secret/<key>/reveal   -> {"secret_value":"stage16-smoke"}
POST .../reveal again                    -> 404
```

CLI commands from the pinned image (same scratch network, confirming that omitting `script/`
breaks nothing):

```
bin/ots health        -> config: ok / redis: ok / Status: ok
bin/ots migrate --dry-run -> schema: current=0 target=1 / dry-run: would apply initial-schema
bin/ots webhooks:work 1   -> claimed=0 delivered=0 retrying=0 failed=0 skipped=0
bin/ots backup --out /tmp/dump.json -> Wrote 0 secret record(s) and 0 customer(s)
```

Reproducible-build run (`bash deploy/free-tier/verify.sh --verify-build`, two `--pull
--no-cache` builds of `Dockerfile.pinned`):

```
image A: sha256:25d68adae2d3fe9bedcf424f3137cfe2c792e83a6e337349c8fee08dd58a97af
image B: sha256:f6416b826f64859b3be5e9d6bf21f70ee8e99f52267a59f030e874d4248ced72
Gemfile.lock sha256: 37086006db4c11c4324d6b4cb8fe76389f498b5d1bf53c3079cb816de0ec4df8 (both)
public/app tree sha256: ad1019f8e9b0b4d14345e1e35f48b98e3d2587ee8e0c5d4ba14d6be9916c99f5 (both)
installed gems sha256: d602fcdc176ad0a21f7d7abacdc8802f74eae95556447ec4533cad1abdc64683 (both)
ruby 3.3.14 / Bundler 2.5.22 (both)
/tmp and /backups directory mtimes: 1795280347 (A) vs 1795280695 (B)
```

The `verify.sh` content-comparison branch was exercised directly on two completed images built
in **separate build sessions** (IDs `81acd…` and `f6416…`); its aggregate content hash was
identical for both: `924a47ccea6f843883a184cb6657d3dca421229ce4b694c01faa504e06574a60`.
(A second full `--verify-build` re-run was terminated by the 600 s tool limit mid-second-build;
it is not claimed as a pass.)

**Finding:** dependency and asset content is byte-identical across clean builds; the image IDs
differ only because the **legacy builder** (Docker without buildx) writes wall-clock directory
mtimes into layer tars. `verify.sh` therefore reports *content reproducibility* as PASS and
documents the gap rather than claiming bit-for-bit IDs. A build host with BuildKit/buildx and a
fixed `SOURCE_DATE_EPOCH` is required for identical image IDs; this host returned
`BuildKit is enabled but the buildx component is missing` when attempted.

## 9. Residual risks / not verified locally

- No real hostname, certificate chain, DNS, CDN or Upstash endpoint was contacted by this
  preparation; T-70/T-71/K-46 remain operator-owned.
- `preflight.sh --skip-redis` PASS proves nothing about Redis isolation on Upstash Free.
- `bin/ots migrate --dry-run` is not strictly read-only (audit `XADD`); dry-run against a *copy*
  of the free data is UNVERIFIED.
- Backup restore of TTL-less zsets (`customer:<id>:secrets`, `webhook:owner:*`, `webhook:queue`)
  can create immortal keys — no spec covers that shape; restore only on scratch Redis.
- `CONFIG GET maxmemory-policy` may be restricted on managed Redis, and 500k-command
  over-limit behaviour on Upstash Free is UNVERIFIED.
- Apt package versions are unpinned in the proposed image (see §4).
