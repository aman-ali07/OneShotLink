# Design system

> **Status: applied by the Vue SPA and the static site (2026-11-21).** Canonical values live in
> [replica/design/tokens.json](replica/design/tokens.json) and `tokens.css`, imported by
> `frontend/src/assets/styles.css`. The 12 declared light contrast pairs pass AA (verified with
> `python3 ~/.agents/skills/replica-design/contrast.py replica/design/tokens.json`).
> This document describes what ships; where an older note disagreed with code, code won.

## 1. Principles

1. **The secret is the interface.** Conceal and reveal screens have one job each; no dashboard, upsell, or decoration competes with them.
2. **Say what will happen.** Before reveal: "If this link is still valid, you can open it once." After: "Permanently deleted on the server."
3. **Calm, not alarming.** Quiet, high-contrast surfaces. Amber warns; red is reserved for destructive/error states.
4. **No dark patterns.** No forced accounts, no "are you sure" mazes, no auto-copy of plaintext, no dead-end CTAs on an instance where accounts are off.
5. **Accessible by default.** Keyboard-first, visible focus, AA contrast, 44px hit areas, no motion that blocks reading.

## 2. Layout

- App shell: `max-w-6xl` centered, `px-4 sm:px-6`, `py-8 lg:py-14`, on the warm ground (`App.vue:15`).
- Content panels: `max-w-3xl` compose/open, `max-w-2xl` responder, one column on mobile; two columns at `lg` where they carry distinct roles (`ConcealView`, `RevealView`, `RequestView`).
- Rhythm: 8px base scale with named aliases for steps already in use (`--ots-space-5/7/9/10/14`); prefer `6/8` (24/32px) for new panels so the scale can converge.
- Panel body padding: `--ots-panel-pad` (24px); inset sub-panels keep 16–20px.
- Terminal states replace the action area in place; no modal for the link or for reveal.

## 3. Tokens

Colour roles and the 12 contrast pairs live in `tokens.json`; the full type scale, spacing and component aliases live in `tokens.css` and its Tailwind 4 `@theme` block. CSS names are `--ots-*`. `tokens.json` is **colour-only** — its `type` map is historical and not the shipped scale. Palette: warm paper `--ots-bg: #fafaf9`, `--ots-surface: #ffffff`, quiet borders, `--ots-text: #1c1917`, `--ots-text-muted: #57534e`, teal `--ots-accent: #0f766e`, `--ots-on-accent: #ffffff`, `--ots-warning: #b45309`, `--ots-danger: #b91c1c`, `--ots-success: #15803d`. Semantic additions: `--ots-on-danger`, `--ots-accent-hover`, `--ots-danger-hover`, and `--ots-*-tint` for alert backgrounds.

**Dark mode ships in the SPA via `@media (prefers-color-scheme: dark)`** in `tokens.css`; `styles.css` sets
`color-scheme: light dark`. The static marketing site stays light-only by design (`site/styles.css`). There is no manual toggle. Derived grid/bloom/tints use `color-mix`
and adapt automatically. The dark palette was checked with the canonical tool: **12 pairs,
0 failing AA** (`contrast.py` on the dark token set; lowest normal-text pair 6.32:1, border-input
7.83:1). No new colour without a contrast pass.

Shared brand ground: `--ots-grid-size` (48px), `--ots-grid-line`, `--ots-bloom`; the marketing preview uses the same variables where reachable. Component rules live in `@layer components` so utilities can override them.

## 4. Typography

- System stack only (`--ots-font-sans`, `--ots-font-mono`); no webfont, no CDN, zero third-party requests.
- Named scale in `tokens.css`/`@theme`: `--ots-text-2xs … --ots-text-display`. `--ots-text-xs` (13px) is metadata only; help text uses `--ots-text-help` (14px, `--ots-text-sm`).
- **Heading hierarchy (shipped):** task titles use `.ots-title` (`text-3xl sm:text-4xl` bold);
  result and terminal states step down to `.ots-title-compact` (`text-2xl` semibold); section
  headings are `text-xl` semibold. `tokens.json` now mirrors the CSS type scale exactly.
  Body `text-base`; secrets and keys mono, `break-all`, line-height 1.75.
- Eyebrows: `--ots-eyebrow-size` (12px), `--ots-eyebrow-tracking` (0.12em), uppercase, accent.
- Never justify text; never letter-space body copy.

## 5. Components

Shipped primitives: `AppButton` (primary/secondary/ghost/danger, loading + disabled, shade hovers), `AppAlert` (`role=alert` for danger, `role=status` otherwise), `CopyButton` (Clipboard API + DOM fallback, `role=status` feedback), `AppHeader`, `AppFooter`.

Rules:

