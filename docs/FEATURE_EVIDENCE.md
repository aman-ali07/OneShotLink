# Feature → evidence matrix

Snapshot: 2026-11-20, HEAD `dd14fa7`. Scope: production-readiness verification and the
in-repo fixes it surfaced. "Verified" means a command was run and its output is recorded in
[GO_LIVE_HANDOFF.md](GO_LIVE_HANDOFF.md). No parity value was changed by this pass —
`replica/features.csv` remains the status of record (63.0/100, must-haves 11/11).

## Rows counted as `yes` (the 11 must-haves)

| # | Feature | Evidence | Verification at `dd14fa7` |
| --- | --- | --- | --- |
| 2 | Create a secret from pasted text | `spec/integration/secrets_api_spec.rb` (v3 guest conceal `201`); `e2e/journey.mjs` | PASS — 132/0; lifecycle journey `ok: true` |
| 3 | Reveal exactly once and destroy | `spec/integration/secrets_api_spec.rb` (8-way race); `script/loadtest.rb` | PASS — 20-way race, 100/100 exactly once, 0 wrong |
| 4 | Configurable expiry (TTL) | `spec/integration/secrets_api_spec.rb` TTL allowlist + Redis TTL | PASS (in 132/0) |
| 5 | Copyable one-time link | `frontend/src/views/ConcealView.vue` copy button; `e2e/journey.mjs` navigates the link | PARTIAL — link generation exercised by the journey; **no dedicated clipboard assertion** (documented gap) |
| 6 | Optional passphrase gate | `spec/integration/secrets_api_spec.rb`; `spec/unit/password_spec.rb`; D-012/D-014; `e2e/journey.mjs` | PASS — wrong attempt preserves the record; 7/8-byte floor in RSpec and browser |
| 7 | Expired / viewed / unknown terminal states | `spec/integration/secrets_api_spec.rb` (uniform `404`) | PASS (in 132/0) |
| 8 | REST API create and reveal | `spec/integration/secrets_api_spec.rb` (v1 form + JSON, v3 guest) | PASS (in 132/0) |
| 9 | Guest use without an account | `spec/integration/secrets_api_spec.rb` guest routes | PASS (in 132/0) |
| 10 | Encryption at rest | `spec/integration/secrets_api_spec.rb` ciphertext-only assertion; `spec/unit/crypto_spec.rb` | PASS (in 132/0) |
| 11 | Rate limiting on create and reveal | `spec/unit/limiter_spec.rb`; `spec/integration/secrets_api_spec.rb` (`429` + Retry-After) | PASS (in 132/0) |
| 12 | Accessible responsive create/reveal UI | `e2e/journey.mjs`; headless DOM audit at 375/768/1280 px (T-35) | PARTIAL — journey passed with zero console errors; **no committed axe-core assertion** (documented gap) |

## Rows marked `partial`

| # | Feature | Evidence | Note |
| --- | --- | --- | --- |
| 33 | Published crypto spec / "verify it yourself" page | `SECURITY.md` | No standalone verifiable spec page; unchanged |

## Audit follow-ups and their evidence

| Gap | Spec / command that proves the fix |
| --- | --- |
| Login/signup CSRF, host-only origin check (K-41) | `spec/integration/accounts_spec.rb` "request origin proofs" — 5 examples, red (4 failures) → green; browser journeys and TLS rehearsal re-run |
| Rotation race (K-42) | `spec/unit/store_spec.rb` CAS cases + `spec/unit/ops_spec.rb` "does not resurrect a secret consumed between the read and the rewrite" — 4 red → green |
| Backup receipt loss (K-43) | `spec/unit/ops_spec.rb` receipt-TTL and owner-index-zset cases — 2 red → green |
| Known example key (K-44) | `spec/unit/config_spec.rb` reads the committed `.env.example` and asserts its `SECRET` fails `Config.validate!` — red → green |
| Non-executable rollback, stale counts (T-108) | `RUNBOOK.md` §6 / `DEPLOYMENT.md` §7 reviewed against `compose.yaml` (`build:`, no `image:`); counts reconciled across all live status lines |
| Missing CI gates (T-109) | `script/brand-sweep.sh` run clean locally; workflow YAML parsed; pinned `sweep.py` SHA `77c9436` hash-matched against the installed tool |

## Discrepancy requiring a human decision (not changed here)

Four shipped capabilities are still marked `clone: no` in `replica/features.csv` while
`TASKS.md`/`PRODUCTION_READINESS.md` describe them as implemented:

| CSV row | CSV value | Docs say |
| --- | --- | --- |
| 13 — Email/password accounts (simple mode) | `no` | T-40 DONE |
| 14 — Owner dashboard of active receipts | `no` | T-34 DONE |
| 22 — Security audit trail | `no` | T-46 / "Audit trail" DONE |
| 23 — OpenAPI document and rate-limit headers | `no` | T-44 / T-26 DONE |

The parity tool reads the CSV and reports 63.0 with 11/11 must-haves, matching the frozen
milestone record (T-93). Two notes in those rows are themselves stale: row 14 says "no UI
yet" and row 23 says "planned T-44/T-26". This pass changed none of them: flipping status to
improve a score is the "invented parity" the clone rules forbid. Either confirm the CSV is
intentionally conservative — the original's SSO/verification/paid audit trail are absent —
or explicitly authorize a parity correction with a `parity.py` re-run and matching updates to
`TASKS.md` / `replica/parity.md`. Do not do it silently.

## Unverified by automation

- Live DNS name and public certificate chain (operator, T-70); preflight on a real host (B5).
- Domain-served legal pages (B2) and remaining trademark/handle screening (B4).
- Clipboard copy and axe-core accessibility assertions (gaps listed above).
- Visual parity against the original — no reference screenshots exist (K-22/K-30).
