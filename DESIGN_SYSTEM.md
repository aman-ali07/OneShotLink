# Design system

> **Status: applied by the M2 Vue SPA.** Canonical values live in
> [replica/design/tokens.json](replica/design/tokens.json) and `tokens.css`, imported by
> `frontend/src/assets/styles.css`; 12 contrast pairs pass AA. Primitives exist under
> `frontend/src/components/`. These rules govern further screens.

## 1. Principles

1. **The secret is the interface.** Conceal and reveal screens have one job each; no
   dashboards, upsells, or decoration compete with them.
2. **Say what will happen.** Before reveal: "This secret can only be viewed once." After:
   "It has been permanently deleted."
3. **Calm, not alarming.** Sensitive content deserves a quiet, high-contrast surface, not
   red warning banners everywhere. Reserve red for destructive/terminal states.
4. **No dark patterns.** No forced accounts, no "are you sure" mazes, no auto-copy of
   plaintext into the clipboard without a click.
5. **Accessible by default.** Keyboard-first, visible focus, AA contrast, no motion that
   blocks reading.

## 2. Layout

- Single centered column, `max-width: 42rem`, page padding `1rem` mobile / `2rem` desktop.
- Vertical rhythm: 8px base scale — 4, 8, 12, 16, 24, 32, 48, 64.
- Conceal view: title → secret textarea → options row (TTL, passphrase) → primary action →
  result panel (link + copy).
- Reveal view: title → warning → optional passphrase field → primary "Reveal secret"
  action → revealed content panel → destroyed state.
- Result panels appear in place; no modal for the link (modals are reserved for confirming
  reveal when a passphrase is set).

## 3. Tokens

Define as CSS custom properties (Tailwind 4 `@theme`). Canonical files:
`replica/design/tokens.json` and `replica/design/tokens.css`; the Vue app imports the
latter as `src/assets/styles.css` in M2. Check changes with
`~/.agents/skills/replica-design/contrast.py`.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `--color-bg` | `#fafaf9` | `#0c0a09` | Page background |
| `--color-surface` | `#ffffff` | `#1c1917` | Cards, inputs |
| `--color-text` | `#1c1917` | `#f5f5f4` | Primary text |
| `--color-muted` | `#57534e` | `#a8a29e` | Secondary text |
| `--color-border` | `#e7e5e4` | `#292524` | Dividers, input borders |
| `--color-accent` | `#0f766e` | `#2dd4bf` | Primary action, links |
| `--color-on-accent` | `#ffffff` | `#042f2e` | Text on accent |
| `--color-danger` | `#b91c1c` | `#f87171` | Errors, destructive confirmation |
| `--color-success` | `#15803d` | `#4ade80` | Copied/revealed confirmation |

No additional colors without a contrast check. Dark mode follows
`prefers-color-scheme`; no manual toggle in v1.

## 4. Typography

- UI: system stack — `ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif`.
- Secrets and keys: `ui-monospace, "SFMono-Regular", Menlo, monospace`, `text-sm`,
  `break-all`, selectable.
- Scale: `text-3xl` page title (semibold), `text-base` body, `text-sm` help text,
  `text-xs` metadata. Line height 1.5 body, 1.75 for secret text.
- Never justify text; never letter-space body copy.

## 5. Components (shared)

`src/components/`:

- `base/`: `AppButton` (primary/secondary/danger, loading + disabled), `AppInput`,
  `AppTextarea`, `AppSelect`, `AppAlert` (info/success/danger), `AppSpinner`,
  `CopyButton`.
- `forms/`: `SecretForm`, `PassphraseField`, `TtlSelect`.
- `layout/`: `AppHeader`, `AppFooter`, `PageShell`.

Rules:

- Buttons show loading state and are disabled while a request is in flight; never allow
  double submit of conceal/reveal.
- Errors render in `role="alert"`; success/copy feedback uses `aria-live="polite"`.
- Icons are inline SVG with `aria-hidden="true"` unless they carry meaning.
- Focus ring: 2px accent outline with 2px offset; never remove focus styles.

## 6. Security UX

- Never place plaintext in the URL, query string, `localStorage`, or `sessionStorage`.
- Secret content lives in component state only; clear it on unmount, on "hide", and after
  a successful copy timeout.
- The reveal page requires an explicit click; never auto-reveal on page load.
- Warn once, in plain language, that reveal is irreversible. Do not require typing a
  phrase to confirm.
- "Copy link" and "Copy secret" are separate actions; both announce success via
  `aria-live`.
- If the passphrase is wrong, keep the field and show an inline error; do not navigate
  away or clear the form.
- After a successful reveal, replace the action area with a terminal state: "This secret
  has been viewed and deleted. Ask the sender for a new link." No "view again" button.

## 7. Responsive rules

- One column at all widths; options collapse to stacked fields below `640px`.
- Touch targets ≥ 44×44px.
- Long unbroken secrets wrap (`overflow-wrap: anywhere`); the page must never scroll
  horizontally.
- Test at 320px, 768px, and 1280px widths.

## 8. Accessibility checklist

- [ ] Keyboard-only path: conceal → copy link; reveal → read → done.
- [ ] Labels are real `<label for>` elements; placeholders are not labels.
- [ ] Error text is programmatically associated (`aria-describedby`).
- [ ] Contrast ≥ 4.5:1 for body text, ≥ 3:1 for large text and UI borders.
- [ ] No looping animation; honor `prefers-reduced-motion`.
- [ ] Page `<title>` changes per view; `lang` set on `<html>`.
- [ ] Screen reader announces the reveal outcome and the destroyed state.

## 9. Copy (microcopy) rules

- Sentence case, second person, no exclamation marks.
- "Create a secret link", "Copy link", "Reveal secret", "This link can only be used once."
- Avoid "burn", "self-destruct", "military-grade" in user-facing copy; use "delete" and
  "one-time".
- Error copy says what to do next, never echoes input.

## 10. Out of scope

- Marketing site, illustrations, custom fonts, animation library, component library
  dependency. Tailwind utilities only; no UI kit.
