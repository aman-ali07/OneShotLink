# OneShotLink — Open-source release readiness

**Date:** 2026-11-21
**Scope:** repository contents needed for a public open-source release — README, architecture and
API docs, contributor guidelines, security policy, license, changelog, environment example,
Docker/deployment instructions, and GitHub issue/PR templates. No repository was published, no
commit/tag was created, and nothing was deployed.

## 1. Verdict

The **release tree is complete and staged** (`git add -A`, no commit/push/deploy). A tracked-only
snapshot built from the index (`git write-tree` → `git archive`) now builds, tests and produces a
non-root production image. Publication remains **blocked only by human actions** (commit/tag,
enabling GitHub private vulnerability reporting, publishing a conduct-enforcement contact) and by
the already recorded deployment gates T-70/T-71. The release verdict therefore remains **NO-GO for a public
deployment**, while the **source-package readiness is GO pending the human actions in §5**.

## 2. Method

Five `.claude/` specialists ran in parallel on disjoint scopes: `devrel-docs` (README),
`devrel-api` + `release-docs` (architecture/API/SDK/ADRs), `opensource-packager` (contributor
files and templates), `release-security` (security policy and secret hygiene), and
`devrel-docker` + `devrel-integration` (deployment and container docs). Every report was re-read
against source by the main agent; agent prose alone was never treated as evidence. `@stageshow`
was used for the coordination still `docs/open-source-readiness.html` / `.png`.
`@reverse-engineer-anything` was not used: no competitor artifact was supplied and the complete
clean-room source is available locally (its own routing rule prefers repository tools).

## 3. Release surface

| File | State | Notes |
| --- | --- | --- |
| `README.md` | present, tracked | quickstart, feature list, status/NO-GO banner, dev setup, links; corrected spec count, file-secret wording, prerequisites, verification-script description and reporting pointer this pass |
| `ARCHITECTURE.md` | present, tracked | reconciled v3 MAC version, line ranges, closed contract items and current spec count this pass |
| `API.md` | present, tracked | v1/v3 contracts, preview-vs-consume, error envelopes; typo and 503 claim corrected |
| `docs/SDK.md` | present, tracked | curl/TypeScript/Python quickstarts and advanced flows |
| `CONTRIBUTING.md` | present, **staged (not committed)** | dev setup, tests, protected paths, PR process; native-test precondition clarified this pass |
| `CODE_OF_CONDUCT.md` | present, **staged (not committed)** | standards + enforcement route (contact still needs publishing) |
| `SECURITY.md` | present, tracked | scope, controls, private reporting policy and non-E2EE statement |
| `LICENSE` | present, tracked | MIT, named holder |
| `CHANGELOG.md` | present, tracked | Keep a Changelog 1.1.0 / SemVer; `[Unreleased]` contradiction corrected |
| `.env.example` | present, tracked | invalid `CHANGE-ME` placeholders; CLI-only `OTS_*` stubs added this pass |
| `DEPLOYMENT.md` | present, tracked | Compose, env contract, TLS/proxy, backup/restore; port coupling, proxy topologies and secret-file guidance corrected |
| `Dockerfile` / `compose.yaml` | present, tracked | non-root, read-only rootfs, loopback publish by default; no new issue found |
| `.github/ISSUE_TEMPLATE/*` | present, **staged (not committed)** | bug/feature/documentation forms + config |
| `.github/PULL_REQUEST_TEMPLATE.md` | present, **staged (not committed)** | security-invariant and protected-path checklist |

## 4. Verification evidence

### 4.1 Clean-environment setup

Initially a tracked-only checkout (reconstructed from `git ls-files`) failed with 13 `TS2307`
errors for `@/lib/{authMode,clipboard,config,format}` because those modules and the contributor
files were untracked. **That blocker is resolved:** all 114 untracked non-ignored files plus the
working-tree edits were staged with `git add -A` (nothing committed). A fresh snapshot was then
built strictly from the index — `git write-tree` → `d11ef63bf62b996ae3d3177df65e99f70c69ff64` →
`git archive` — and verified:

```
fresh tree: 289 files; all 12 previously missing source/template files present
npm ci                        → clean (canonical esbuild postinstall)
npm run build                 → ✓ built in 9.02s (253.72 kB JS / 23.00 kB CSS)
npm run test                  → Test Files 8 passed (8), Tests 35 passed (35)
node --check e2e/*.mjs        → all 8 journeys parse
rspec spec/unit               → 138 examples, 0 failures
rspec spec/integration        → 169 examples, 0 failures, 1 pending (conditional asset skip)
docker compose config --quiet → valid
docker build -t ots-fresh-release . → Successfully built; User=ots
```

No `.env` exists in the fresh tree — only `.env.example` — confirming the ignore rules. The
secret scan over the staged snapshot found no credentials or private keys.

### 4.2 Secret and credential hygiene

```
tracked secret-like patterns:      none
tracked .env / .pem / .key files:  .env.example only
SECRET/REDIS_PASSWORD assignments: CHANGE-ME sentinels only
```

Test fixtures (`ci-only-*`, `example-harness-token`, `DUMMY_PASSWORD_HASH`, `@example.com`
emails) are labelled and not real credentials. Privacy/terms pages explicitly negate
end-to-end encryption and zero-knowledge claims.

### 4.3 Fixes applied during this pass

- `script/verify-deployment.sh` now installs `e2e/node_modules` when absent (fresh clones
  previously failed with "Cannot find module 'puppeteer-core'") and documents its
  `AUTH_MODE=simple` requirement.
- OpenAPI: documented `503` on `POST /api/v3/requests` and `429` on both health probes; a red
  spec proved the gap, then `openapi_spec.rb` passed **23/23**.
- README contributor/security/verification copy, CONTRIBUTING native-test guard, CHANGELOG
  `[Unreleased]` wording, `.env.example` CLI stubs, DEPLOYMENT port/proxy/secret guidance,
  ARCHITECTURE/DATABASE/DECISIONS/CRYPTO_SPEC/API drift — all corrected against source.

## 5. Unresolved human actions (blockers, not silently ignored)

1. **Staged, not committed — maintainer sign-off required.** The full release tree is in the git
   index (`git add -A`, 227 files changed); the fresh-clone gate in §4.1 is green. **No commit, tag
   or push was performed** — those remain human actions, as does the final go/no-go signature.
2. **HIGH — enable GitHub private vulnerability reporting** (`SECURITY.md:18-20` still records it
   as a maintainer action) and publish a named conduct-enforcement contact (`CODE_OF_CONDUCT.md`).
3. **MED — tag/sign the release** and complete the sign-off in `RELEASE_CHECKLIST.md` §6.
4. **MED — deployment gates T-70/T-71** still need target-host evidence; no public deployment was
   attempted. `AUTH_MODE=full` remains deliberately unimplemented (501).
5. **LOW — add `license: MIT` to the npm manifests** and a pinned Node version file (`.nvmrc`)
   for reproducible contributor setups; neither is required to build.
6. **LOW — generated posture PNG/HTML files** are untriaged; decide whether to keep them as
   authored coordination artifacts or add them to `.gitignore`.

## 6. Release gate

Source-package contents: **GO** once §5.1–5.2 are actioned. Public deployment: **NO-GO** until
T-70/T-71 and the human sign-offs are recorded. No competitor identity, source, bundle or asset
was copied; the existing OneShotLink identity and all working functionality were preserved.
