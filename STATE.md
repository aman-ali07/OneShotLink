# Loop State — OneShotLink

Last run: never

## High Priority (loop is acting or waiting on human)

- **R-11 deploy is IN PROGRESS, not blocked on code** — blockers B1–B6 live in
  `replica/deploy.md` and `TASKS.md`: no account deletion (B1), legal pages written but
  no domain (B2), placeholder favicon / no OG image (B3), trademark screening unrun (B4),
  preflight not green on a real host (B5), host firewall rule unapplied (B6).
- **T-70 TLS termination and T-71 Redis host firewall** are operator infrastructure:
  they cannot be closed from the repository. Do not propose code for them.
  `HOST=https://<domain> script/preflight.sh` is the gate that proves them.

## Watch List

- Open `KNOWN_ISSUES.md` defects worth a small fix: K-35 (v3 `GET` consumes the secret,
  so a link preview or chat client burns it), K-12 (`Config` reads ENV lazily, so tests
  can leak config), K-15 (rejected requests still increment the limiter), K-17 (one Redis
  client, no pool/retry policy), K-10 (`OpenSSL.fixed_length_secure_compare` availability).
- Frontend coverage is one file (`frontend/src/lib/api.test.ts`); views are only covered
  by the two committed browser journeys in `e2e/`.
- `docs/loop`-style scaffolding does not exist here: this repo uses the loop-engineering
  kit (`LOOP.md`, `STATE.md`, `loop-budget.md`, `loop-run-log.md`, `gate.yaml`).

## Recent Noise (ignored this run)

- (none yet — first run not done)

---
Run log: `loop-run-log.md`
