# Implementation plan — OneShotLink

Date: 2026-11-20. Status legend: `TODO`, `IN PROGRESS`, `DONE`. Every phase ends with a
verifiable command; no phase is called done on inspection alone.

## Phase 0 — Audit and comparison (DONE)

- `PROJECT_AUDIT.md`, `FEATURE_MATRIX.md`, this plan.
- Evidence: local inspection, 138 backend specs, public competitor pages.
- Constraint: clean-room + REA unavailable recorded in the audit.

## Phase 1 — Product: premium frontend in place (DONE)

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

## Phase 3 — Security: visible assurance (DONE)

- DONE: `docs/CRYPTO_SPEC.md` publishes the actual algorithms, parameters, record shape,
  single-use Lua, expiry semantics and explicit non-claims (no zero-knowledge, no
  cryptographic erasure from backups). Its verification commands were executed:
  `crypto_spec + store_spec + secrets_api_spec` → **37 examples, 0 failures**. Linked from
  README and the feature matrix; closes the "partial" crypto-spec row in documentation.
- DONE by the frontend refresh: the conceal screen states "Encrypted at rest", "A preview
  cannot spend it" and "One view, then gone"; the passphrase panel says the server holds
  the encryption key and this is **not** client-side encryption. No zero-knowledge claim
  (D-012). Verified in the captured 1440/768/375 screenshots and by axe.
- DONE after UI changes: CSP/hardening-header assertions and the plain-HTTP redirect passed
  in `script/tls-rehearsal.sh --with-redis` (`PREFLIGHT PASSED (0 skipped)`, 9 assertions);
  both committed browser journeys passed with `errors: []`; brand sweep clean.
- Crypto and consume paths were not touched.

## Phase 4 — Deployment readiness (DONE, in-repo portion)

- Full gate battery re-run and recorded in `docs/GO_LIVE_HANDOFF.md`: 138 specs / 0 failures,
  12 Vitest, clean build, brand sweep clean, contrast 12/12 AA, parity 63.0 with 11/11
  must-haves, Compose config valid, image builds, both browser journeys green, load test
  100/100 revealed exactly once, TLS rehearsal `PREFLIGHT PASSED`, preflight self-test 5/5,
  bundler-audit and npm audit both 0 vulnerabilities.
- Independent browser QA on the shipped UI: Puppeteer + axe WCAG 2.2 AA on home, reveal and
  signup at 1440/768/375 → **21/21 checks**, 0 violations, 0 overflow, 0 console/5xx errors;
  two footer targets were found too small (`target-size`, 5 nodes) and fixed to `min-h-6`
  in `AppFooter.vue`, then re-verified clean. The redesigned static landing page also passed
  axe at 1440/375 after giving the code block and both scrollable tables `tabindex="0"`.
- T-70/T-71 remain operator-owned; do not claim production ready without them. This phase is
  "done" only for what can be proven from the repository.

## Phase 5 — File secrets (DONE)

- Backend: `ConcealSecret` accepts `kind: "file"`, strict base64 payload and a safe filename;
  512 KiB decoded ceiling; `app.rb` passes the filename and `/api/v3/config` publishes
  `max_file_bytes`. Reveal metadata already carried `kind`/`filename`, so no data-shape
  change was needed.
- Frontend: text/file mode on conceal, binary-safe base64 encoding, size feedback and a
  download button on reveal (browser-side decode).
- Verification: 4 red→green backend specs (138 total), 12 Vitest, both committed journeys
  plus a dedicated file journey, live curl, OpenAPI/API/SDK docs.
- Still honest: this is server-side encryption; a file secret is not zero-knowledge.

## Explicitly out of scope this release

Incoming secret requests, webhooks, SSO/MFA/WebAuthn, client-side encryption,
i18n locales, read counts >1, custom domains. They stay `no`/`skip` in the feature matrix.

## Change discipline

- One concern per commit; tests before claims; protected paths (`web/app.rb`, crypto,
  password, session, compose, Dockerfile, config.ru, workflows, preflight) require approval.
- Update `TASKS.md` with new stable IDs, `CHANGELOG.md` for user-visible changes, and this
  plan as phases move. No deploy, key rotation or restore from an agent run.
