# OneShotLink

A self-hostable service for sharing passwords, API keys, and private notes through
**single-use, self-destructing links**. The recipient can view a secret exactly once;
after that it is deleted from the server, and it also expires automatically after a
configurable TTL.

> **Project status: production-packaged core with optional simple-mode accounts,
> pre-alpha product.** The anonymous create → one-time reveal flow and optional accounts
> run in a hardened non-root container with Redis persistence, CI, and redacted logs.
> **307 backend specs pass**; the TypeScript/Vite build and eight committed browser journeys
> (lifecycle, accounts, file, requests, webhooks, states, mobile, a11y) were verified at
> desktop and 320 px. Operational
> controls are closed in the repository (Redis auth, backups, metrics, dependency scanning,
> key rotation, Redis isolation); what is left is **TLS on the operator's own host and
> domain**, which no commit can provide: see
> [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md), [KNOWN_ISSUES.md](KNOWN_ISSUES.md),
> and [TASKS.md](TASKS.md).
>
> **Go-live verdict: NO-GO.** TLS on your own hostname (T-70) and the host-side Redis firewall
> rule (T-71) are operator actions that no commit can satisfy. Do not describe a deployment as
> production-ready until both are signed off; the app-side flow is rehearsed by
> `script/tls-rehearsal.sh`.

## What works now

- Vue 3 SPA: conceal form, config-driven TTL, optional passphrase, one-time link with
  copy, reveal confirmation, passphrase prompt, and destroyed state.
- No auto-reveal on page load and no consuming GET: link previews cannot burn a secret,
  through the UI or the v3 API.
- `POST /api/v3/guest/conceal`; `GET /api/v3/guest/secret/:key` previews;
  `POST /api/v3/guest/secret/:key/reveal` consumes. See [docs/SDK.md](docs/SDK.md).
- Legacy `POST /api/v1/share` and `GET|POST /api/v1/secret/:key` (form or JSON).
- Encryption at rest with AES-256-GCM; plaintext never enters Redis.
- Atomic compare-and-delete: 8 concurrent reveals produce exactly one `200`.
- Production build served by Rack at `/` with deep-link fallback and correct asset MIME.
- Optional passphrase, verified with Argon2id **before** the delete; a wrong attempt does
  not burn the secret. This is an access gate, not zero-knowledge (D-012).
- TTL allowlist with Redis expiry, per-IP rate limits with `Retry-After`, uniform 404s.
- `/health`, `/api/v3/config`, typed JSON errors, request IDs, `no-store`, and a strict
  CSP plus HSTS (when `SSL=true`), nosniff, frame-deny, Referrer-Policy, COOP/CORP.
- Fail-closed boot validation; trusted-proxy-only `X-Forwarded-For`; bounded Redis
  timeouts; per-request logs that redact secret keys.
- Optional simple-mode accounts (`AUTH_MODE=simple`): signup/signin/signout, Argon2id
  passwords, opaque Redis sessions with `HttpOnly`/`SameSite=Lax` cookies, CSRF proof for
  cookie-authenticated mutations, owner receipts, dashboard, and password change.
- `bin/ots customers create` and `bin/ots customers reset-password` (hidden prompt or
  `OTS_PASSWORD`; passwords are never command-line arguments).
- Multi-stage production image, Compose stack with Redis AOF, read-only non-root web
  container, health checks, and CI smoke test.

Also implemented: the OpenAPI 3.1 document at `/api/v3/openapi.json`, `bin/ots` for
operator tasks (customers, health, backup/restore, rotate-key), `/metrics`, the audit stream,
and text file secrets up to 512 KiB (base64 in JSON, encrypted, downloaded once).
Not built yet: the colonel/admin **API** (the CLI covers it), organizations, custom domains,
email jobs, MFA/WebAuthn/SSO, and i18n.
`AUTH_MODE=full` intentionally returns `501` rather than silently degrading; account
routes return `403` when auth is disabled.
Remaining production gaps are infrastructure, not features: TLS on your domain and the
host-side Redis firewall rule — see [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md).

