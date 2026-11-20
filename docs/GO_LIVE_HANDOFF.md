# Go-live decision memo — OneShotLink

Snapshot: **2026-11-20**, verified on the `dd14fa7` tree plus the final `REDIS_PASSWORD`
sentinel guard (both pushed). Companion artifact:
[FEATURE_EVIDENCE.md](FEATURE_EVIDENCE.md).

## Production audit: 84/100 — launchable with caveats

Every in-repo gap found by the four-role production audit is closed and verified below. The
remaining risks are operator-owned: TLS on a real hostname, a domain serving the legal
pages, trademark/handle screening, and a green preflight on the real host. The repo's binding
rule (`AGENTS.md`, `PRODUCTION_READINESS.md` §Verdict) still forbids calling this
"production ready" while T-70/T-71 are open. **No deploy was performed.**

## Gates re-run at `dd14fa7` (command → result)

| Gate | Command | Result |
| --- | --- | --- |
| Backend suite | `docker run … ots-dev bundle exec rspec` (Redis on :6400/15) | **133 examples, 0 failures** (seed 21790) |
| Frontend unit | `npm --prefix frontend run test` | **11 passed** (Vitest 5.1.0) |
| Frontend typecheck + build | `npm --prefix frontend run typecheck && npm --prefix frontend run build` | clean `vue-tsc`; 212.69 kB JS / 14.21 kB CSS |
| Rebrand gate | `script/brand-sweep.sh` | clean |
| Feature parity | `parity.py replica/features.csv` | **63.0 / 100**, must-haves **11 / 11** |
| Compose config | `SECRET=… REDIS_PASSWORD=… docker compose config --quiet` | OK |
| Image build | `docker build -t ots-prod:final-check .` | built `8180a4d41b81` |
| TLS rehearsal (app side of T-70) | `script/tls-rehearsal.sh` | `PREFLIGHT PASSED (1 skipped)` — validated chain, HSTS, headers, cookie flags, HTTP→HTTPS redirect |
| Browser lifecycle | `BASE_URL=… npm --prefix e2e test` | `ok: true`, zero console errors |
| Browser accounts | `BASE_URL=… npm --prefix e2e run test:accounts` | `accounts journey ok` |
| Load / single-use | `docker run … ruby script/loadtest.rb 100 20` | **100/100 revealed exactly once**, 0 wrong, 104 creates/s |
| Preflight self-test | `script/preflight_selftest.sh` | **5 assertions passed**, including both negative controls |
| Dependency audits | `bundler-audit check --update` / `npm audit --audit-level=high` | **0 vulnerabilities** across 1379 advisories / **0** |
| CI YAML | `ruby -ryaml -e 'YAML.load_file(…)'` | parses |

All local verification resources (`ots-final`, `ots-final-redis`, `ots-test-redis`) were
throwaway and have been torn down.

## In-repo gaps closed in this pass

| ID | Gap | Fix / evidence |
| --- | --- | --- |
| K-41 | Login/signup CSRF; CSRF checked only `uri.host` | Shared full-origin proof on signin/signup and cookie mutations; 5 specs red→green; 133/0 (T-104) |
| K-42 | Key rotation could resurrect a consumed secret | Lua compare-and-swap `Store.rewrite_if_unchanged` with `KEEPTTL`; 4 specs red→green (T-105) |
| K-43 | Backup lost owner receipts and customer zsets | Receipt hashes with TTL exported/restored; zset/set restore added; 2 specs red→green (T-106) |
| K-44 | `.env.example` placeholder passed boot validation (32 bytes) | Placeholders now `CHANGE-ME`; boot rejects both the short `SECRET` and the `REDIS_PASSWORD=CHANGE-ME` sentinel, with specs reading the committed example (T-107) |
| T-108 | Rollback prescribed a `docker pull` no-op; stale counts | Rollback checks out a known-good commit and rebuilds; live spec counts reconciled to 133 |
| T-109 | CI omitted brand sweep and Compose validation | Both added; rebrand tool pinned to SHA `77c9436` (hash verified locally against the installed tool) |

Earlier in the session K-38 cleared four newly disclosed Puma 7.2.1 advisories with a
7.2.3 lockfile bump (0 vulnerabilities today). Protected paths (`app.rb`, workflows) were
edited only with explicit operator approval.

## Open items — all require a human or a real host

| ID | Item | Owner | State |
| --- | --- | --- | --- |
| T-70 | TLS on a real hostname + public CA chain | operator | App side rehearsed twice: direct and behind Caddy. DNS and the real chain cannot be proved from the repo |
| B2 | Domain with legal pages actually served | operator | `site/privacy.html` / `site/terms.html` exist; no DNS, so `og:image` is still relative |
| B4 | Trademark/handle screening remainder | human + lawyer | Core markets screened; adjacent US marks, WIPO/Canada/handles and open-web search remain (`replica/brand.md` §2) |
| B5 | Preflight green on the real host | operator | Never run against a live domain; go/no-go for the managed tier |
| B6 | Host → Redis:6379 drop rule | operator (per host) | Applied and proven here (T-85/T-96); a new host must apply `DEPLOYMENT.md` §4.0 again. `replica/deploy.md` is now current on this point |
| — | Feature-matrix discrepancy | human decision | Four shipped capabilities are still `clone: no` in `replica/features.csv`; see `FEATURE_EVIDENCE.md`. Not changed — flipping them to raise the score would be invented parity |

## Operator sequence for a real go decision

1. Buy the domain; point `app.` and apex at the VM; serve `site/` at apex.
2. Terminate TLS at the proxy; set `SSL=true`, `HOST=https://app.<domain>`, `TRUST_PROXY=true`,
   `TRUSTED_PROXIES=<proxy CIDRs>`; generate `SECRET`/`REDIS_PASSWORD` into a `0600` `.env`.
   The example placeholders now fail closed, so an unfilled copy cannot boot.
3. Apply the per-host Redis firewall rule (`DEPLOYMENT.md` §4.0).
4. Run `HOST=https://app.<domain> PREFLIGHT_ALLOW_SIGNUP=1 script/preflight.sh` and paste the
   output into `replica/deploy.md` §1. Exit 0 closes B5.
5. On the live domain: create → reveal → second reveal `404`; restore a backup into a scratch
   instance (receipts and owner index now come back too); re-run preflight after any change.
6. Only then record the live URL at the top of `replica/deploy.md`, close B2/B4/B5/B6, and ask
   the human for the go. Until then keep saying "production-packaged, go-live pending".

## Decisions not taken here

- `.claude/` remains untracked. D-011 keeps root `AGENTS.md` as the single instruction file;
  using the installed `production-audit` / `dev-team` skills is not a reason to vendor the tree.
- No deferred product features were added; they remain `no`/`skip` in the feature matrix.
- No deploy, key rotation, backup restore, or public "production ready" / "zero-knowledge"
  claim. Copy rules D-012 and the T-70/T-71 prohibition remain in force.

## Approval

Go/no-go owner: ______________________  Date: __________  Decision: __________
