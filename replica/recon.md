# Recon map: Onetime Secret (web)

Scope: the core loop — create a one-time secret link, share it, reveal it exactly once —
plus the accounts and team features that gate it on the hosted service.
For: this repository's self-hosted clone (working title only; see [../AGENTS.md](../AGENTS.md)).
Date: 2026-11-11. Method: `replica-recon`, clean-room, public pages only.

> **Clean-room note.** This map records *what the product does* and *how the flow moves*.
> It does not copy source code, JavaScript bundles, logos, screenshots, or marketing copy.
> The original's name is a research reference. The shipped clone must be rebranded
> (`/replica-brand`) and swept before launch. Never load assets from the original domain.

## Sources

| # | source | URL | notes |
| --- | --- | --- | --- |
| 1 | Marketing home + inline create form | https://onetimesecret.com/ | fetched 2026-11-11; shows core loop, TTL/passphrase framing, features |
| 2 | Pricing + plan comparison | https://onetimesecret.com/en/pricing | plans: Basic €0, Identity Plus €35, Team Plus €125; TTL up to 14/30 days |
| 3 | About + FAQ | https://onetimesecret.com/en/about | explains passphrase model, no file sharing, open source |
| 4 | Documentation home | https://docs.onetimesecret.com/en | guides, API, self-hosting, 16 UI languages listed |
| 5 | REST API docs (linked from home) | https://docs.onetimesecret.com/en/rest-api | public contract; do not copy implementation |
| 6 | Public GitHub project page | https://github.com/onetimesecret/onetimesecret | confirms open source; **source not read** during recon |
| 7 | User-supplied product brief | (in project chat) | desired stack and v1 scope; not an original-site source |

Not available in this environment: the user's own account, a real browser (no
screenshots), app-store listings of their desktop/mobile clients. Screens S02–S19 are
therefore **inferred** from the public pages, FAQ, docs and the brief; each row says so.

## Core loop

Paste sensitive text → choose expiry (and optionally a passphrase) → receive a link →
recipient opens it once → content is shown → the record is destroyed.

## Screens

| ID | screen | route / how to reach | purpose | key components | states seen |
| --- | --- | --- | --- | --- | --- |
| S01 | Marketing home with inline create form | `/` | Explain product, start a secret | hero, secret textarea, create button, plan/feature sections, nav, footer | filled (public page) |
| S02 | Conceal / create page | inferred `/` or `/create` | Compose secret with options | textarea, TTL select, passphrase field, warnings, submit | inferred |
| S03 | Secret-created result | inferred after create | Hand over the one-time link | link display, copy button, QR (possible), new-secret action | inferred |
| S04 | Reveal gate / passphrase prompt | inferred `/secret/:key` | Warn before burning + collect passphrase | warning copy, passphrase input, reveal button | inferred |
| S05 | Revealed secret | inferred `/secret/:key` after reveal | Show content once | monospace secret, copy, "viewed/deleted" notice | inferred |
| S06 | Gone / expired / already viewed | inferred `/secret/:key` | Terminal state, no retry | neutral error, "ask sender for a new link" | inferred |
| S07 | Sign up | `/signup` (linked) | Create account | email, password, plan/region context | link verified, page not fetched |
| S08 | Sign in | `/signin` (linked) | Authenticate | email, password, forgot link | link verified, page not fetched |
| S09 | Account dashboard / receipts | inferred | See active and consumed secrets | table/list, TTL, status, create action | inferred |
| S10 | Account settings | inferred | Email, password, MFA, sessions | forms, danger zone | inferred |
| S11 | Pricing + plan compare | `/en/pricing` | Choose plan | 3 plan cards, feature matrix, billing toggle | filled (public page) |
| S12 | Docs / help / API | docs site | Learn + integrate | sidebar, search, code blocks | filled (public page) |
| S13 | Custom domain settings | inferred, paid | Branded links | domain input, DNS records, verify status | inferred |
| S14 | Organization / team members | inferred, paid | Invite, roles, SSO | member table, role select, invite form | inferred |
| S15 | Incoming secrets / request link | inferred, paid | Let others send to you | request-link builder, inbox | inferred |
| S16 | About / FAQ | `/en/about` | Trust + answers | FAQ accordions, story | filled (public page) |
| S17 | Status | linked footer | Availability | uptime/incident list | linked only |
| S18 | What's new / changelog | linked nav | Release notes | entries | linked only |
| S19 | Legal (privacy, terms, security) | linked footer | Compliance | long-form pages | linked only |
| S20 | API reference | docs `/en/rest-api` | Integrate | endpoints, auth, examples | filled (docs) |

## Flows

