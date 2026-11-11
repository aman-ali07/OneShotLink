# Component specs

Status: **specs only — no UI exists yet** (M2 builds them). Roles and spacing come from
`tokens.json`; every value below must resolve to a token, never a raw hex/pixel in a
component. Screens refer to `replica/recon.md`.

Conventions: real `<button>`/`<label>`/`<input>` elements, visible focus ring
(`2px accent`, `2px` offset), disabled and loading states, `aria-live` for async
feedback, no `v-html` for user content.

## Button

```
variants  primary, secondary, ghost, danger
sizes     sm 32px, md 40px, lg 48px
states    default, hover, active, focus-visible, disabled, loading
tokens    bg accent, text on-accent, radius md, text sm/600; danger uses bg danger
a11y      real <button type>, visible focus, loading keeps the accessible label and sets aria-busy
used on   S02, S03, S04, S07, S08, S10
```

## Textarea (secret)

```
variants  default, invalid
sizes     min-height 8rem, resize-y
states    empty, filled, focused, error, disabled
tokens    bg surface, border border-input, text base, mono for content, radius md
a11y      <label for>, aria-describedby for counter/error; never store value outside component state
used on   S01, S02
```

## Input (passphrase / email / password)

```
variants  default, with reveal toggle (password only)
states    empty, filled, focus, error, disabled
tokens    bg surface, border border-input, radius md, text base
a11y      autocomplete correct (current-password/new-password/email), error linked, toggle has aria-pressed
used on   S04, S07, S08, S10
```

## Select (TTL)

```
variants  preset list
states    default, open, disabled, error
tokens    same as Input
a11y      native <select> for reliability; label is visible, not placeholder-only
used on   S02
```

## Callout / Alert

```
variants  info, success, danger
states    static; danger may be role="alert"
tokens    bg surface, border border, text; icon uses role colour
a11y      role="status" for success, role="alert" for errors; no colour-only meaning
used on   S02, S04, S05, S06
```

## One-time link result

```
parts     read-only link text (mono, break-all), Copy button, optional QR (could)
states    fresh, copied (aria-live), clipboard denied (manual-select hint)
tokens    surface card, border, radius md, shadow card
a11y      link is selectable; copy announces success; no plaintext secret in the link
used on   S03
```

## Secret display

```
parts     pre/mono block, Copy button, destroyed notice
states    visible, copied
tokens    mono sm, bg surface, border, radius md, overflow-wrap anywhere
a11y      not aria-hidden; copy announces; unmount clears the value
used on   S05
```

## Terminal state (gone/expired/unknown)

```
parts     heading, one-line explanation, "create a new secret" link
states    static
tokens    text, text-muted
a11y      page title changes; no error code or internal detail shown
used on   S06
```

## Header / Footer

```
parts     wordmark (clone's own, not the original's), nav, theme/lang (later)
states    signed-out, signed-in
tokens    bg bg, border-b border, header height 64px
a11y      skip link to main, nav landmark, current page aria-current
used on   all
```

## Confirm dialog

```
parts     title, body, cancel, destructive confirm
states    closed, open, busy
tokens    surface, shadow pop, radius lg
a11y      focus trap, Esc closes, focus returns to trigger; not used for the reveal warning (inline instead)
used on   S10 (delete account), later org removal
```

## Toast / inline feedback

```
variants  success, error
states    entering, visible, auto-dismiss, persistent (error)
tokens    surface, border, text sm
a11y      aria-live polite; errors never auto-dismiss before being readable
used on   S03, S05, S07
```