- Every interactive control has a hit area of at least `--ots-target-min` (44px); visual height may be smaller.
- Buttons disable while a request is in flight; no double submit of conceal/reveal.
- Errors render in `role="alert"`; success/copy feedback uses `aria-live="polite"` or `role="status"`.
- Icons are inline SVG with `aria-hidden="true"` unless they carry meaning. The header mark is the two-half chain from `site/favicon.svg`, split at the seam — a link waiting to be completed. There is no read/unread state switch.
- Focus ring: 2px accent outline with 2px offset, never removed.
- Panels use `--ots-radius-lg` + `--ots-shadow-card`; insets use `--ots-radius-md` with no shadow. Elevation belongs to panels, not chrome.

Primitives promised by older docs but not implemented (`AppInput`, `AppTextarea`, `AppSelect`, `PageShell`, `PassphraseField`, `TtlSelect`) remain deliberately unbuilt — add one only when ≥2 real call sites justify it (AGENTS rule 2).

## 6. Security UX

- Never place plaintext in the URL, query string, `localStorage`, or `sessionStorage`; the suite asserts empty storage after create and reveal.
- Secret content lives in component state, is cleared after submit, and can be dismissed with **Hide secret** on the reveal screen.
- The reveal page requires an explicit click; no auto-reveal on mount. The pre-click copy is neutral — a link may already be spent.
- One warning in plain language; no typing-to-confirm.
- "Copy link" and "Copy secret" are separate actions with announced success.
- A wrong passphrase keeps the field but clears the wrong value so one retry is a single type.
- After reveal, the action area is replaced by a terminal state. Ask the sender for a new link; no "view again".
- Account entry points disappear when `AUTH_MODE=disabled`; the dashboard explains that sharing needs no account instead of offering a 403 sign-in.

## 7. Responsive rules

- One column below `lg`; options stack below `640px`; two-column `lg` layouts only where roles differ.
- Touch targets ≥44×44px (`--ots-target-min`).
- Long unbroken secrets and keys wrap (`break-all` / `overflow-wrap: anywhere`); no horizontal scroll.
- Verify at 320, 375, 768, and 1280px.

## 8. Accessibility checklist

- [x] Skip link to `<main id="main" tabindex="-1">`.
- [x] Semantic landmarks; one `<h1>` per view; real `<label for>`.
- [x] Per-route `<title>` via router metadata + `afterEach` (WCAG 2.4.2).
- [x] Focus moved to the terminal heading on gone/sent/taken/revealed states.
- [x] `role="alert"` for errors; `role="status"` / `aria-live="polite"` for success and copy.
- [x] Global `:focus-visible` ring; `prefers-reduced-motion` honoured.
- [x] 12 contrast pairs pass AA (light) and 12 pass AA (dark); placeholder uses full `--ots-text-muted`.
- [x] Error alerts are wired to their fields with `aria-describedby` (reveal passphrase,
      sign-in, sign-up, incoming-request answer).
- [x] Browser-verified at 320/768/1280px (no horizontal scroll), keyboard skip link and
      `prefers-color-scheme: dark` — see the evidence ledger in §11.
- [x] Automated `axe-core` WCAG 2.2 AA gate in CI (`e2e/a11y.mjs`, D-016) — 40 states across 320/375/768/1280px including 7 dark-theme states, 0 violations; negative control detects an injected `image-alt` violation.
- [x] Component, formatter and view tests (Vitest + jsdom + `@vue/test-utils`, D-016) — 30 tests total.
- [ ] Runtime verification of keyboard-only paths, 320px/400% reflow, and real screen-reader announcements.

## 9. Copy rules

Sentence case, second person, no exclamation marks. "Create a secret link", "Copy link", "Reveal secret", "This link can only be used once." Avoid "burn", "self-destruct", "military-grade" in user-facing copy. Errors say what to do next, never echo input. Never claim zero-knowledge or that the server cannot decrypt (D-012) — the passphrase is an extra access check.

## 10. Out of scope

Custom fonts, a manual dark-mode toggle, an animation library, a component library dependency, and client-side encryption. Dark mode ships automatically via `prefers-color-scheme` (§3) — it is not out of scope. Tailwind utilities plus the token layer only; no UI kit and no copied competitor identity.

## 11. Frontend evolution pass — 2026-11-21

Four parallel reviewers (UX, visual design, accessibility, frontend architecture) audited the
existing SPA. Fixes implemented in this pass, all inside the existing identity and stack:

- **Tokens:** dark palette implemented; `/ots-inset` input border moved from decorative
  `--ots-border` (~1.26:1) to `--ots-border-input` (4.59:1 light / 7.83:1 dark) for WCAG 1.4.11;
  placeholder opacity removed from the secret textarea (was ~3.6:1).
- **Navigation / state:** per-route `<title>`, focus moved to terminal headings (gone/sent/taken),
  `<main tabindex="-1">`, Account link gated by `accountsEnabled()` in both header and footer,
  account-disabled dashboard gets a usable "Create a link" path instead of a dead end, and a
  non-401 load failure renders a retry panel instead of a blank page.
- **Copy:** one `src/lib/clipboard.ts` path with a real fallback on API rejection; dashboard
  actions now use `CopyButton` (aria-live feedback) instead of bare clipboard calls.
- **Trust:** marketing hero links directly to the working app, "Questions" stays reachable on
  mobile, and the stale spec count is 180.
