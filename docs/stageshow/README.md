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
