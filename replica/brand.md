# Brand — R-09

Status: **name chosen, palette verified, voice written, codebase swept clean of the
original's name.** Trademark and app-store screening are **not** done — see §2. Nothing
here claims legal clearance, zero-knowledge encryption (D-012), or production readiness.

Angle this brand has to carry (from `replica/fixes.md`): **self-host first, honest crypto
copy.** The original's loudest complaint is distrust of a third-party host, so the name and
copy stay concrete about what the server can and cannot do.

## 1. The name

**OneShotLink** — descriptive-compound. It says the mechanism (one shot, one link) and the
verb the product exists for (share a link, not "manage secrets"). It is the name the
GitHub repository already carries, so no rename churn on the remote.

Candidates considered (20 generated, cut to 5 by the skill's filters: not confusingly
similar to the original in sound/look/meaning, short and spellable after hearing it once,
no awkward meaning in a big language, and not fighting the self-host angle):

| Candidate | Style | Why it was cut / kept |
| --- | --- | --- |
| **OneShotLink** | descriptive compound | **Kept.** Says the mechanism; no shared sound or letterform trick with the original; already the repo name. |
| Burnnote | metaphor | Cut: "burn after reading" implies the sender keeps no record, which is stronger than what the product does. |
| Sable | invented/metaphor | Cut: no meaning transfer; collides with existing products in unrelated categories. |
| Sliponce | invented compound | Cut: reads as a typo of "slip once"; poor spell-after-hearing. |
| Veilcast | metaphor | Cut: implies end-to-end secrecy we do not implement (D-012), i.e. it would lie about the crypto. |

Rejected deliberately: any pun on "onetime", any `-ly` twin of a competitor, and every
metaphor (veil, vault, cloak, zero) that implies the server cannot read the secret. That
last rule is the D-012 constraint expressed as naming policy.

## 2. The checks — run vs. to run

Run on **2026-11-12** from this machine (2026-11-11 rows below were re-verified today):

| Check | Method | Result |
| --- | --- | --- |
| `oneshotlink.com/.net/.app/.dev/.link` | RDAP via rdap.org (follows to each registry) | `404` "Not Found" from each registry — consistent with unregistered; confirm at a registrar before paying |
| `oneshotlink.io` | RDAP: the `.io` registry publishes no RDAP service (`errorCode 404`); local DNS | `NXDOMAIN` — consistent with unregistered; confirm at a registrar before paying |
| all six domains | local DNS resolution (`getent hosts`) | `NXDOMAIN` for every one (a live registration would resolve) |
| npm package | `registry.npmjs.org/oneshotlink` | `404` — unregistered |
| PyPI package | `pypi.org/pypi/oneshotlink/json` | `404` — unregistered |
| RubyGems | `rubygems.org/api/v1/gems/oneshotlink.json` | `404` — unregistered |
| GitHub handle | `api.github.com/users/oneshotlink`, `/orgs/oneshotlink` | `404` — no user or org holds it |
| Apple App Store (US) | iTunes Search API `term=OneShotLink&entity=software` | 5 fuzzy results (Flickr, Hunch, Uhale, SayHi, Frameo) — **no exact match named OneShotLink** |
| Google Play (US) | headless Chrome on the Play Store search | **"No results for OneShotLink"** |
| USPTO wordmark | headless Chrome on `tmsearch.uspto.gov`, typed query, **control = `verizon` → 177 results** | **"No results found" for `oneshotlink`** — the wordmark search returns no marks. (The filter sidebar showed live/registered/dead counts at 0 on the first load; the exact "no results" verdict is from the controlled run.) |

**Still to run — no result is claimed for any of these, and the blocker is named:**

- **Adjacent US marks** (`oneshot`, `one-shot`, `one shot link` in classes 9/42): not run.
  After the `oneshotlink` query, `tmsearch.uspto.gov` stopped serving its search box to
  automated requests (rate-limit/bot wall), so a human should run these in a browser.
- **EU (EUIPO eSearch / TMview):** TMview rejects requests ("Request Rejected" WAF page);
  EUIPO eSearch is a JS app that needs a session. Not claimed.
- **WIPO Global Brand Database:** behind an `altcha` CAPTCHA; not claimed.
- **Canada (ISED):** JS-only trademark search; not attempted from this machine.
- **Handles on X, Instagram, TikTok, YouTube, Reddit:** unconfirmed — login walls and `403`
  from this machine; check in a browser. GitHub is the one handle that is freely checkable
  and is free (`404`).
- **Open web search for `OneShotLink` plus the category:** the web-search tool failed again
  this session (3 attempts, provider error), so the existence/conflict sweep is still unrun.

These are screening checks, not clearance. Before spending money on the name, a trademark
lawyer should run a proper search. **The `scripts/preflight` go-live gate does not check
this**, so it is an operator decision recorded here, not an automated one.

## 3. Palette

Roles unchanged from `replica/design/tokens.json` (replica-design owns the role names).
The accent is **deep teal `#0f766e`** — a different hue family from the original's
blue-violet public identity, so no confusion in a screenshot comparison and no borrowed
colour pair. Neutrals stay warm stone, which reads calmer than the usual cool grey for a
page whose job is "paste the thing you do not want to leak".

The original's brand hexes are deliberately absent from `brand.json`: we never sampled
them, because reading their CSS or bundles is prohibited by the clean-room rule. The
palette was authored from the token roles and then measured:

