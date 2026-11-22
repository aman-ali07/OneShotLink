# OneShotLink product still (Stageshow)

An authored product illustration of the recipient experience: one thing happens — the link
is opened and the one-time value appears beside the open screen. It is **not** a screenshot
of the original service and copies no competitor identity; type, grid ground and the teal
accent come from OneShotLink's own design language.

Files:
- `index.tsx` / `card.css` — the stage, copied from the `static-card` gold structure and
  restyled with OneShotLink copy and tokens.
- `oneshotlink-wide.png` — 720×340 still for a hero beside copy.
- `oneshotlink-compact.png` — 358×300 redesign for a phone column (not a squeeze).

Verification (executed 2026-11-20 with the Stageshow kit):

```
node scripts/film.mjs "http://127.0.0.1:4258/?capture=oneshotlink&still=1" \
  --select '#example .ss-fit' --still --width 1000 --gate
# film: no-issues-detected; rehearsal passed

node scripts/film.mjs ... --width 390 --gate
# rehearsal passed (one near-tangent note, non-blocking)
```

To reproduce, copy `index.tsx` and `card.css` into
`<stageshow-kit>/examples/oneshotlink/`, run `npm run dev` in the kit, then run the film
commands above. The kit is a design toolchain, not an app dependency; nothing here is
imported by the Vue SPA or the static site.

## Frontend alignment-fix still (2026-11-22)

`frontend-alignment-fix.html` / `frontend-alignment-fix.png` is the `@stageshow` still coordinating
the layout-only frontend fixes: the eyebrow holds one line at 390px, the sidebar note shares the
card's left edge at 1440px, and terminal-state headings no longer draw a focus box while real
controls keep their focus ring. It reuses the exact tokens from `frontend-design.html`; **theme,
palette, type and spacing scale are unchanged**. Rendered 1030×560 with zero page errors, no
document overflow (`docWidth=1030`, `docHeight=560`). Verified in a local Vite dev server with
mocked API responses: eyebrow height 18px at 390px, `noteLeft === cardLeft === 968` at 1440px,
terminal heading `outlineStyle: none` while focused, and a keyboard-focused link still shows
`outlineStyle: solid`.

Code changes: `frontend/src/assets/styles.css`, `views/ConcealView.vue`, `views/RevealView.vue`,
`views/RequestView.vue`. Verification: Vitest, `vue-tsc --noEmit` and Vite build all exit 0.

## Developer-readiness still (2026-11-21)

`../developer-readiness.html` and `../developer-readiness.png` are the `@stageshow` still for
product-engineering coordination of the developer-experience pass: one cropped readiness board
(API contract, examples, containers, SDK plan) with one straddling evidence card that keeps the
honest status — operator gates unverified, public launch NO-GO, passphrase is not E2EE. Rendered
1030×560 with zero page errors. It illustrates `PROVIDER_COMPARISON.md`/`docs/SDK.md`, not a
deployed dashboard.

## Frontend integration still (2026-11-21)

`../frontend-integration-posture.html` and `../frontend-integration-posture.png` are the `@stageshow` still for
product-engineering coordination across the SPA surfaces: one cropped journey window
(create → share → preview/reveal → manage) with one straddling evidence card. Real words name
the four surfaces and the guarantees (config-driven, no-consume preview, status shown); filler
bars carry the rest. Rendered 1030×560 with zero page errors. It illustrates the connected
frontend, not a screenshot of a deployed app; the public launch verdict remains NO-GO.

## Fourth-pass security still (2026-11-21)

`../security-fourth-pass.html` and `../security-fourth-pass.png` are the `@stageshow` still for
coordinating this audit with product engineering: one cropped findings window (SA-46…SA-52) and
one straddling evidence card. The card keeps the honest status — 285 specs green, operator gates
still unverified, public launch NO-GO — and states **no E2EE / zero-knowledge claim** on its face.
Rendered 1030×560 with zero page errors. It illustrates `SECURITY_AUDIT.md §17`; it is not a
screenshot of a live dashboard.

## Zero-budget topology still (2026-11-21)

`../free-tier-topology.html` and `../free-tier-topology.png` are the `@stageshow` still for the
deployment-architecture conversation: one cropped topology window (Render, Upstash, GitHub
Actions, Cloudflare Pages) with one straddling evidence card that keeps the honest status —
"deployed gates: none verified" and "Public launch: NO-GO". Real words are limited to the four
services and the gate statuses; everything else is quiet structure and filler bars. It illustrates
`FREE_TIER_DEPLOYMENT_PLAN.md`; it is not a screenshot of a live stack.

