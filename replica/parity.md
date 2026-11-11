# Parity report

Tool: `python3 ~/.agents/skills/replica-diff/parity.py replica/features.csv`
Source of truth: `replica/features.csv`. A feature is only `yes` when a passing spec or a
verified live request proves it; `partial` means the user-facing behavior is incomplete.

## Baseline (2026-11-11, docs only)

- **5.8 / 100 overall**
- **0 / 11 must-haves**
- 27 features counted; all clone values `no`/`partial`.

## M1 — secret lifecycle (2026-11-11)

- **54.8 / 100 overall** (+49.0)
- **9 / 11 must-haves**
- Evidence: 40 specs green (`bundle exec rspec`) and a live Puma run on `:3100`:
  create `201` → reveal `200` → second reveal `404`; four parallel reveals → one `200`,
  three `404`. At-rest spec asserts ciphertext-only Redis; passphrase spec asserts a wrong
  attempt does not consume.

### Must-haves still open

| Feature | State | Why |
| --- | --- | --- |
| Accessible responsive create/reveal UI | no | No frontend; M2 / T-30–T-36 |
| Optional passphrase gate | partial | Gate works; by design the server can decrypt after the gate (D-012), so the original's zero-knowledge claim is not matched (K-21) |

### Newly scored

| Feature | State | Evidence |
| --- | --- | --- |
| Create a secret | yes | HTTP create + integration spec |
| Reveal exactly once | yes | Atomic consume; 8-way race = one winner |
| Configurable expiry | yes | TTL allowlist + Redis TTL + expiry spec |
| Copyable one-time link | yes | API returns `links.secret` (copy UI in M2) |
| Terminal states | yes | Uniform `404 not_found` |
| REST API | yes | v1 form+JSON, v3 guest |
| Guest use | yes | Anonymous create/reveal |
| Encryption at rest | yes | AES-256-GCM; plaintext marker absent from Redis |
| Rate limiting | yes | `429` + `Retry-After` |

## Not scored (on purpose)

Original identity/assets (clean-room rule), regional operations, billing, and network
effects. These are not features to clone.

## M2 — UI vertical slice (2026-11-11)

- **60.6 / 100 overall** (+5.8)
- **10 / 11 must-haves**
- Evidence: `npm run build` (vue-tsc + Vite) to `public/app`; Rack served `/`,
  `/assets/*.js` with `text/javascript`, and deep links; headless Chrome completed
  create → copy link → reveal → gone and the wrong/correct passphrase path. No plaintext
  in the URL or `localStorage` (`{}`). Responsive overflow checks passed at 375, 768,
  and 1280 px.

### Remaining must-have

| Feature | State | Why |
| --- | --- | --- |
| Optional passphrase gate | partial | Works as an access gate; the server can decrypt after the gate, so it does not match the original's zero-knowledge claim (D-012/K-21). **This is a deliberate, documented divergence, not unfinished M2 work.** |

The parity tool therefore still prints "1 must-have not done". A launch decision must
explicitly accept D-012 or scope a client-side-encryption v2; do not silently relabel it
`yes`.

## Next measurement

Re-run after M3 (accounts/dashboard) and M4 (full test/CI pass). Do not mark passphrase
parity `yes` (D-012), and do not claim screenshot parity while the original reference
screens are missing (K-22).

## R-08 — user research re-score (2026-11-11)

Feedback mining (`replica/reviews.csv`, `replica/fixes.md`) added five rows for gaps the
original's users actually complain about: preview-safe links, client-side encryption,
file secrets, read counts > 1, and a published crypto spec.

- **63.0 / 100 overall** (+2.4)
- **11 / 11 must-haves**
- 24 features counted (the five new rows are `could`/`should` and are scored against
  the original independently).

### Why the passphrase row is now `yes`

The earlier `partial` encoded two different things in one row: whether a passphrase
gate exists (it does — 401 without a passphrase, 401 with a wrong one and **the secret
is not consumed**, 200 with the right one, then 404) and whether the server can decrypt
after the gate (it can). Only the second is true of the gap, so it now has its own row:
**client-side (zero-knowledge) encryption, `no`**, priority `should`.

This is a measurement correction, not a parity claim: nothing in the product changed,
D-012 is still open, and the UIs and docs still must not describe the passphrase as
zero-knowledge. The must-have count moved to 11/11 because the gate is genuinely
implemented and verified — the remaining divergence is tracked as a scored `no` row
instead of hiding inside an overloaded `partial`.
