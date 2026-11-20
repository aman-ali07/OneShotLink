# Feature → evidence matrix

Snapshot: 2026-11-20. Scope: verify-only handoff at commit `499a93c` plus the Puma 7.2.3
lockfile bump (T-101). Every row below points at an artifact; "verified" means a command
was run in this session and its output is recorded in [GO_LIVE_HANDOFF.md](GO_LIVE_HANDOFF.md).
No parity value was changed by this verification pass — `replica/features.csv` remains the
status of record (63.0/100, must-haves 11/11).

## Rows counted as `yes` in `replica/features.csv` (the 11 must-haves)

| # | Feature | Evidence | Verification this session |
| --- | --- | --- | --- |
| 2 | Create a secret from pasted text | `spec/integration/secrets_api_spec.rb` (v3 guest conceal `201`); `e2e/journey.mjs` create step | PASS — RSpec 119/0; lifecycle journey `ok: true` |
| 3 | Reveal exactly once and destroy | `spec/integration/secrets_api_spec.rb` (8-way race); `script/loadtest.rb` | PASS — 20-way race, 100/100 revealed exactly once, 0 wrong |
| 4 | Configurable expiry (TTL) | `spec/integration/secrets_api_spec.rb` TTL allowlist + Redis TTL cases | PASS (in 119/0) |
| 5 | Copyable one-time link | `frontend/src/views/ConcealView.vue` copy button; link in conceal response; `e2e/journey.mjs` navigates the link | PARTIAL — link generation exercised by the journey; **copy-to-clipboard has no dedicated automated assertion** (documented gap) |
| 6 | Optional passphrase gate | `spec/integration/secrets_api_spec.rb`; `spec/unit/password_spec.rb`; D-012/D-014; `e2e/journey.mjs` | PASS — wrong attempt preserves the record, correct one reveals; 7/8-byte floor in RSpec and browser |
| 7 | Expired / viewed / unknown terminal states | `spec/integration/secrets_api_spec.rb` (uniform `404`) | PASS (in 119/0) |
| 8 | REST API create and reveal | `spec/integration/secrets_api_spec.rb` (v1 form + JSON, v3 guest) | PASS (in 119/0) |
| 9 | Guest use without an account | `spec/integration/secrets_api_spec.rb` guest routes | PASS (in 119/0) |
| 10 | Encryption at rest | `spec/integration/secrets_api_spec.rb` ciphertext-only Redis assertion; `spec/unit/crypto_spec.rb` | PASS (in 119/0) |
| 11 | Rate limiting on create and reveal | `spec/unit/limiter_spec.rb`; `spec/integration/secrets_api_spec.rb` (`429` + `Retry-After`) | PASS (in 119/0) |
| 12 | Accessible responsive create/reveal UI | `e2e/journey.mjs`; headless DOM audit at 375/768/1280 px (T-35) | PARTIAL — journey passed with zero console errors; **no automated axe-core assertion is committed** (documented gap) |

## Rows marked `partial`

| # | Feature | Evidence | Note |
| --- | --- | --- | --- |
| 33 | Published crypto spec / "verify it yourself" page | `SECURITY.md` | No standalone verifiable spec page; unchanged by this pass |

## Discrepancy requiring a human decision (not changed here)

`replica/features.csv` marks four shipped capabilities as `clone: no`, while `TASKS.md` and
`PRODUCTION_READINESS.md` describe them as implemented and verified:

| CSV row | CSV value | Docs say |
| --- | --- | --- |
| 13 — Email/password accounts (simple mode) | `no` | T-40 DONE |
| 14 — Owner dashboard of active receipts | `no` | T-34 DONE |
| 22 — Security audit trail | `no` | T-46 / PRODUCTION_READINESS "Audit trail" DONE |
| 23 — OpenAPI document and rate-limit headers | `no` | T-44 / T-26 DONE |

The parity tool reads the CSV and reports 63.0 with 11/11 must-haves, which matches the
frozen milestone record (T-93). Changing those cells would change the published parity
score. This pass did **not** touch them: flipping status to improve a score is exactly the
"invented parity" the clone rules forbid. Either (a) confirm the CSV is intentionally
conservative — the original's SSO/verification/paid audit trail are absent — and leave it,
or (b) explicitly authorize a parity correction with a re-run of `parity.py` and a matching
update to `TASKS.md`/`replica/parity.md`. Do not do (b) silently.

## Unverified by automation

- Live DNS name and public certificate chain (operator, T-70).
- Host-side Redis firewall rule on the real deployment host (operator, T-71).
- Clipboard copy button and axe-core accessibility assertions (gaps listed above).
- Visual parity with the original — no reference screenshots exist (K-22/K-30).