## Stack

Ruby 3.3 · Roda 3 on Rack 3 · Puma 7 · Redis 7+ · Vue 3 + TypeScript · Vite 6 ·
Tailwind CSS 4. Details: [TECH_STACK.md](TECH_STACK.md).

## Repository layout (current)

```
config.ru                # boot + fail-fast SECRET validation
config/puma.rb
frontend/                # Vue 3 + TS + Vite 6 + Tailwind 4
  src/lib/api.ts         # Zod schemas + typed API client
  src/views/             # ConcealView, RevealView, NotFoundView
  src/components/        # buttons, alerts, copy, header/footer
lib/onetime/
  config.rb              # env-driven configuration
  crypto.rb              # AES-256-GCM + HKDF
  errors.rb              # typed errors with HTTP status/code
  ids.rb                 # opaque IDs
  limiter.rb             # fixed-window Redis limiter (Lua)
  models/secret.rb       # encrypted record + receipt persistence
  logic/conceal_secret.rb
  logic/reveal_secret.rb
  password.rb            # Argon2id + bcrypt legacy verify
  store.rb               # Redis client + atomic consume
  web/app.rb             # Roda routes (health, config, v1, v3, static SPA)
  web/openapi.rb         # OpenAPI 3.1 document (/api/v3/openapi.json)
  web/request_logger.rb  # redacted request logs
  web/head_requests.rb   # HEAD served like GET
  audit.rb               # append-only audit stream (identifiers only)
  backup.rb              # encrypted backup export/restore
  logic/rotate_key.rb    # in-place SECRET rotation
replica/                 # recon, feature matrix, architecture, design tokens, parity
bin/ots                  # CLI: customers, health, backup/restore, rotate-key
script/loadtest.rb       # single-use invariant under concurrency
spec/                    # 307 unit + integration examples (Redis DB 15)
e2e/                     # 8 committed browser journeys: journey, accounts, file,
                         # requests, webhooks, states, mobile, a11y
Dockerfile               # multi-stage UI build + non-root Ruby runtime
compose.yaml             # web + persistent Redis
.github/workflows/ci.yml # specs, scans, container + browser smoke test + load test
RUNBOOK.md               # incident procedures (key compromise, Redis loss, rollback)
```

Built by Vite into `public/app/` (git-ignored). Set `AUTH_MODE=simple` to expose account
routes and the dashboard; the default `disabled` keeps the anonymous flow only.

## Quickstart (Compose, recommended)

Prerequisites: Docker with Compose v2, `openssl` (to generate secrets), `curl` (to probe)
and `python3` (SDK example and verification scripts). For UI work you also need Node 24;
browser journeys need Chrome/Chromium and `CHROME_PATH`. The manual non-Compose development
path in `script/dev.sh` additionally uses a local `redis-server`.

```bash
export SECRET="$(openssl rand -hex 32)"
export REDIS_PASSWORD="$(openssl rand -hex 24)"
docker compose up -d --build
curl -fsS localhost:3000/health
```

Open `http://localhost:3000/`. The stack runs the web container as UID 10001 with a
read-only root filesystem and a persistent Redis volume with a memory ceiling
(`REDIS_MAXMEMORY`). Set `APP_PORT`, `APP_BIND`, `HOST`, `SSL`, `TRUST_PROXY`,
`TRUSTED_PROXIES`, and `WEB_CONCURRENCY` in the environment; see
[.env.example](.env.example) and [DEPLOYMENT.md](DEPLOYMENT.md). Going live on a real
hostname? [DEPLOYMENT.md](DEPLOYMENT.md) §4.2 is the deploy-day sequence, and
`script/tls-rehearsal.sh` rehearses it on a scratch box first.

