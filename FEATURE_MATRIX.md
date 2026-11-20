# Feature comparison matrix

Date: 2026-11-20. Evidence: local implementation + **public** product pages only.
Legend: **yes** implemented and verified · **partial** present but narrower · **no** missing ·
**deferred** deliberate out-of-scope for this release. Priorities: P0 (now), P1 (next), P2 (later).

Sources: [OneTime Secret](https://onetimesecret.com/), [Yopass](https://yopass.se/),
[Bitwarden Send](https://bitwarden.com/products/send/), [PrivateBin](https://privatebin.net/).
Privnote returned a Cloudflare 403 and Password Pusher timed out from this host; their rows
are marked "not verified" rather than guessed.

| Capability | OneShotLink | OneTime Secret | Yopass | Bitwarden Send | PrivateBin | Gap / priority |
| --- | --- | --- | --- | --- | --- | --- |
| Text secret, single-use link | yes | yes | yes | yes | yes | — |
| Atomic destruction on first view | yes (Lua CAS) | yes | yes | yes | yes | — |
| Configurable expiry | yes (allowlist) | yes | yes (1h/1d/1w) | yes | yes | — |
| Passphrase / access gate | yes (Argon2id, 8-byte floor) | yes | generated key in URL fragment | yes (password) | optional password | S-G2 client-side key deferred (D-012) |
| Client-side encryption | no | claimed | yes (OpenPGP in browser) | yes | yes | P2, opt-in only; never claim zero-knowledge |
| Encryption at rest | yes (AES-GCM, instance key) | yes | ciphertext only | yes | ciphertext only | — |
| Link preview does not consume | yes (GET = metadata) | not verified | not verified | not verified | not verified | Competitive advantage, keep |
| File secrets | no | yes (paid) | yes (≤1 MB free) | yes | yes | P2 |
| Branding / custom domain | no (brand fixed, clean-room) | yes (paid) | yes (paid) | partial | self-hosted theme | deliberately deferred |
| Secret request links (incoming) | no | yes (paid) | yes (paid) | no | no | P2 |
| Accounts + dashboard | yes (simple mode) | yes | OIDC (paid) | yes (Bitwarden account) | no | SSO/MFA deferred (D-003) |
| Audit trail / read receipts | yes (append-only events) | claimed | yes (paid) | enterprise | no | — |
| API / SDK | OpenAPI + REST + [docs/SDK.md](docs/SDK.md) and 3 runnable examples | API (public docs) | CLI + REST | CLI/API | API-ish | **D-G1 resolved (P1):** SDK guide plus curl/TypeScript/Python examples executed against a live stack; no SDK package is claimed |
| Webhooks | no | not verified | yes (paid) | not verified | no | P2 |
| Self-hosting / Docker | yes (non-root, Compose) | self-host option | yes (Go + Redis) | yes (vault) | yes | — |
| Open-source license | MIT | source available | Apache-2.0 | GPLv3 | AGPLv3 | — |
| Premium, distinctive frontend | **yes** (in-place OneShotLink redesign committed `5165921`; visual review at 375/1280 px, 11 Vitest, clean typecheck/build, both browser journeys green) | polished SaaS | functional | polished SaaS | utilitarian | P0 delivered; original UI not copied |
| Responsive + accessible | yes (375/768/1280, AA tokens) | yes | yes | yes | partial | preserve while redesigning |
| Documentation depth | strong ops docs + [SDK guide](docs/SDK.md) + [crypto spec](docs/CRYPTO_SPEC.md) | strong | strong | strong | FAQ | SDK guide and crypto spec shipped this pass; UI copy remains Phase 1 |
| Published crypto spec / verify-it-yourself | yes ([docs/CRYPTO_SPEC.md](docs/CRYPTO_SPEC.md), code-grounded, includes non-claims) | not verified | not verified | not verified | not verified | Resolves the `replica/features.csv` "partial" row in docs; no zero-knowledge claim |

## What this means for this pass

1. The core security and self-hosting story is already competitive; do **not** rewrite it.
2. The clearest deficit is product experience: the SPA works but does not feel like a
   considered security product. Redesign in place with the existing tokens and identity.
3. The second deficit is developer onboarding: add real, runnable API examples and an SDK
   guide instead of promising an SDK that does not exist.
4. Do not add fake parity: file secrets, SSO/MFA, client-side encryption and webhooks stay
   explicitly deferred until implemented.