- **Secrecy hygiene:** revealed plaintext is cleared on unmount as well as on Hide.

Verification: `npm --prefix frontend run test` → 12/12; `vue-tsc --noEmit` clean; Vite build
succeeds (242.57 kB JS / 22.13 kB CSS); `git diff --check` clean; `script/brand-sweep.sh` clean;
dark token set passes 12/12 contrast pairs. No competitor UI or assets copied. Product-design
still: `docs/frontend-design.html` + `.png` (1030×560, rendered from the real tokens).

## 12. Second frontend audit pass — 2026-11-21

Four parallel reviewers (UX, visual design, accessibility, frontend architecture) audited the
current SPA and static site. Fixes implemented in the working tree, all inside the existing
warm-paper/teal identity and with **no new dependency and no E2E selector renamed**:

- **HIGH — dev-server exposure:** `vite.config.ts` `fs.allow` narrowed from `[".."]` (whole repo
  root, including git-ignored `.env` with `SECRET`) to the frontend directory plus
  `replica/design` only — the sole CSS import that needs it.
- **Accessibility:** SPA route changes now move focus to `<main tabindex="-1">` (`router.ts`);
  the inbound-request error terminal state focuses its heading (`RequestView.vue`); a cached
  `format.ts` replaces four divergent `ttlLabel`/`sizeLabel` copies with 3 unit tests.
- **Hit areas and text:** one global rule gives text inputs/selects/textareas a 44px hit area
  and restores full-muted placeholder contrast; `<pre>` gets 1.75 line-height and `break-all`.
- **Visual consistency:** title scale unified into `.ots-title` / `.ots-title-compact`; the
  byte meter now turns red when actually over the limit instead of clamping to amber; auth and
  dashboard controls reuse `.ots-inset`; the request TTL comes from `/api/v3/config`.
- **Trust:** the Account link no longer flashes on auth-disabled instances; "Active links" is
  relabelled "Links created"; the empty-receipts state links home; reveal copy says "Ask the
  sender for a new link" and no longer claims a browser preview was observed; pricing columns
  are badged "Planned".
- **Secrecy hygiene:** `RequestView` clears the submitted answer and `DashboardView` clears
  revealed answers, signing secrets and passwords on unmount.
- **Static site:** header wraps at 320px, global focus ring, `color-scheme: light`, and a
  `.planned` badge for unshipped tiers.

Verification this pass: `npm --prefix frontend test` → **15/15** (2 files); `vue-tsc --noEmit`
clean; Vite build clean (243.19 kB JS / 22.72 kB CSS); contrast tool **12 pairs, 0 failing AA**;
`script/brand-sweep.sh` Clean; `git diff --check` clean. All committed E2E selectors verified
present. Dark mode remains SPA-only; custom fonts, a manual dark toggle, animation libraries,
component-library dependencies and client-side encryption remain out of scope.

## 13. Third frontend pass — verification ledger

Closed the remaining reviewer findings with repository and browser evidence:

- **Type scale reconciled:** `tokens.json` now matches the CSS scale (11/13/14/16/18/20/24/30/36/40px);
  heading hierarchy is `.ots-title` (task) vs `.ots-title-compact` (result/terminal).
- **Error association:** `AppAlert` accepts an `id`; the reveal passphrase, sign-in, sign-up and
  incoming-request answer fields now point at their error alerts via `aria-describedby`.
- **No data loss on tab switch:** `ConcealView` keeps a text draft; file encoding shows a
  `role="status"` "Reading file…" indicator.
- **Shared config:** `src/lib/config.ts` caches `/api/v3/config`; the dashboard request TTL is
  sourced from it instead of a hardcoded array. `authMode.ts` treats `full` as disabled (501).
- **Helpers tested:** `src/lib/format.ts` has 3 Vitest cases (TTL, sub-KB sizes, timestamp zone).

Executed evidence:
```
npm --prefix frontend run test       → Test Files 2 passed; Tests 15 passed
npm --prefix frontend run typecheck  → vue-tsc --noEmit clean
npm --prefix frontend run build      → ✓ built (243.41 kB JS / 22.72 kB CSS)
Puppeteer 320 / 768 / 1280px         → scrollWidth == innerWidth at all three;
                                       one h1 with class "ots-title"; route title set
Puppeteer keyboard                   → first focusable "Skip to content"; Enter → hash #main, focus MAIN
Puppeteer prefers-color-scheme dark  → --ots-bg #0c0a09, --ots-accent #2dd4bf, color-scheme "light dark"
stageshow film --gate (1030px)       → rehearsal passed
stageshow film --gate (390px)        → rehearsal passed
contrast.py light + dark             → 12 pairs, 0 failing AA (both)
```
Screenshots: `docs/responsive-{320,768,1280}.png`, `docs/responsive-dark-1280.png`,
`docs/frontend-design{,-gate,-compact-gate}.png`. Static marketing remains light-only; dark mode
ships in the SPA, and no manual toggle, webfont, animation library or UI kit was added.