**Refresh (2026-11-21):** the evidence card now carries the live re-verification date, the
"backend suite green · 34 Vitest · 8 journeys" gate (the backend count is moving during this
research pass, so no hard-coded number is printed), and the same NO-GO verdict. Re-rendered with
`google-chrome --headless --window-size=1030,560` → PNG `1030 x 560`; a `puppeteer-core` pass
reported `{"errors":[],"docWidth":1030,"docHeight":560}` and the four expected satellite lines.
The window still bleeds off the crop by design.

## QA automation acceptance still (2026-11-21)

`../qa-acceptance-posture.html` and its rendered `../qa-acceptance-posture.png` are the
`@stageshow` still used to coordinate product-level acceptance for the full-stack QA pass:
one cropped acceptance window (gate totals) with one straddling evidence card listing the five
defects fixed red→green — multi-byte passphrase handling, honest copy status, TTL-zero request
submissions, passphrase type validation, and immortal-backup refusal. The honest status is kept
on its face: **293 backend specs / 30 Vitest / 8 browser journeys / 40 a11y states, 0 violations**;
public launch remains **NO-GO** until the operator-owned TLS/hostname and Redis firewall gates
(T-70/T-71) have target-host evidence. Rendered at 1030×560 with zero page errors and no
document overflow; it illustrates `TEST_REPORT.md`, not a screenshot of a live dashboard.

## Independent security/performance audit still (2026-11-21)

`../security-perf-independent.html` and its rendered `../security-perf-independent.png` are the
`@stageshow` coordination still for the independent pre-release audit: one cropped gate window
(0 gem/production-npm advisories, 400/400 exactly-once reveals, 306 backend specs, 35 Vitest
tests — all green) with one straddling evidence card listing the fixes and dispositions — worker
lock, backup TTL, password ceiling, hot-path pipelines, protected-path proposals and the
documented Argon2id capacity ceiling. The honest status stays on its face: code-level **GO**,
public launch **NO-GO** until T-70/T-71 and protected-path approvals; passphrase is an access gate,
not end-to-end encryption. Rendered 1030×560 with zero page errors and no document overflow. It
illustrates `../SECURITY_AUDIT.md` §19 and `../PERFORMANCE.md` §8.

## Final QA acceptance still (2026-11-21)

`../qa-final-acceptance-posture.html` and its rendered `../qa-final-acceptance-posture.png`
are the `@stageshow` still used to coordinate the final full-stack QA pass with product
engineering: one cropped acceptance window (gate totals — 303 backend specs, 34 Vitest tests,
8 browser journeys, 40 a11y states, all green) with one straddling evidence card naming the six
fix classes closed red→green — immortal backup, error cache headers, v1 501 envelope, browser
false-passes, dark contrast and crypto edge cases. The honest status is kept on its face:
**code-level acceptance GO; public launch NO-GO** until T-70/T-71 have target-host evidence, and
the passphrase is an access gate, not end-to-end encryption. Rendered at 1030×560 with zero page
errors and no document overflow. It illustrates `../TEST_REPORT.md`, not a live dashboard.

## Pre-release security/performance still (2026-11-21)

`../security-perf-posture.html` and its rendered `../security-perf-posture.png` are the
`@stageshow` still coordinating the independent security + performance audit with product
engineering: one cropped gate window (303 backend specs, 34 Vitest tests, 8 browser journeys,
0 high/critical shipped-dependency advisories, ~2 measured passphrase reveals/s) and one
straddling evidence card naming the fixes landed red→green — oversized passphrase rejection,
a validated marketing CTA origin, TTL-less receipt/delivery backup refusal, no root `eval` in the
firewall helper, the metrics token off the argv, and a pipelined webhook hot path. The honest
status is on its face: **no E2EE claim**, dev-only advisories waived with evidence, public launch
**NO-GO** until T-70/T-71 are signed. Rendered 1030×560 with zero page errors and no overflow.

## Final release review still (2026-11-21)

`../final-release-review.html` and its rendered `../final-release-review.png` are the
`@stageshow` still for the final product-engineering review: one cropped gate window (307 backend
specs, 35 Vitest tests, 8 journeys with 0 axe violations, parity 80.8/100 with 11/11 must-haves —
all green) with one straddling evidence card — migration and restore drill passed, zero production
advisories, documentation corrected, and the blockers kept visible (T-70/T-71/K-46, commit/tag and
SA-61). Rendered 1030×560 with zero page errors and no overflow. It illustrates
`../RELEASE_CHECKLIST.md` §7; the verdict is **NO-GO** for public deployment.

## Open-source release readiness still (2026-11-21)

`../open-source-readiness.html` and its rendered `../open-source-readiness.png` are the
`@stageshow` still coordinating the public-release preparation: one cropped gate window (zero
secrets in tracked files, 307 backend specs, 35 Vitest tests, clean-tree build and non-root image
passing) with one straddling evidence card — deployment-script dependency install, OpenAPI
503/429 gaps closed red→green, documentation drift corrected, and the HIGH human actions
(untracked release sources and private vulnerability reporting) kept visible. Rendered 1030×560
with zero page errors and no overflow. It illustrates `../OPEN_SOURCE_READINESS.md`.

