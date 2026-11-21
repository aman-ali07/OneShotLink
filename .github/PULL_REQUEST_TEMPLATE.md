## Summary

<!-- What changed and why. One change per PR. -->

## Related

- TASKS.md ID: T-___ / K-___
- Closes #___
- `replica/features.csv` row updated? (yes / n/a)

## Type of change

- [ ] fix / feat / docs / test / refactor / chore / security
- [ ] Conventional commit style used (e.g. `fix: refuse oversized reveal passphrase (SA-53)`)

## Checklist

- [ ] Diff is minimal and matches the request; no drive-by edits.
- [ ] Read `AGENTS.md` and the relevant contract doc(s).
- [ ] No protected path touched without operator approval, or approval recorded here:
      `crypto.rb` / `password.rb` / `session.rb` / `web/app.rb` / `compose.yaml` / `Dockerfile` /
      `config.ru` / `config/puma.rb` / `.github/workflows/` / `script/preflight*.sh` /
      `auth|payments|secrets|credentials|*.pem|*.key`.
- [ ] `.env` / `.env.*` untouched; new vars documented in `.env.example` with placeholders.
- [ ] Tests added/updated; new behaviour was seen failing before the fix (or the gap is stated).
- [ ] Commands run and output pasted (below).
- [ ] Docs invalidated by the change updated: `API.md` / `DATABASE.md` / `SECURITY.md` /
      `CHANGELOG.md` / `TASKS.md` / `replica/features.csv` / `docs/DECISIONS.md` / `README.md`.
- [ ] No new gem or npm package without a `docs/DECISIONS.md` entry and a canonical check.
- [ ] No secret, passphrase, ciphertext, token or `.env` value in code, logs, fixtures, docs or this PR.
- [ ] Security invariants kept: atomic `Store.consume` unchanged; passphrase check and decryption
      still happen before consume; records remain JSON strings; no plaintext in Redis; API v1
      shape unchanged; `AUTH_MODE=full` still returns 501.
- [ ] `script/brand-sweep.sh` exits 0 for shipped-file changes.
- [ ] Draft PR opened; a human will mark ready and merge. Nothing deployed by me.

## Commands run (paste output)

```
bundle exec rspec   # or the exact Docker fallback from CONTRIBUTING.md
npm --prefix frontend run test / typecheck / build
docker build -t ots-prod . && SECRET=$(openssl rand -hex 32) docker compose config
```

## Remaining unverified

<!-- Name anything not run. Do not claim "production ready" while T-70/T-71 are open. -->
