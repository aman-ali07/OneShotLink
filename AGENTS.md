# AGENTS.md — project instructions

OneShotLink: a self-hostable, single-use secret sharing service. Clean-room clone of the
original one-time secret service.
**Stack:** Ruby 3.3 + Roda on Rack 3 + Puma, Redis, Vue 3 + TypeScript + Vite + Tailwind.
**Status:** production-packaged core with optional simple-mode accounts. The Vue SPA and
APIs support create → link → reveal once → gone, including the passphrase path; account
signup/signin, owner receipts, and the dashboard are implemented. **118 backend specs pass**,
two headless browser journeys are verified, and the non-root Compose stack is smoke-tested.
Every in-repo gate is closed (Redis auth, network isolation, backups, metrics, dependency
scanning, key rotation, load test). Still open: **TLS on a real hostname** (T-70 — operator
infrastructure; the app side is rehearsed by `script/tls-rehearsal.sh`) and `AUTH_MODE=full`,
which is deliberately unimplemented and answers 501.
Read [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md) and
[KNOWN_ISSUES.md](KNOWN_ISSUES.md) before assuming anything is production-ready.

## How to use these docs

Coding agents discover this file by walking up from the project directory, but none of them
read every Markdown file automatically. Read the relevant file before working in that area:

| Area | Read first |
| --- | --- |
| Product scope, acceptance criteria | [PRD.md](PRD.md) |
| System design, folder layout, data flow | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Versions, dependencies, rationale | [TECH_STACK.md](TECH_STACK.md) |
| Redis keys, record shapes, migrations | [DATABASE.md](DATABASE.md) |
| HTTP routes, payloads, errors | [API.md](API.md) |
| Auth, crypto, threat model, prohibited actions | [SECURITY.md](SECURITY.md) |
| Tests, commands, quality gates | [TESTING.md](TESTING.md) |
| Env vars, Docker, operations | [DEPLOYMENT.md](DEPLOYMENT.md) |
| Production gates / open ops work | [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md) |
| UI rules + implemented token values | [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md), [replica/design/tokens.json](replica/design/tokens.json) |
| Current work queue | [TASKS.md](TASKS.md) |
| Milestones, order, dates | [ROADMAP.md](ROADMAP.md) |
| Why we chose something | [docs/DECISIONS.md](docs/DECISIONS.md) |
| Known defects / gaps | [KNOWN_ISSUES.md](KNOWN_ISSUES.md) |
| Clone map + feature matrix | [replica/recon.md](replica/recon.md), [replica/features.csv](replica/features.csv) |
| Clone stack, schema, build order | [replica/architecture.md](replica/architecture.md) |

This repo has no agent-specific config file and needs none: the instructions live here.
Do not add a tool-specific rules file unless a concrete need appears (MCP server, custom
permissions, a sub-agent). No nested `AGENTS.md` files until a subtree genuinely needs
different rules.

## Replica clone workflow (mandatory)

