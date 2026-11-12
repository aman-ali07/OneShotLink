# Roadmap and timeline

This is an effort-based plan for one focused developer (or agent) working sequentially.
Dates are **indicative**, not commitments: they assume ~1 working day per "day" of effort,
no external review bottleneck, and the stack in [TECH_STACK.md](TECH_STACK.md). Every
milestone ends with an evidence gate; a milestone is not "done" because code exists.

At 2026-11-12: docs, recon, architect, and design complete; **M0, M1, M2, the
production-packaging gate, M3 simple-mode accounts, and all in-repo operational gates are
complete.** M0: app boots and 26 specs pass. M1: full secret lifecycle. M2: Vue vertical
slice. Packaging: hardened non-root container, Compose with persistent Redis, CI, redacted
logs. M3: signup/signin/signout, sessions, owner receipts, dashboard, password change, CLI
create/reset, and two browser journeys. Operations: Redis auth + internal network + host
firewall rule, `/metrics`, dependency scanning, key rotation, backup/restore, audit
stream, TLS rehearsal. **119 specs** green; parity **63.0/100 with 11/11 must-haves**
(the remaining parity gaps are should/could items such as email verification and i18n).
Next: **TLS on the operator's own domain** (T-70, the only open gate), then M4
verification.

## Order, and why

```
M0 runnable core ──► M1 secret lifecycle ──► M2 UI vertical slice ──► M3 accounts
                                                          │
                                                          ▼
             M6 deploy ◄── M5 brand/fixes ◄── M4 tests + parity
                    ▲
                    │
        M2.5 production packaging (done)
                                                          
M7 deferred (orgs, domains, i18n, full auth) runs only after M6.
```

| # | Milestone | Comes first because | Depends on |
| --- | --- | --- | --- |
| M0 | Runnable core: entrypoint, boot, `/health`, `/api/v3/config`, test harness, unit specs | Nothing can be verified until the app boots and tests run | — |
| M1 | Secret lifecycle: model, conceal/reveal logic, v1 + v3 routes, atomic consume, rate limits, lifecycle specs | This *is* the product; UI without it has nothing truthful to show | M0 |
| M2 | UI vertical slice: conceal → link → reveal → gone, plus typed API client | The core loop must be usable before secondary screens | M1 |
| M2.5 | Production packaging: fail-closed config, headers, proxy trust, redacted logs, container, Compose, CI | Functional code is not shippable until the deployment contract is verified | M2 |
| M3 | Accounts (simple): signup/in/out, sessions, owner receipts, security headers, redaction | Accounts are additive; they must not block the anonymous loop | M1 |
| M4 | Full test pass, concurrency/expiry proofs, parity re-score, CI | Numbers must be measured before branding or deploying | M1–M3 |
| M5 | Brand + entrepreneur fixes: new name/palette, sweep clean, review-driven fixes, LICENSE | Rebranding earlier wastes work; later blocks launch | M4 |
| M6 | Docker image, Compose, docs finalization, deploy preflight | Packaging is the last step, not the first | M5 |
| M7 | Deferred: orgs/RBAC/SSO, custom domains, incoming requests, i18n, file secrets | Out of v1; each is its own project | M6 |

Deliberate sequencing rules:

- **No UI before the API it calls exists.** No mock screens that imply parity.
- **No feature marked `yes` in `features.csv` without a passing spec.**
- **No auth before the anonymous core loop works.** Accounts must not gate the product.
- **No deploy before the brand sweep is clean and parity must-haves are done or an explicit, documented waiver exists (D-012).**
- **No full-auth/RabbitMQ/Postgres until M7.** It is a separate product decision (D-003).

## Milestones

### M0 — Runnable core (effort: 0.5–1 day) — ✅ done 2026-11-11

Deliverables: `lib/onetime.rb`, `lib/onetime/version.rb`, `config.ru`, `config/puma.rb`,
minimal Roda app with `/health` and `/api/v3/config`, `Gemfile.lock`, `.rspec`,
`spec/spec_helper.rb`, unit specs for crypto/ids/password/limiter/store, Redis test DB 15.

Gate: `bundle exec rspec` green; `GET /health` returns 200 with Redis up and 503 with it
down; no secret material in logs.

### M1 — Secret lifecycle (effort: 2–3 days) — ✅ done 2026-11-11

Deliverables: `Secret` model, `ConcealSecret`/`RevealSecret` logic, API v1 (`/share`,
`/secret/:key`) and v3 guest routes, atomic consume, passphrase flow, rate limits,
`/health` hardening, lifecycle specs (create/reveal/gone, TTL, at-rest encryption,
concurrent reveal).

Gate: PRD §7 criteria 1–4 pass; parity must-haves reach ~7/11.

**Actual:** all four criteria pass (create/reveal/gone, expiry, ciphertext-only Redis,
one winner in an 8-way race); parity is **9/11** (the two open: UI not built; passphrase
is a gate, not zero-knowledge — D-012). Evidence: 40 specs + live Puma run. The remaining
`/health` 503 case with Redis down is not yet tested.

### M2 — UI vertical slice (effort: 2–3 days) — ✅ done 2026-11-11

Deliverables: Vite/Vue/TS/Tailwind scaffold, Zod schemas + API client, conceal view,
reveal view (warning, passphrase prompt, destroyed state), TTL options from
`/api/v3/config`, copy-link, a11y pass, production build served by Rack.

