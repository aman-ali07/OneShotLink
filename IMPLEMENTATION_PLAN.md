# Implementation plan — OneShotLink

Date: 2026-11-20. Status legend: `TODO`, `IN PROGRESS`, `DONE`. Every phase ends with a
verifiable command; no phase is called done on inspection alone.

## Phase 0 — Audit and comparison (DONE)

- `PROJECT_AUDIT.md`, `FEATURE_MATRIX.md`, this plan.
- Evidence: local inspection, 134 backend specs, public competitor pages.
- Constraint: clean-room + REA unavailable recorded in the audit.

## Phase 1 — Product: premium frontend in place (IN PROGRESS)

Goal: the same routes and API, a recognisably OneShotLink security product with layered
composition, deliberate type, trust affordances, and finished states. No UI kit, no copied
identity, no new runtime dependency.

| Step | Files | Acceptance |
| --- | --- | --- |
| 1.1 Shell and design language | `App.vue`, `AppHeader.vue`, `AppFooter.vue`, `styles.css`, `tokens.css` extension | Wider shell, refined masthead with brand mark, active nav, subtle grid/aurora ground, accessible focus, reduced-motion honoured. Contrast checked. |
| 1.2 Conceal experience | `ConcealView.vue` | Two-column desktop composition, trust panel, TTL chips, byte progress, clear passphrase guidance, polished result panel; same IDs (`#secret`, `#ttl`, `#passphrase`, `#result-heading`, `p.break-all`) and submit behaviour. |
| 1.3 Reveal experience | `RevealView.vue` | Strong one-time framing, passphrase and error states, revealed panel, terminal gone state; same IDs (`#reveal-heading`, `#revealed-heading`, `#gone-heading`, `#reveal-passphrase`, `pre`) and the single `[role=alert]` ordering used by e2e. |
| 1.4 Dashboard + auth screens | `DashboardView.vue`, `SignInView.vue`, `SignUpView.vue` | Summary strip, grouped receipts and settings, skeleton/empty states; exact e2e strings preserved (`Your account`, `#receipts-heading`, `Expires in`, `Sign out`, `Delete my account`, `#delete-password`). |
| 1.5 Landing site | `site/index.html`, `site/styles.css` | Premium narrative, product preview, proof strip, clear CTA; no third-party requests; privacy/terms unchanged. |
| 1.6 Verification | `npm --prefix frontend run build`, `npm --prefix frontend run test`, both `e2e` journeys, screenshots at 375/1280 | Green builds and journeys; screenshots reviewed for overflow and hierarchy; contrast script passes. |

## Phase 2 — Developer: SDK guide and examples (DONE)

- `docs/SDK.md`: config discovery, guest and authenticated flows, OpenAPI location,
  copy-paste curl/TypeScript/Python examples, error table with `request_id`, TTL semantics,
  rate limits and `Retry-After`, passphrase contract (8-byte floor, access gate, D-012),
  and the "GET previews, POST /reveal consumes" rule including the v1 exception.
- Three dependency-free examples under `examples/`: `curl/quickstart.sh` (curl + python3
  JSON), `typescript/quickstart.mjs` (Node 24 `fetch`), `python/quickstart.py` (urllib).
- Linked from `README.md`; stale `GET`-as-reveal examples in `README.md` and `API.md` fixed.
  The SPA footer link was left to the frontend owner to avoid concurrent edits.
- Verification (live Puma from current source, throwaway Redis, 2026-11-20): all three
  examples printed `ok: create=… preview=no-content reveal=match replay=404` with exit 0;
  passphrase flow returned `preview passphrase_required:true`, `passphrase_required`,
  `invalid_passphrase`, then the value on the correct passphrase. No new dependencies.

## Phase 3 — Security: visible assurance (IN PROGRESS)

- DONE: `docs/CRYPTO_SPEC.md` publishes the actual algorithms, parameters, record shape,
  single-use Lua, expiry semantics and explicit non-claims (no zero-knowledge, no
  cryptographic erasure from backups). Its verification commands were executed:
  `crypto_spec + store_spec + secrets_api_spec` → **37 examples, 0 failures**. Linked from
  README and the feature matrix; closes the "partial" crypto-spec row in documentation.
- TODO by the frontend owner (Phase 1): surface one-time/expiry/passphrase semantics as
  short, honest UI statements — no "zero-knowledge" claim (D-012).
- TODO after UI changes: re-run `SECURITY.md` checks, CSP/journey tests and the TLS rehearsal.
- Crypto and consume paths were not touched.

## Phase 4 — Deployment readiness (TODO)

- Re-run the full gate battery (specs, frontend, brand sweep, parity, image, journeys,
  load test, preflight self-test, audits) and refresh `docs/GO_LIVE_HANDOFF.md`.
- T-70/T-71 remain operator-owned; do not claim production ready without them.

## Explicitly out of scope this release

File secrets, incoming secret requests, webhooks, SSO/MFA/WebAuthn, client-side encryption,
i18n locales, read counts >1, custom domains. They stay `no`/`skip` in the feature matrix.

## Change discipline

- One concern per commit; tests before claims; protected paths (`web/app.rb`, crypto,
  password, session, compose, Dockerfile, config.ru, workflows, preflight) require approval.
- Update `TASKS.md` with new stable IDs, `CHANGELOG.md` for user-visible changes, and this
  plan as phases move. No deploy, key rotation or restore from an agent run.