Automated end-to-end verification: `bash script/test-examples.sh` boots a throwaway Puma +
Redis stack, runs all six SDK examples (guest, passphrase, file, burn) and cleans up. It is
also a CI gate. Uses `ots-dev` + `ots-bundle` when present, otherwise the `oneshotlink-web`
image produced by the quickstart (see [TESTING.md](TESTING.md) §2).

Manual smoke test (verified through Compose; the shapes below are live responses):

```bash
curl -s localhost:3000/health
curl -s -X POST localhost:3000/api/v3/guest/conceal \
  -H 'content-type: application/json' -d '{"secret":"hello","ttl":1800}'
# copy secret_key from the response, then:
curl -si localhost:3000/api/v3/guest/secret/<key>                         # 200, metadata only
curl -si -X POST localhost:3000/api/v3/guest/secret/<key>/reveal \
  -H 'content-type: application/json' -d '{}'                             # 200, value once
curl -si -X POST localhost:3000/api/v3/guest/secret/<key>/reveal \
  -H 'content-type: application/json' -d '{}'                             # 404
```

Copy-paste examples in curl, TypeScript and Python are in [`examples/`](examples/),
explained in [docs/SDK.md](docs/SDK.md). To prove a running stack end to end (SDK examples and
eight browser journeys — `test`, `accounts`, `file`, `requests`, `webhooks`, `states`, `a11y`,
where `a11y` is the axe WCAG gate; mobile, metrics and restore checks are optional):

```bash
BASE_URL=http://localhost:3000 script/verify-deployment.sh
```

`.env.example` already ships `REDIS_URL=redis://redis:6379/0` (the Compose service name).
Use `redis://127.0.0.1:6379/0` only for a standalone process running next to Redis, never in a
Compose `.env`. Build prerequisites (BuildKit, outbound internet, `replica/design/tokens.css`)
are in [DEPLOYMENT.md](DEPLOYMENT.md) §2.

## Local development (no host Ruby required)

For a one-command dev stack (Redis + Puma + Vite with source mounted), run
`bash script/dev.sh` and open `http://127.0.0.1:5174`. It builds the dev image on first use
and cleans up on Ctrl-C. The manual equivalent below uses a dev image and a bundle volume:

```bash
docker build -t ots-dev - <<'EOF'
FROM ruby:3.3-slim
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libssl-dev curl \
 && rm -rf /var/lib/apt/lists/*
EOF
docker volume create ots-bundle
docker run --rm -v "$PWD":/app -v ots-bundle:/bundle -e BUNDLE_PATH=/bundle -w /app \
  ots-dev bundle install
```

Start Redis and the Rack app on `:3100` (specs use DB 15; the app uses DB 0):

```bash
redis-server --port 6399 --save '' --daemonize yes
export SECRET="$(openssl rand -hex 32)"
docker run --rm --network=host \
  -v "$PWD":/app -v ots-bundle:/bundle -e BUNDLE_PATH=/bundle \
  -e SECRET -e REDIS_URL=redis://127.0.0.1:6399/0 -e PORT=3100 -w /app \
  ots-dev bundle exec puma -C config/puma.rb
```

For UI hot reload, run `npm --prefix frontend run dev` in another shell; Vite proxies
`/api` to `http://127.0.0.1:3100` and serves the SPA itself.

Run the suite:

```bash
docker run --rm --network=host \
  -v "$PWD":/app -v ots-bundle:/bundle -e BUNDLE_PATH=/bundle -w /app \
  ots-dev bundle exec rspec
```

Expected: `307 examples, 0 failures`. The suite only touches Redis DB 15 and calls
`FLUSHDB` there, never `FLUSHALL`.

Frontend checks:

```bash
# Account journey against a running AUTH_MODE=simple instance
BASE_URL=http://127.0.0.1:3000 npm --prefix e2e run test:accounts

npm --prefix frontend test
npm --prefix frontend run typecheck
npm --prefix frontend run build
```