This project is a clean-room clone of the original service's core features. The
`replica-*` skill pack is installed globally under `~/.agents/skills/replica-*`
(source: https://github.com/Jakeschincariol/replica-skill, MIT). Use it for every
clone-related task, in this order:

```
recon -> architect -> design -> build -> backend -> test -> diff
      -> entrepreneur -> brand -> launch -> deploy
```

Rules:

- **Re-read `replica/recon.md`, `replica/architecture.md`, and the current
  `replica/features.csv` before building UI or API work.** The matrix's `clone` column is
  the status of record; update it in the same change that implements a feature
  (`yes`, `partial` with a note, `no`, `skip`).
- **Clean room.** Never read or copy the original's source code, JavaScript bundles,
  network calls, private APIs, logos, illustrations, copy, or fonts. Public pages, public
  docs, and the user's own account are the only evidence sources.
- **Rebrand before launch.** `/replica-brand` (with `sweep.py`) must pass before any
  deploy. The brand is **OneShotLink** (`replica/brand.md`, `replica/brand.json`);
  references to the original are working titles only, not shippable branding. Do not add
  the original's name or domain to UI copy, links, or metadata.
- **No invented parity.** If a feature is deferred, it stays `no`/`skip` in the matrix
  and in PRD.md; never mark it `yes` to improve the score.
- **Screenshots are references only.** They belong in `replica/screens/`, are git-ignored,
  and never become assets.

Useful commands (tools are stdlib Python; run them from the repo root):

```bash
python3 ~/.agents/skills/replica-diff/parity.py replica/features.csv
script/brand-sweep.sh                                   # rebrand gate over shipped files
script/build-assets.sh                                  # icons + og.png from their SVG/HTML sources
python3 ~/.agents/skills/replica-design/contrast.py replica/design/tokens.json   # WCAG contrast
```

`script/brand-sweep.sh` is the gate, not the raw tool: it runs `sweep.py` over the tracked
files that ship (code, config, static assets, specs, e2e) and skips prose (`*.md`) and the
`replica/` planning folder, where the original's name legitimately appears as a comparison.
It copies those files into a temp tree first, so untracked run artifacts (logs, transcripts,
anything a tool drops in the working tree) can never turn the gate red. Run `sweep.py` over
the whole repo by hand when you want to audit prose too.

If the skills are missing (new machine), reinstall them with:

```bash
git clone https://github.com/Jakeschincariol/replica-skill.git /tmp/replica-skill
cp -r /tmp/replica-skill/replica-* ~/.agents/skills/
```

On a clone milestone, run the pack's own tests before trusting its tooling:
`cd /tmp/replica-skill && python3 -m unittest discover -s tests`.

## Ground rules

1. **Smallest change that satisfies the request.** No unrequested features, files,
   abstractions, or drive-by refactors.
2. **Evidence before claims.** Inspect the code; never describe planned behavior as
   implemented. `KNOWN_ISSUES.md` and the status banners are the source of truth.
3. **Match existing style.** Standard Ruby (double-quoted strings are already used),
   frozen string literals, `module_function` for stateless modules. Frontend style is set in
   [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) (tokens: [replica/design/tokens.json](replica/design/tokens.json)).
4. **Reuse before building.** Grep `lib/onetime/` for an existing helper — e.g. use
   `Onetime::Crypto.secure_compare`, `Onetime::Ids.extid`, `Onetime::Limiter.check!`
   instead of new equivalents.
5. **No new abstraction without 2–3 real call sites.** This repo intentionally avoids
   inventing an ORM: the Redis access is in `Onetime::Store` and model modules.
6. **Validate at the boundary.** HTTP input is validated in the Roda layer (and with
   Zod on the frontend). Domain logic raises `Onetime::Error` subclasses.
7. **Never log secret material.** No plaintext, passphrase, ciphertext, token, or
   cookie values in logs, errors, specs output, or docs.
8. **Keep secrets out of the repo.** `.env` is git-ignored; document variables in
   `.env.example` with placeholders only.
9. **Say your assumptions; do not pick silently.** If two readings of a request exist, name
   both. If something is unclear, stop and ask rather than guessing at intent.
10. **Clean up only your own mess.** Remove imports, variables and helpers *your* change
   orphaned. Leave unrelated dead code alone — mention it instead of deleting it.

## Operating rules (binding)

These bind any agent or human working in this repo. They are the rules that used to sit in
a separate automation kit; the automation is gone, the rules are not.

1. **Tell the human before you act, and before you push.** Do not push, open a PR, or merge
   without saying so first. Never auto-merge to `main`. Open a draft PR and let a human mark
   it ready.
2. **Tests decide, not prose.** Run the checks before proposing a fix, and run them yourself
   rather than trusting a report that they passed. Never disable, skip, or weaken a test to
   get a green run. If the same failure appears twice, stop retrying and read the code, the
   docs, or the full error instead.
3. **One change at a time.** No unrelated refactors, no drive-by cleanups, no second fix
   bundled into the first. If a fix needs more than a few attempts, escalate to the human
   instead of thrashing.
4. **Some paths need human review before you touch them:** `lib/onetime/crypto.rb`,
   `lib/onetime/password.rb`, `lib/onetime/models/session.rb`, `lib/onetime/web/app.rb`,
   `compose.yaml`, `Dockerfile`, `config.ru`, `config/puma.rb`, `.github/workflows/`,
   `script/preflight*.sh`, and anything under `auth/`, `payments/`, `secrets/`, credentials,
   or any `*.pem` / `*.key`. Ask; do not assume.
5. **Never edit `.env` or `.env.*`.** Document variables in `.env.example` with placeholders.
6. **Copy rules (D-012, [SECURITY.md](SECURITY.md)):** never write "zero-knowledge" or "the
   server cannot decrypt" — the passphrase is an access gate, not a second key. Never write
   "production ready" while T-70 (TLS on a real host) or T-71 (Redis host firewall) are open
   in [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md).
7. **Status of record:** [TASKS.md](TASKS.md) (IDs are stable — never renumber) and the
   `clone` column of [replica/features.csv](replica/features.csv). Update them in the same
   change that earns it.
8. **No new gem or npm package** without a line in [docs/DECISIONS.md](docs/DECISIONS.md) and
   a check that it is canonical per [TECH_STACK.md](TECH_STACK.md).
9. **Report, do not deploy.** An agent run does not `docker compose up` on a public host,
   does not rotate `SECRET`, and does not restore a backup. Those are human actions with a
   defined sequence: [DEPLOYMENT.md](DEPLOYMENT.md) §4.2 and [RUNBOOK.md](RUNBOOK.md).

## Required coding workflow

1. Read this file, then the doc(s) for the area you will touch.
2. Inspect the current implementation and tests; identify what actually exists.
3. Write down ambiguities, risks, dependencies, and affected files. Ask only if a
   critical decision cannot be inferred from `docs/DECISIONS.md`.
4. Break the work into small, testable steps and update [TASKS.md](TASKS.md) when the
   plan or status changes (use the existing task IDs; add new ones only when needed).
5. Implement the minimal change that follows [ARCHITECTURE.md](ARCHITECTURE.md) and the
   relevant contract docs.
6. Run the checks that apply: `bundle exec rspec`, `npm --prefix frontend run typecheck`,
   `npm --prefix frontend run build`, `docker build -t ots-prod .`, and
   `SECRET=... docker compose config`. **Ruby is not installed on this host**, so the
   backend suite runs in Docker —
   `docker run --rm --network=host -v "$PWD":/app -v ots-bundle:/bundle -e BUNDLE_PATH=/bundle -w /app ots-dev bundle exec rspec`
   ([TESTING.md](TESTING.md) §2). Never claim a check passed without command output.
7. Fix regressions and manually exercise the changed behavior (curl/browser) where the
   test suite does not cover it.
8. Update the docs the change invalidates: API.md for routes/payloads, DATABASE.md for
   key shapes, SECURITY.md for controls, CHANGELOG.md for user-visible changes.
9. Report: what changed, commands run with results, and what remains unverified.

## Definition of done (all must hold)

- Diff is minimal and matches the request; no unrelated edits.
- No duplicated helpers; existing ones reused.
- Inputs validated at the boundary; errors are typed, not swallowed.
- Tests assert observable behavior and were seen to fail before the change and pass
  after, or the gap is stated explicitly.
- The changed path was actually executed (request/response, test output, build log).
- No secret material in code, logs, fixtures, or docs; no credentials committed.
- Docs/TASKS updated; `CHANGELOG.md` updated for user-visible behavior.
- Anything not run is named in the final report.

## Project rules that are easy to get wrong

- **Do not introduce Rails, ActiveRecord, or a second web framework.** Roda on Rack 3.
- **Do not add an ORM dependency.** Redis access stays in `lib/onetime/store.rb`; models
  are modules with explicit key builders (see [DATABASE.md](DATABASE.md)).
- **One-time reveal is a security invariant.** The consume must stay atomic
  (compare-and-delete Lua). Never replace it with read-then-delete in Ruby.
- **Nothing irreversible before the work succeeds.** Both the passphrase check and the
  decryption run *before* `Store.consume`: a wrong passphrase, a rotated `SECRET` or a
  corrupt record leaves the secret readable instead of destroying it. Do not move
  `Crypto.decrypt` after the consume.
- **Record encoding is constrained:** `Onetime::Store.consume` compares a single string
  value with `GET`, so secret records must remain JSON strings, not Redis hashes.
- **API versions are contracts.** v1 shapes must not change; v3 is native JSON.
- **`AUTH_MODE=full` is not implemented.** It must fail with 501, never silently fall
  back to simple mode.
- **No plaintext in Redis.** Only `Onetime::Crypto` output is persisted.

## Prohibited actions

- Committing `.env`, real keys, tokens, or database dumps.
- Logging request bodies for secret/passphrase endpoints.
- Weakening auth, rate limits, validation, or the atomic consume to make a test pass.
- Destructive operations on shared data (Redis `FLUSHALL`, dropping databases, deleting
  volumes) without explicit human approval. Tests may only use database 15.
- Editing files outside this repository without approval.
