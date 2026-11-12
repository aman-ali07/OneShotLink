# OneShotLink

A self-hostable service for sharing passwords, API keys, and private notes through
**single-use, self-destructing links**. The recipient can view a secret exactly once;
after that it is deleted from the server, and it also expires automatically after a
configurable TTL.

> **Project status: production-packaged core with optional simple-mode accounts,
> pre-alpha product.** The anonymous create → one-time reveal flow and optional accounts
> run in a hardened non-root container with Redis persistence, CI, and redacted logs.
> **112 backend specs pass**; the TypeScript/Vite build, a headless-Chrome secret journey,
> and a browser signup → receipt → signout → signin journey were verified. Operational
> controls (TLS, Redis auth, backups, metrics, scanning, key rotation) are still open: see
> [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md), [KNOWN_ISSUES.md](KNOWN_ISSUES.md),
> and [TASKS.md](TASKS.md).

## What works now

- Vue 3 SPA: conceal form, config-driven TTL, optional passphrase, one-time link with
  copy, reveal confirmation, passphrase prompt, and destroyed state.
- No auto-reveal on page load (link previews cannot burn a secret).
- `POST /api/v3/guest/conceal` and `GET|POST /api/v3/guest/secret/:key[/reveal]`.
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

Not built yet: colonel/admin API, OpenAPI document, file secrets, organizations, i18n.
`AUTH_MODE=full` intentionally returns `501` rather than silently degrading; account
routes return `403` when auth is disabled.
Production gaps that are *not* features (TLS, Redis auth, backups, metrics, dependency
scanning, key rotation) are listed in [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md).

## Stack

Ruby 3.3 · Roda 3 on Rack 3 · Puma 6 · Redis 7+ · Vue 3 + TypeScript · Vite 6 ·
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
spec/                    # 112 unit + integration examples (Redis DB 15)
e2e/journey.mjs          # committed create → reveal → gone browser test
e2e/accounts.mjs         # committed signup → receipt → signout → signin journey
Dockerfile               # multi-stage UI build + non-root Ruby runtime
compose.yaml             # web + persistent Redis
.github/workflows/ci.yml # specs, scans, container + browser smoke test + load test
RUNBOOK.md               # incident procedures (key compromise, Redis loss, rollback)
```

Built by Vite into `public/app/` (git-ignored). Set `AUTH_MODE=simple` to expose account
routes and the dashboard; the default `disabled` keeps the anonymous flow only.

## Quickstart (Compose, recommended)

```bash
export SECRET="$(openssl rand -hex 32)"
export REDIS_PASSWORD="$(openssl rand -hex 24)"
docker compose up -d --build
curl -fsS localhost:3000/health
```

Open `http://localhost:3000/`. The stack runs the web container as UID 10001 with a
read-only root filesystem and a persistent Redis volume. Set `APP_PORT`, `APP_BIND`,
`HOST`, `SSL`, `TRUST_PROXY`, `TRUSTED_PROXIES`, and `WEB_CONCURRENCY` in the environment; see
[.env.example](.env.example) and [DEPLOYMENT.md](DEPLOYMENT.md). Going live on a real
hostname? [DEPLOYMENT.md](DEPLOYMENT.md) §4.2 is the deploy-day sequence, and
`script/tls-rehearsal.sh` rehearses it on a scratch box first.

Smoke test (verified 2026-11-11 through Compose):

```bash
curl -s localhost:3000/health
curl -s -X POST localhost:3000/api/v3/guest/conceal \
  -H 'content-type: application/json' -d '{"secret":"hello","ttl":1800}'
# copy secret_key from the response, then:
curl -si localhost:3000/api/v3/guest/secret/<key>   # 200
curl -si localhost:3000/api/v3/guest/secret/<key>   # 404
```

## Local development (no host Ruby required)

Ruby/Bundler are absent on this host, so the verified test path uses a dev image. Build
it once and create the bundle volume:

```bash
docker build -t ots-dev - <<'EOF'
FROM ruby:3.3-slim
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libssl-dev curl \
 && rm -rf /var/lib/apt/lists/*
EOF
docker volume create ots-bundle
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

Expected: `112 examples, 0 failures`. The suite only touches Redis DB 15 and calls
`FLUSHDB` there, never `FLUSHALL`.

Frontend checks:

```bash
# Account journey against a running AUTH_MODE=simple instance
BASE_URL=http://127.0.0.1:3000 npm --prefix e2e run test:accounts

npm --prefix frontend test
npm --prefix frontend run typecheck
npm --prefix frontend run build
```

Vitest covers the Zod API client. A committed puppeteer journey covers the full browser flow;
run it against a live stack with `BASE_URL=http://127.0.0.1:3000 npm --prefix e2e test`.

## Clone workflow

This is a clean-room rebuild of the original's core features. The MIT `replica-*` skill
pack (installed under `~/.agents/skills/`) drives recon → architect → design → build →
backend → test → diff → entrepreneur → brand → launch → deploy. Current artifacts:

- [replica/recon.md](replica/recon.md) — public-source map, evidence gaps
- [replica/features.csv](replica/features.csv) — 27-feature matrix
- [replica/architecture.md](replica/architecture.md) — v1 architecture
- [replica/design/tokens.json](replica/design/tokens.json) — AA-checked tokens, applied by the SPA
- [replica/parity.md](replica/parity.md) — M2 **60.6/100** (10/11 must-haves); the last
  is the deliberate D-012 passphrase divergence

The original's name, logo, copy, screenshots, and fonts are never copied. A rebrand is
mandatory before launch; the brand sweep still reports the HKDF salt (K-23) and must pass
before any deploy.

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
- [TESTING.md](TESTING.md) / [DEPLOYMENT.md](DEPLOYMENT.md)
- [RUNBOOK.md](RUNBOOK.md) — incident response (key compromise, Redis loss, rollback)
- [TECH_STACK.md](TECH_STACK.md) / [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)
- [docs/DECISIONS.md](docs/DECISIONS.md) / [KNOWN_ISSUES.md](KNOWN_ISSUES.md)
- [CHANGELOG.md](CHANGELOG.md)

## License

MIT. See [LICENSE](LICENSE).
# OneShotLink