## Independent engineering-quality still (2026-11-21)

`../engineering-quality-independent.html` and its rendered `../engineering-quality-independent.png`
are the `@stageshow` still for the second, independent cleanup review: one cropped gate window
(306 backend specs, 35 Vitest tests, 8 e2e scripts parsing, 0 new dependencies — all green) with
one straddling evidence card naming the removals and consolidations — three duplicate `assert`
helpers, a DOM debug dump, a dead writer/temp dir, the key-length and TTL-validator single sources
of truth, a TTL-less delivery-key bug fix, and seven protected-path issues documented rather than
edited. Rendered 1030×560 with zero page errors and no overflow. It illustrates
`../ENGINEERING_REVIEW.md` §5, not a live dashboard.

## Open-source release still (2026-11-21)

`../open-source-readiness.html` and its rendered `../open-source-readiness.png` coordinate the
public-release preparation with product engineering: one cropped gate window (306 backend specs,
35 Vitest tests, 8 browser journeys, zero missing doc links or committed secrets) and one
straddling card naming the newly added contributor guide, code of conduct, issue/PR templates,
private security-reporting route and reconciled docs. The footer keeps the honest blocker on its
face — required sources are untracked, so a git checkout fails typecheck until a human stages and
commits them — plus **public launch NO-GO** until T-70/T-71 are signed. Rendered 1030×560 with zero
page errors and no overflow; it illustrates `OPEN_SOURCE_READINESS.md`, not a deployed product.

## Engineering-quality review still (2026-11-21)

`../engineering-quality-posture.html` and its rendered `../engineering-quality-posture.png`
coordinate the cleanup pass: one cropped gate window (306 backend specs, 35 Vitest tests, 8
browser journeys, 0 unused declared dependencies) and one straddling card naming the real
navigation bug fixed red→green plus the dead code, duplication, comment and doc drift removed.
The honest footer names the unresolved human actions — untracked CI-referenced journeys, the
duplicated protected CI step, and untriaged generated artifacts — and keeps public launch **NO-GO**
until T-70/T-71 are signed. Rendered 1030×560 with zero page errors and no overflow.

## Backend-gates coordination still (2026-11-21)

`../backend-gates-posture.html` and its rendered `../backend-gates-posture.png` are the
coordination still for the backend increment: one cropped reveal window (the value is shown
once, then the link is spent) with one straddling satellite listing the four gates that
landed — schema-version migrations, post-consume cleanup, correlated/dropped-audit
counting, and strict v2 metadata MAC — plus the 188/0 evidence gate. Real words are limited
to the outcome and the gates; everything else is filler bars at the edges. It copies no
competitor identity and uses OneShotLink's own teal accent and quiet grid ground.

Verification: rendered with `google-chrome --headless --window-size=1030,560` to a
1030×560 PNG; a puppeteer-core pass reported `{"errors":[]}` and no document-level horizontal
overflow (the window bleeds off the crop by design). It is an illustration for the
product-engineering conversation, not a screenshot of a live screen.

## Frontend wiring pass (2026-11-21)

`../frontend-wiring-pass.html` and its rendered `../frontend-wiring-pass.png` are the
cross-component coordination still for the six parallel frontend reviews: one cropped
receipts window showing the three owner-side lifecycle states (already viewed, destroyed by
you, waiting to be opened) and the Burn action, with one straddling evidence card listing the
integration gate — 28 frontend tests, five desktop journeys plus 20 phone-width checks, 261
backend specs green, no mock data or dead controls, and **Public launch: NO-GO (T-70/71)**.
Real words are limited to those outcomes; the rest is quiet rows and filler bars. It uses
OneShotLink's own teal accent and copies no competitor identity. Rendered at 1030×560 with
zero page errors, no satellite overflow and no wrapping status pills; it is an authored
illustration, not a screenshot of a live dashboard.

## Developer-readiness decisions (2026-11-21)

`../developer-readiness.html` and `../developer-readiness.png` are the `@stageshow` still for
the self-hosting/product conversation: one cropped "four developer surfaces, one contract"
window (OpenAPI contract, six verified examples, reproducible container, SDK plan) with one
straddling evidence card. The card carries the honest status — **285 backend specs, 28 Vitest
tests**, six SDK examples verified locally (not in CI), T-70/T-71 operator-owned, and
"passphrase is not E2EE"; **Public launch: NO-GO**. Rendered at 1030×560 with zero page
errors, no satellite overflow and no wrapped lines. The supporting decisions are one
authoritative rate-limit table, config-derived TTLs in examples, Compose service DNS in
`.env.example`, and protected-path edits (`app.rb`, `compose.yaml`, CI) left for human
approval.