Vitest covers the Zod API client. Eight committed puppeteer journeys cover the browser flows;
run the primary one against a live stack with
`BASE_URL=http://127.0.0.1:3000 npm --prefix e2e test` (see `TESTING.md` §3 for all eight).

## Clone workflow

This is a clean-room rebuild of the original's core features. The MIT `replica-*` skill
pack (installed under `~/.agents/skills/`) drives recon → architect → design → build →
backend → test → diff → entrepreneur → brand → launch → deploy. Current artifacts:

- [replica/recon.md](replica/recon.md) — public-source map, evidence gaps
- [replica/features.csv](replica/features.csv) — 33-feature matrix
- [replica/architecture.md](replica/architecture.md) — v1 architecture
- [replica/design/tokens.json](replica/design/tokens.json) — AA-checked tokens, applied by the SPA
- [replica/parity.md](replica/parity.md) — parity history; current working-tree score **80.8/100 with
  11/11 must-haves** (`python3 ~/.agents/skills/replica-diff/parity.py replica/features.csv`).
  The committed HEAD figure is 66.7/100; the difference is the uncommitted release work.
  The remaining gaps are should/could items, and the passphrase is still an access gate,
  not a second key (D-012)

The original's name, logo, copy, screenshots, and fonts are never copied. A rebrand is
mandatory before launch; the brand sweep (`script/brand-sweep.sh`) passes today and must stay green
before any deploy (K-23 is resolved).

Read [AGENTS.md](AGENTS.md) before clone work.

## Documentation

- [ROADMAP.md](ROADMAP.md) — milestones, order, estimates
- [AGENTS.md](AGENTS.md) — instructions for AI coding agents
- [PRD.md](PRD.md) — requirements and acceptance criteria
- [ARCHITECTURE.md](ARCHITECTURE.md) — components, data flow
- [TASKS.md](TASKS.md) — work queue with evidence
- [API.md](API.md) — HTTP contract and implemented status
- [DATABASE.md](DATABASE.md) — Redis schema and invariants
- [SECURITY.md](SECURITY.md) — controls, threat model, D-012
- [docs/CRYPTO_SPEC.md](docs/CRYPTO_SPEC.md) — code-grounded crypto and single-use spec
- [docs/SDK.md](docs/SDK.md) — API guide with runnable curl/TypeScript/Python examples
- [TESTING.md](TESTING.md) / [DEPLOYMENT.md](DEPLOYMENT.md)
- [RUNBOOK.md](RUNBOOK.md) — incident response (key compromise, Redis loss, rollback)
- [TECH_STACK.md](TECH_STACK.md) / [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)
- [docs/DECISIONS.md](docs/DECISIONS.md) / [KNOWN_ISSUES.md](KNOWN_ISSUES.md)
- [CHANGELOG.md](CHANGELOG.md)

## Contributing

Read [AGENTS.md](AGENTS.md) for the ground rules (including protected paths that need operator
review) and [TESTING.md](TESTING.md) for the exact test commands. Ruby specs run in Docker against
Redis DB 15; a change needs a spec that fails before the fix and passes after. Open a draft PR —
a human reviews and merges; nothing is auto-merged. Never include secret values, passphrases or
tokens in issues, PRs, logs or docs. See [CONTRIBUTING.md](CONTRIBUTING.md) and the
[code of conduct](CODE_OF_CONDUCT.md).

## Security reporting

**Do not file public issues for security vulnerabilities.** Follow
[SECURITY.md](SECURITY.md), which documents the reporting policy and scope. **Enable GitHub
private vulnerability reporting in Settings → Security before publishing**; until then there is
no private channel. For ordinary
bugs, [open an issue](https://github.com/aman-ali07/OneShotLink/issues) with `X-Request-Id` from
the failing response and the output of `script/verify-deployment.sh`.

## License

MIT. See [LICENSE](LICENSE).