```
F01 Guest creates a secret
    S01/S02 -> S03
    happy path clicks: ~3 (type, choose TTL, create)
    edge: empty secret, oversized, no TTL chosen, passphrase set but not confirmed,
          clipboard unavailable, page refresh before copying the link

F02 Recipient reveals once
    S04 -> S05 -> S06 (on any later attempt)
    happy path clicks: ~2 (open link, reveal)
    edge: passphrase required, wrong passphrase (must not burn), already viewed,
          expired, two tabs open, network drops mid-reveal

F03 Account signup and signin
    S07 -> verify email -> S08 -> S09
    edge: duplicate email, weak password, wrong password (no account enumeration),
          expired session, password reset

F04 Signed-in user creates and tracks a secret
    S09 -> S02 -> S03 -> S09
    edge: receipt disappears after reveal; TTL shown correctly across time zones

F05 Passphrase-protected share
    S02 (passphrase) -> S03 -> S04 (prompt) -> S05
    edge: wrong passphrase repeated, sender forgets passphrase (secret unrecoverable)

F06 Custom domain setup (paid, deferred here)
    S13 -> DNS verification -> branded links
    edge: TXT/CNAME not propagated, domain already claimed, TLS pending

F07 Team invite + roles + SSO (paid, deferred here)
    S14 -> invite email -> accept -> role-scoped workspace
    edge: revoked invite, role change mid-session, SSO misconfiguration

F08 Incoming secret request (paid, deferred here)
    S15 create request link -> sender opens -> recipient inbox
    edge: request link reuse policy, expired request

F09 API create/reveal (v1 + v3)
    POST create -> key -> GET/POST reveal -> 404 on second call
    edge: rate limit, bad TTL, passphrase missing, concurrent reveal

F10 Locale / theme switch on marketing + docs
    language menu (16 listed) and light/dark/auto theme
    edge: untranslated strings, RTL (not advertised), persisted preference
```

## Components

| component | variants | states | used on |
| --- | --- | --- | --- |
| Secret textarea | plain, with counter | empty, filled, too large, error | S01, S02 |
| TTL select | presets, custom (paid) | default, selected, invalid | S02 |
| Passphrase field | optional, reveal toggle | empty, filled, weak, error | S02, S04 |
| Primary button | create, reveal, copy, save | default, hover, focus, loading, disabled | all |
| One-time link result | link + copy + QR | fresh, copied, clipboard denied | S03 |
| Warning / callout | info, danger | static | S02, S04, S06 |
| Secret display | monospace block | visible, copied | S05 |
| Terminal/empty state | gone, expired, not-found | static | S06 |
| App header/nav | marketing, app, docs | signed-out, signed-in | all |
| Account table | receipts, members | empty, loading, filled | S09, S14 |
| Plan card / matrix | 3 tiers, billing toggle | monthly, yearly | S11 |
| Modal / dialog | confirm reveal, delete account | open, busy, error | S04, S10 |
| Toast / inline alert | success, error | auto-dismiss, persistent | S03, S05, S07 |
| Custom-domain form | add, verify | pending, verified, failed | S13 |

## Inferred data model

```
Secret      id (opaque), ciphertext, iv, tag, salt, passphrase_hash?, ttl,
            created_at, owner_id?, kind=text, viewed_at?
            evidence: S01/S02/S04, FAQ ("we display it once and then delete it"),
                      pricing ("automatic destruction after viewing", TTL up to 14/30 d)
            confidence: high for fields, medium for exact storage

Customer    id, email, password_hash, role (owner|admin|member), plan,
            created_at, verified_at, mfa?, org_id?
            evidence: S07/S08/S09, pricing (RBAC, SSO, unlimited members)
            confidence: high

Organization id, name, plan, branding, sso_config?, created_at
            evidence: pricing Team Plus, docs "branded workspace"
            confidence: medium

CustomDomain domain, org_id, verification_state, created_at
            evidence: S13, pricing "one/unlimited custom domains"
            confidence: medium

Receipt     secret_id, owner_id, created_at, ttl, status (active|viewed|expired)
            evidence: S09 inferred, FAQ "can I retrieve it?" -> no
            confidence: guess (dashboard shape not seen)

IncomingRequest id, owner_id, label, expires_at, used_at?
            evidence: pricing "Incoming secrets ... private request link"
            confidence: medium

Plan        name, price_cents, currency, limits (domains, ttl_days, members)
            evidence: S11
            confidence: high
```

Relationships: Customer 1-n Secret; Organization 1-n Customer; Organization 1-n
CustomDomain; Customer 1-n IncomingRequest.

## Feature matrix

See `features.csv`. Must: 11, should: 7, could: 5, skip: 4 (brand/content/network/infra).

## Out of scope (cannot or should not be cloned)

- Their name, logo, illustrations, marketing copy, and domain. Rebrand before launch.
- Their customer base, brand trust, regional hosting footprint (EU/CA/NZ/US/UK/BR/AU/MX),
  and payment relationships.
- The hosted plan economics and Stripe billing integration, unless the clone chooses to
  sell (deferred).
- Their proprietary operational tooling and private APIs. Public REST API docs only.
- Licensed third-party fonts/icons if any; the clone uses open alternatives.

Deferred in this repo, but buildable later: custom domains, organizations/RBAC/SSO,
incoming-secret request links, MFA/WebAuthn, email delivery. See `TASKS.md` Phase 5.

## Size

Screens 20 (4 verified public, 16 inferred), flows 10, entities 6–7. Hard parts:
concurrent one-time reveal, passphrase model parity (see below), custom-domain
verification, team/SSO multi-tenancy, rate limiting behind a proxy, i18n breadth.
Size: **M** for the core loop + simple accounts; **L** for hosted-plan parity.

### Parity risk worth a decision

The original's FAQ says its bcrypt passphrase hash cannot decrypt a secret and that
without the passphrase the secret cannot be decrypted "even by us". This repo's current
design (per the product brief) encrypts with an instance-wide `SECRET` and verifies a
passphrase hash before reveal — the server *can* decrypt without the passphrase. That is
a real security/parity difference, recorded in `KNOWN_ISSUES.md` (K-21) and TASKS.md
(T-48). **Decided 2026-11-11 (D-012):** keep the access-gate model for v1 and never claim
zero-knowledge; revisit only as an opt-in client-side mode. This remains a parity gap by
design, not an implementation bug.
