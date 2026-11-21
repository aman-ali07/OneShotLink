# Contributing to OneShotLink

Thanks for helping. OneShotLink is a pre-alpha, self-hostable single-use secret service.
Please read [AGENTS.md](AGENTS.md) first: it is the authoritative rule set, and this file is a
short practical index of it. By contributing you agree to the [code of conduct](CODE_OF_CONDUCT.md).

## Ground rules

- Smallest change that satisfies the request — no unrequested features, drive-by refactors or
  speculative abstractions.
- Evidence before claims: inspect code, run checks, paste command output. Never describe planned
  behaviour as implemented. [KNOWN_ISSUES.md](KNOWN_ISSUES.md) and the status banners are the
  source of truth.
- One change at a time. Never disable, skip or weaken a test to get a green run.
- Never log or commit secret material (see "Secrets" below).

## Prerequisites

| Tool | Version / notes |
| --- | --- |
| Ruby | 3.3 (CI and runtime image use 3.3). Ruby/Bundler are **not required on the host** — the Docker fallback below is supported. |
| Node.js | 24 (CI and the frontend build image use 24; there is no `.nvmrc`, so pin it locally). |
| Redis | 7+ (CI uses `redis:7.4-alpine`). Specs use **database 15 only**. |
| Docker + Compose v2 | Required for the container build/smoke test and the no-host-Ruby test path. |
| `openssl`, `curl` | Secret generation and HTTP probes. |
| Chrome/Chromium + `CHROME_PATH` | Eight headless browser journeys. |
| Python 3 (stdlib) + git | Replica tooling (`parity.py`, `brand-sweep.sh`, `contrast.py`). |

## Branch / PR flow

- Default branch is `main`. Work on a topic branch; keep each PR to one change.
- **Tell the human before you act and before you push.** Do not push, open a PR or merge without
  saying so first. Never auto-merge to `main`.
- Open a **draft PR** first; a human marks it ready and performs the merge.
- Reference the stable `TASKS.md` ID in the branch, commit and PR (IDs are never renumbered).
  Update `TASKS.md` and the `clone` column of `replica/features.csv` in the same change that earns it.
- Commit style: conventional commits, e.g. `fix: refuse oversized reveal passphrase (SA-53)`,
  `docs: add contributor guide`, `test: pin passphrase budget window (K-47)`. Types: `feat`,
  `fix`, `docs`, `test`, `refactor`, `chore`, `security`.

## Protected paths — operator review required before touching

Ask first; do not assume: `lib/onetime/crypto.rb`, `lib/onetime/password.rb`,
`lib/onetime/models/session.rb`, `lib/onetime/web/app.rb`, `compose.yaml`, `Dockerfile`,
`config.ru`, `config/puma.rb`, `.github/workflows/`, `script/preflight*.sh`, anything under
`auth/`, `payments/`, `secrets/`, credentials, or any `*.pem` / `*.key`.
**Never edit `.env` or `.env.*`**; document new variables in `.env.example` with placeholders only.
Agents do not `docker compose up` on a public host, rotate `SECRET`, or restore a backup.

## Tests

Native (requires Ruby 3.3 + Bundler installed locally; if they are missing, skip to the
Docker fallback below — that is how this repository's CI and this host run the suite):

```bash
bundle install
bundle exec rspec
npm --prefix frontend ci
npm --prefix frontend run test
npm --prefix frontend run typecheck
npm --prefix frontend run build
```

Docker fallback (no host Ruby/Bundler):

```bash
docker build -t ots-dev - <<'EOF'
FROM ruby:3.3-slim
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libssl-dev curl \
 && rm -rf /var/lib/apt/lists/*
EOF
docker volume create ots-bundle
docker run --rm -v "$PWD":/app -v ots-bundle:/bundle -e BUNDLE_PATH=/bundle -w /app ots-dev bundle install
docker run -d --rm --name ots-test-redis -p 6399:6379 redis:7.4-alpine
docker run --rm --network=host \
  -v "$PWD":/app -v ots-bundle:/bundle -e BUNDLE_PATH=/bundle -w /app \
  ots-dev bundle exec rspec
```

Specs `FLUSHDB` on **DB 15 only** and refuse a different DB or a busy DB 15 — never `FLUSHALL`.
Browser and hygiene gates:

```bash
BASE_URL=http://127.0.0.1:3000 npm --prefix e2e test        # plus test:accounts, test:file,
                                                            # test:requests, test:webhooks,
                                                            # test:states, test:mobile, test:a11y
BASE_URL=http://127.0.0.1:3000 script/verify-deployment.sh  # all-in-one deployment proof
script/brand-sweep.sh                                       # rebrand gate must exit 0
```

Deployment changes must also pass `docker build -t ots-prod .` and
`SECRET=$(openssl rand -hex 32) docker compose config`.

New/changed behaviour needs a spec that **fails before** the fix and passes after, or the gap must
be stated in the handoff. See [TESTING.md](TESTING.md) §6 for the full quality gate.

## Docs to update with the change

- [API.md](API.md) — routes/payloads/errors; [DATABASE.md](DATABASE.md) — key shapes;
- [SECURITY.md](SECURITY.md) — controls; [CHANGELOG.md](CHANGELOG.md) — user-visible changes;
- [TASKS.md](TASKS.md) + `replica/features.csv` — status of record (`yes`/`partial`/`no`/`skip`);
- [docs/DECISIONS.md](docs/DECISIONS.md) for any new gem/npm package, plus the canonical check in
  [TECH_STACK.md](TECH_STACK.md); `.env.example` for new env vars.

## Secrets

- `.env` is git-ignored; use placeholders in `.env.example`. Never commit keys, tokens or DB dumps.
- Specs may use literal fixture strings; never real credentials.
- Never print request bodies for `/api/v3/guest/conceal`, `/api/v3/guest/secret/:key` or `/api/v1/share`,
  log ciphertext, or add analytics/APM that captures bodies without redaction review.
- Never paste secret values, passphrases or tokens into issues, PRs, logs or docs. For live bugs,
  include the `X-Request-Id` from the failing response instead.
- Rotate keys with `bin/ots rotate-key` (CAS re-encryption), never by deleting/regenerating `SECRET`.

## Clone-specific rules

Clean room: never read or copy the original's source, bundles, private APIs, logos, illustrations,
copy or fonts. Re-read `replica/recon.md`, `replica/architecture.md` and `replica/features.csv`
before UI/API work. Rebrand is mandatory before launch. Screenshots in `replica/screens/` are
references only and never become assets.

## Reporting bugs and vulnerabilities

Open a GitHub issue with `X-Request-Id` and `script/verify-deployment.sh` output for ordinary bugs.
**Security vulnerabilities must not be filed as public issues** — follow [SECURITY.md](SECURITY.md).