```bash
python3 ~/.agents/skills/replica-design/contrast.py replica/design/tokens.json
# 12 pairs, 0 failing AA  (accent on bg 5.24:1, on-accent on accent 5.47:1, text 16.74:1)
```

Zero AA failures is the gate; it passes as of 2026-11-11.

## 4. Logo brief

For whoever draws it — the user, a designer, or an image model.

- **Idea in one line:** a link (chain) that is whole while it is unread and breaks cleanly
  the moment it is used — one open stroke entering, one leaving, the break at the seam.
- **Mark type:** symbol plus wordmark. Wordmark set in the existing UI sans at semibold,
  tight tracking, `#1c1917` on light; the symbol is the single-stroke chain break in
  `#0f766e`.
- **Monogram fallback:** `1SL` is too dense at 16px — use the symbol alone for the favicon
  rather than a letter trio.
- **Must work at** 16px (favicon, one mark, no fine detail) and 1024px (app icon).
- **Deliverables:** SVG (single path per colour), app icon 1024×1024 with **no
  transparency** for iOS, favicon set (16/32/180/512), social image 1200×630 with the
  tagline "Share a secret once."
- **Must not resemble the original's mark:** no shared shape, no shared colour pair, no
  letterform trick. If a draft could be mistaken for the original's logo at 32px, redo it.

## 5. Voice

Three words: **plain, careful, unhurried.**

- *Plain*, not blunt — no jargon, no "military-grade", and no softening a real limit.
- *Careful*, not anxious — state the risk once, then let the user act; no red banners.
- *Unhurried*, not slow — short sentences, no urgency theatre, no countdown pressure.

| Do | Don't |
| --- | --- |
| Say exactly what is stored and for how long. | Say "military-grade", "zero-knowledge", or "unbreakable". |
| Name the thing: link, passphrase, expiry. | Call it a vault, a package, a drop, a capsule. |
| Tell the user what to do next. | Tell the user how to feel ("don't worry!"). |
| Keep the passphrase warning factual: sent separately. | Imply the passphrase makes the secret unreadable to the server (D-012). |
| Own the empty state ("already viewed, expired, or never existed"). | Explain the security logic at length in the UI. |

### The ten most-seen strings, rewritten

All fresh; none reuses the original's phrasing. Files are the ones changed in the sweep
commit.

| # | Where | String |
| --- | --- | --- |
| 1 | `AppHeader.vue` | **OneShotLink** |
| 2 | `index.html` `<title>` | **OneShotLink — share a secret once** |
| 3 | `ConcealView.vue` hero h1 | **Share a secret once** |
| 4 | `ConcealView.vue` hero sub | The recipient opens the link once. After that the secret is gone from the server. |
| 5 | `ConcealView.vue` primary button | **Create the link** (was "Create one-time link") |
| 6 | `ConcealView.vue` result h1 | **Your link, ready to send** |
| 7 | `ConcealView.vue` success alert | Stored encrypted. Deleted after one view, or automatically after {ttl}. |
| 8 | `RevealView.vue` intro sub | It can be opened once. Opening it deletes it. |
| 9 | `RevealView.vue` gone sub | It was already opened, it expired, or it never existed. The server does not say which. |
| 10 | `AppFooter.vue` | Encrypted at rest. Deleted after one view or on expiry. |

Unchanged on purpose: form labels (`Secret`, `Expires after`, `Passphrase`), the passphrase
helper "Share it separately from the link.", and the account screens' headings. Those are
functional microcopy with no brand voice to gain, and churning them would be noise.

## 6. Sweep

```bash
python3 ~/.agents/skills/replica-brand/sweep.py . --config replica/brand.json
```

Clean as of the R-09 commit (verified: `sweep.py --config replica/brand.json` printed
"Clean. Nothing of the original's name, domain or colours found." and exited `0`; the
baseline before the pass was 19 hits — 18 name, 1 domain): the original's name and domain
are gone from the codebase, package names, compose project, CI image tag, preflight
defaults and the user-visible copy.
`replica/` is skipped by the tool because that is where the original's name belongs — the
recon record must keep saying who was cloned.

Two references survive on purpose and neither is a hit:

- The Ruby module namespace stays `Onetime` and Redis keys keep the `ots:` prefix. They are
  internal identifiers, not shipped brand, and the sweep matches only the full name.
- `lib/onetime/crypto.rb` derives keys with `info: "ots-secret"` and a per-record random
  salt, so the brand does not appear in any stored record. K-23 previously claimed a
  `"onetimesecret/v1"` HKDF salt was still in the code; that is stale and was corrected in
  `KNOWN_ISSUES.md` during this task.

Drawn 2026-11-12 from this brief (B3): the mark is `site/favicon.svg`, one stroke, one
colour, two open ends at the seam; `site/app-icon.svg` is the opaque 72%-inset tile. The
full set is generated by `script/build-assets.sh`: favicon 16/32, `apple-touch-icon.png`
180, `icon-512.png`, opaque `app-icon-1024.png`, and the 1200×630 `og.png` card built from
`site/og-card.html`. Verified at 16px (pixel map shows both seam gaps hold) and 512px.

Not done, and not claimed: the GitHub repository description/topics and the remote name are
unchanged, no domain has been registered, and the mark has not been screened against the
original's (B4 — see §2 "to run").

Next: `/replica-launch` (R-10). Landing copy must not imply zero-knowledge (D-012) or
"production ready" while the host gates are open.
