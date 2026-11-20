# Go-live decision memo — OneShotLink

Snapshot: **2026-11-20**. Verified at commit `499a93c` plus the Puma 7.2.3 lockfile bump
(T-101). Companion artifact: [FEATURE_EVIDENCE.md](FEATURE_EVIDENCE.md).

## Verdict

**No go for a public launch or a "production ready" claim.** Every in-repo gate is green;
the blocking items are operator-owned infrastructure and approvals, not code. This is the
same conclusion as `PRODUCTION_READINESS.md` and `replica/deploy.md`, re-tested today.

Nothing was deployed. No live keys were generated or rotated, no backup was restored, no
DNS or firewall change was made, and no PR was opened. The only git action was pushing the
existing local commit `499a93c` to `origin/main` at the operator's explicit instruction.

## Gates re-run today (command → result)

| Gate | Command | Result |
| --- | --- | --- |
| Backend suite | `docker run … ots-dev bundle exec rspec` | **119 examples, 0 failures** (seed 21103) |
| Frontend unit | `npm --prefix frontend run test` | **11 passed (1 file)**, Vitest 5.1.0 |
| Frontend typecheck + build | `npm --prefix frontend run typecheck && … run build` | clean `vue-tsc`; Vite built `index-Bmzuog_w.js` 212.69 kB / `index-DRkEURBd.css` 14.21 kB |
| Rebrand gate | `script/brand-sweep.sh` | "Clean. Nothing of the original's name, domain or colours found." |
| Feature parity | `parity.py replica/features.csv` | **63.0 / 100**, must-haves **11 / 11** |
| Compose config | `SECRET=… REDIS_PASSWORD=… docker compose config --quiet` | OK |
| Image build | `docker build -t ots-prod:verify .` | built `49bc46d4fdea`, then rebuilt with Puma fix as `d2b9ea76f725`; container reports **Puma 7.2.3** |
| TLS rehearsal (app side of T-70) | `script/tls-rehearsal.sh` | `PREFLIGHT PASSED (1 skipped)` — 7 assertions: validated chain, HSTS, 3 headers, `Secure`/`HttpOnly`/`SameSite` cookie, HTTP→HTTPS 301. Redis isolation skipped by design |
| Browser lifecycle | `BASE_URL=… npm --prefix e2e test` | `ok: true`, `errors: []` — create → reveal → gone + passphrase path |
| Browser accounts | `BASE_URL=… npm --prefix e2e run test:accounts` | `accounts journey ok` — signup → receipt → signout → signin → delete |
| Load / single-use | `docker run … ots-dev ruby script/loadtest.rb 100 20` | **100/100 revealed exactly once, 0 wrong**, 180.4 creates/s (CI-equivalent rate limits) |
| Preflight self-test | `script/preflight_selftest.sh` | **PASSED (5 assertions)** — healthy config passes; bad cert, plain HTTP, reachable Redis, and missing HOST all fail as required |
| Dependency audit | `bundler-audit check --update` / `npm audit --audit-level=high` | Initially **FAILED**: 4 Puma 7.2.1 advisories. Fixed in T-101 → **0 vulnerabilities** across 1379 advisories; npm **0 vulnerabilities** |

The verification stack (`ots-verify`) and the test Redis (`ots-test-redis`) were local,
throwaway resources; the stack and its volumes were removed after the load test.

## New in this pass: T-101 (fixed and pushed as part of this handoff)

A fresh advisory database (2026-11-19) disclosed four Puma 7.2.1 issues
(`GHSA-r885-m39c-939g`, `GHSA-rf6g-xhmp-gm7v`, `GHSA-x646-wp7c-h9mg`,
`GHSA-xw3h-pgr9-3vg7`) that post-date the "0 vulnerabilities" claim in the docs.
`Gemfile` already declared `~> 7.2`, so `bundle update puma` resolved 7.2.3 and changed
only `Gemfile.lock`. Re-audit, full suite, image rebuild, and version documentation were
all completed; rationale recorded in `docs/DECISIONS.md` D-015 and `KNOWN_ISSUES.md` K-38.

## Open items — all require a human or a real host

| ID | Item | Owner | State |
| --- | --- | --- | --- |
| T-70 | TLS on a real hostname + public certificate chain | operator | App side rehearsed twice today (direct + Caddy terminator). DNS and the real chain cannot be proven from the repo. Gate: `HOST=https://<domain> PREFLIGHT_ALLOW_SIGNUP=1 script/preflight.sh` must exit 0 |
| B2 | Domain with legal pages actually served | operator | `site/privacy.html` and `site/terms.html` exist; no DNS. `og:image` stays relative until a domain exists |
| B4 | Trademark screening remainder + handle checks | human + lawyer | USPTO/EUIPO/TMview/CIPO (owner field), stores, domains and package registries checked; adjacent US marks, WIPO/Canada/handles and open-web search remain (see `replica/brand.md` §2) |
| B5 | Preflight green on the real host | operator | Never run against a live domain. This is the go/no-go for the managed tier |
| B6 | Host firewall rule (host → Redis:6379 drop) | operator | Applied and proven on *this* host (T-85/T-96) but per-host state; a new deployment host must apply `DEPLOYMENT.md` §4.0 again. `replica/deploy.md` still says "not applied" — it is stale on this point |
| — | Feature-matrix discrepancy | human decision | Four shipped capabilities are marked `clone: no` in `replica/features.csv`; see `FEATURE_EVIDENCE.md`. Do not flip them to raise the score without an explicit decision |

## Recommended operator sequence

1. Buy the domain; point `app.` and apex at the VM; serve `site/` at apex.
2. Terminate TLS at the proxy, set `SSL=true`, `HOST=https://app.<domain>`,
   `TRUST_PROXY=true`, `TRUSTED_PROXIES=<proxy CIDRs>`; generate `SECRET` and
   `REDIS_PASSWORD` on the host into a `0600` `.env` (never in git).
3. Apply the per-host Redis firewall rule from `DEPLOYMENT.md` §4.0.
4. Run `HOST=https://app.<domain> PREFLIGHT_ALLOW_SIGNUP=1 script/preflight.sh` and paste
   the output into `replica/deploy.md` §1. Exit 0 closes B5.
5. By hand on the live domain: create → reveal → second reveal `404`; restore a backup into
   a scratch instance; re-run preflight after any config change.
6. Only then record the live URL at the top of `replica/deploy.md`, close B2/B4/B5/B6, and
   ask the human for the go. The managed tier stays unsellable until step 4 passes.

## Decisions not taken here

- **`.claude/` is untracked and was not committed.** D-011 records "no project config";
  the repo already has root `AGENTS.md`. The `dev-team` skill (installed under `.claude/`)
  was used to shape this handoff, but using a skill is not a reason to vendor the whole
  skills tree into the product. Track it only if you explicitly want to.
- No code features were added. Deferred items remain `no`/`skip` in the feature matrix.
- No deploy, key rotation, restore, or public "production ready" / "zero-knowledge" claim.

## Approval

Go/no-go owner: ______________________  Date: __________  Decision: __________
