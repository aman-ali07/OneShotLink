# Landing page — OneShotLink

Copy and structure for the landing page, in the brand voice (`replica/brand.md` §5:
plain, careful, unhurried). Built from the recommended angle in `replica/fixes.md` §5:
**self-host first + honest crypto copy**, with the no-account strength folded into the hero.

Two hard rules for every line below:

- **No zero-knowledge claim.** The server can read a secret after the passphrase gate
  (D-012). Say what is encrypted and where the key lives.
- **No "production ready" claim.** The host gates (TLS, Redis auth, backups, host firewall)
  are still operator actions — see `PRODUCTION_READINESS.md`.
- **No quotes from the research on this page.** The reviews in `replica/reviews.csv` are
  research, not testimonials, and there are no users to quote yet: the proof section is
  empty on purpose.

## 1. Hero

- **Headline:** Share a secret once — on a server you run.
- **Sub (one line):** One-time links for passwords and keys, with a one-command install,
  a reveal you can read in the source, and a recipient who never needs an account.
- **Button:** `Install it` → jumps to the quickstart; second, quieter link: `Try the hosted
  instance` (only once the host gates close — leave it disabled until then).
- **Screenshot:** of **our** create form and reveal screen, captured from a running
  instance. Not the original's, and not a mockup — a mockup of your own UI is still a
  claim about the product.

## 2. The problem

Two themes, paraphrased from `replica/fixes.md` §1 (never quoted):

> The tool everyone reaches for is somebody else's server, and the person sending the
> password has no way to check what that server does with it. The usual answer is "trust
> us" — a network diagram and a promise.

> And the second-order trap: paste a one-time link into a chat app and its preview may
> spend the link before your colleague ever clicks it.

## 3. How it works

1. **Paste the secret** — set an expiry, add a passphrase if you want an extra access check.
2. **Send the link** — the recipient opens it and confirms; only then is it consumed.
3. **It is gone** — one view, or the expiry, and the record is deleted from Redis.

## 4. Features — fixes first

Fixes from `replica/fixes.md` §4 lead; the parity features are the price of entry and come
after.

| Lead with | What it means here | Status |
| --- | --- | --- |
| **A host you can prove** | `docker compose up` with two env vars. Read `lib/onetime/crypto.rb`; the crypto is ~60 lines and named for what it is. | Verified (Compose smoke test + preflight gate) |
| **Preview-safe share link** | The shareable link does not spend the secret. Nothing is consumed until the recipient presses the button. | Verified in the UI. Caveat: a direct `GET` to the v3 API *does* consume — see the FAQ. |
| **Honest crypto copy** | AES-256-GCM at rest, key derived from your `SECRET`, atomic compare-and-delete on reveal. The server holds the key, so it *can* read a secret; the passphrase is an access check, not a second key. | Verified (spec asserts ciphertext-only Redis + wrong passphrase does not consume) |
| **No account on either end** | Guests create and reveal. Accounts are optional, for receipts and a dashboard. | Verified |
| **Recipient can burn it, you can prove it** | Uniform `404` for expired, viewed, or never-existed — the server does not leak which. | Verified |

Then the baseline: configurable TTL allowlist, 429 + `Retry-After` rate limits, single-use
atomic consume (eight concurrent reveals → exactly one winner), redacted logs, non-root
read-only container, Prometheus metrics behind a flag.

## 5. Pricing

Table from `pricing.md` §4. Community is $0 and is the default answer to "how much" — the
paid tier exists only for people who will not run a server, and it is **not on sale until
the host gates close**.

## 6. FAQ — the real objections

- **Can the server read my secret?** Yes, after you reveal it: the key is derived from the
  instance `SECRET`, which lives on the server. The passphrase is an extra access check; it
  is not a second encryption key, and we do not call this zero-knowledge because it is not.
  If the server cannot read it, don't put it on a server you don't control — that is the
  self-host argument, not a feature.
- **Will a chat preview burn my link?** Not through the share link — the secret is consumed
  only when the recipient confirms. A direct `GET /api/v3/guest/secret/:key` does consume;
  treat the API as a reveal, not a status check.
- **Do I need an account?** No, on either end. Accounts add receipts and a dashboard, and
  they are optional.
- **How long does a secret live?** You pick from a TTL allowlist when you create it; the
  Redis TTL enforces it, so there is no cleanup job to trust.
- **Can I import from my old tool?** No. Secrets are ephemeral by design; there is nothing
  to import, and a bulk import would be a plaintext store — the thing this exists to avoid.
- **Is this production ready?** The app core is packaged and tested (104 specs, CI). The
  operational controls — TLS, Redis auth, backups, metrics, scanning — have code and a
  preflight gate, but a human has to apply them on a real host and the gate must pass
  first. Until then: this is a pre-alpha you can run, not a service to sell.
- **Does it work with SSO / teams / my identity provider?** Not yet. `AUTH_MODE=full`
  returns `501` on purpose rather than pretending.

## 7. Final CTA

> One command, two env vars, your own Redis. **Install it.**

## Build notes

- Sections map 1:1 to a single landing route in the Vue app; no new build tooling.
- Run `python3 ~/.agents/skills/replica-design/contrast.py replica/design/tokens.json`
  after styling — accent on background must stay ≥ 4.5:1 (currently 5.24:1).
- No analytics pixels until the analytics decision in `launch-plan.md` is made; the page
  must not ship a third-party script before the privacy page says so.

**Not built yet.** This file is the approved copy. Putting it into `frontend/` as a route
is a product change (new view, router entry, screenshot, contrast re-check) and is tracked
as the next step in `TASKS.md`, not claimed here.
