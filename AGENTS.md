# AGENTS.md — project instructions

OneShotLink: a self-hostable, single-use secret sharing service. Clean-room clone of the
original one-time secret service.
**Stack:** Ruby 3.3 + Roda on Rack 3 + Puma, Redis, Vue 3 + TypeScript + Vite + Tailwind.
**Status:** production-packaged core with optional simple-mode accounts. The Vue SPA and
APIs support create → link → reveal once → gone, including the passphrase path; account
signup/signin, owner receipts, and the dashboard are implemented. **110 backend specs pass**,
two headless browser journeys are verified, and the non-root Compose stack was smoke-tested.
Operational gates (TLS, Redis auth, backups, metrics, scanning, key rotation) and full mode
are still open; next milestone is M4 verification after those gates.
Read [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md) and
[KNOWN_ISSUES.md](KNOWN_ISSUES.md) before assuming anything is production-ready.

## How OpenCode should use these docs

OpenCode (verified against v2.2.7 on this machine) discovers this file by walking up from
the project directory, and also loads `~/.config/opencode/AGENTS.md` (global). It does **not** read every Markdown file
automatically. Read the relevant file before working in that area:

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

There is no `opencode.json`/`opencode.jsonc` in this repo. Do not add one unless a
concrete need appears (MCP server, permissions, custom agent). No nested `AGENTS.md`
files are needed until a subtree genuinely needs different rules.

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
python3 ~/.agents/skills/replica-brand/sweep.py . --config replica/brand.json
python3 ~/.agents/skills/replica-design/contrast.py replica/design/tokens.json   # once tokens exist
```

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
   frozen string literals, `module_function` for stateless modules. Frontend style is
   set in [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) once it exists.
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
   `SECRET=... docker compose config`. If a tool is not installed, use the documented
   Docker fallback in [TESTING.md](TESTING.md); never claim a check passed without
   command output.
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
- **Passphrase failures must not consume the secret.** Verify first, then consume.
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


Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