Gate: a browser user can complete F01/F02; no plaintext in URL/localStorage; TypeScript
strict build passes; screenshots captured for `/replica-diff`.

**Actual:** F01/F02 pass in headless Chrome (including the passphrase path), no plaintext
in URL or localStorage, `npm run build` passes, and responsive overflow checks pass at
375/768/1280. Screenshots of the clone were not captured (no reference screenshots to
compare against; K-22), so visual parity remains unmeasured. Next milestone: M3.

### M2.5 — Production packaging (done 2026-11-11)

Deliverables: production Dockerfile, Compose + persistent Redis, CI, CSP/HSTS, trusted
proxy handling, boot validation, Redis timeouts, redacted request logs, cluster-mode Puma,
`PRODUCTION_READINESS.md`.

Gate: image runs non-root with read-only rootfs; `/health` green; lifecycle works through
Compose; secrets survive a web restart; logs contain no secret keys; CI config valid.

### M3 — Accounts, simple mode — DONE (2026-11-11)

Delivered: signup/signin/signout/me, Redis sessions, owner receipt index, dashboard,
password change, CSRF checks, cookie hardening, and `bin/ots customers create` /
`reset-password`. List/health/role CLI commands remain in T-43.

Gate verified: cookie flags; duplicate signup rejected atomically; owner cannot see
another owner's receipts; reveal removes the receipt; browser account journey passes;
secrets never appear in the dashboard or logs. Evidence: `spec/integration/accounts_spec.rb`
(13 examples) and `e2e/accounts.mjs`.

### M4 — Test + parity (effort: 1–2 days)

Deliverables: full RSpec suite, Playwright/click-through plan, `replica/test-plan.md`,
`replica/bugs.md`, parity report, CI workflow, coverage of every documented status code.

Gate: no open S1/S2 bugs; all must-haves are done except the passphrase zero-knowledge
claim, which is explicitly waived by D-012 (not stubbed or relabeled); `replica/parity.md`
committed with the waiver stated.

### M5 — Brand + fixes (effort: 1–2 days)

Deliverables: `replica/fixes.md` from real, linked reviews; new name/domain/ palette;
`sweep.py` clean; LICENSE; landing copy without fake proof; original name absent from
UI, metadata, and package names.

Gate: `script/brand-sweep.sh` exits 0 (the shipped tree is clean); `contrast.py` AA; no
fabricated quotes or numbers.

### M6 — Deploy (effort: 1 day)

The image, Compose stack, health checks, and env contract are already built (M2.5). This
milestone now covers the operational half: TLS, Redis auth/TLS, backup/restore drill,
metrics, incident runbook, and the final preflight report.

Gate: TLS/HSTS verified; backup restores a receipt; metrics/alerts exist; Redis is not
open; user approves the deploy.

### M7 — Deferred (effort: 2–6+ weeks, unscheduled)

Organizations/RBAC/SSO, custom domains + verification, incoming requests, MFA/WebAuthn,
i18n (16+ locales to match the original's advertised set), file secrets, billing. Each
gets its own recon/diff cycle; none is part of the v1 promise.

## Indicative calendar

Start 2026-11-12. "Day" = one focused working day.

| Window | Milestone | Ends with |
| --- | --- | --- |
| Nov 12–14 | M3 accounts | simple auth + dashboard |
| Nov 17–19 | M4 tests + parity | 10/11 must-haves + D-012 waiver, no S1/S2 |
| Nov 20–24 | M5 brand + fixes | clean sweep, new identity |
| Nov 25–28 | M6 ops + deploy | TLS, backups, metrics, preflight green |
| Dec 7–9 | Buffer | regressions, docs, release tag |

v1 target: **week of Dec 7, 2026**, with the buffer consumed by whatever slips. If M3
slips by more than two days, M6 moves by the same amount; do not compress M4 or M5.

## How each milestone is executed

1. Pick the next task IDs from [TASKS.md](TASKS.md); confirm no missing decision.
2. Write or update the failing spec first (behaviour, not mocks).
3. Implement the smallest change; keep contracts in [API.md](API.md)/[DATABASE.md](DATABASE.md)
   in sync.
4. Run the checks: `bundle exec rspec`, frontend typecheck/build, `docker compose config`.
5. Exercise the changed path by hand (curl/browser) and paste the evidence.
6. Update `replica/features.csv` (`clone` column), TASKS status, CHANGELOG, and any doc
   the change invalidated.
7. Re-run `parity.py`; at M4/M5 run `sweep.py` and `contrast.py`.
8. Commit only after the gate passes; one milestone may span several commits.

## Risks to the timeline

| Risk | Impact | Mitigation |
| --- | --- | --- |
| No Ruby on the host | Every check runs in Docker (slower) | M0 produces a lockfile; CI mirrors the Docker command |
| Passphrase-model decision (K-21/T-48) | Rework in crypto + specs | Decide during M1, before routes freeze |
| Reveal race is subtle | Security regression | Dedicated concurrency spec in M1 and M4 |
| Brand/domain/trademark checks | Launch slips | Start name checks during M4, not M6 |
| Full-auth expectations | Scope creep | Explicitly deferred to M7; 501 until then |
| Redis memory growth | Ops incident | 1 MiB cap, `noeviction`, monitoring in M6 |

## What is explicitly not scheduled

Perfect pixel parity with the original, their regional infrastructure, their customer
base, paid-plan billing, native mobile apps, and anything requiring their private APIs.
