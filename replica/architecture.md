# Architecture: Onetime Secret clone (self-hosted, text secrets)

Inputs: `replica/recon.md`, `replica/features.csv`, and the fixed stack from the brief.
This is the v1 core-loop architecture, not hosted-plan parity.

## Stack

| layer | choice | why |
| --- | --- | --- |
| web | Ruby 3.3 + Roda on Rack 3 + Puma | Required by the brief; small surface; tree routing without Rails |
| frontend | Vue 3 + TypeScript + Vite 6 + Tailwind 4 | Required by the brief; static build served by Rack |
| database | Redis 7+ / Valkey | TTL expiry and atomic Lua consume are the core primitives; no relational data in v1 |
| auth | Redis opaque sessions; Argon2id (bcrypt migration) | Simple mode only; SSO/MFA deferred (D-003) |
| payments | none | Billing is out of v1 (features.csv `skip`) |
| email | none in v1 | Verification/reset deferred; no worker process |
| jobs | none | Redis TTL is the expiry mechanism (D-008) |
| hosting | Docker Compose (web + Redis) | One-command self-hosting is a product requirement |

Deliberate adaptation: this project does not use SQL or an ORM, so there is no
`replica/schema.sql`. The schema lives in [../DATABASE.md](../DATABASE.md) and is
summarised below. Keep this file and DATABASE.md in sync.

## Schema

Entities: Secret, Receipt, Customer, Session, (deferred: Organization, CustomDomain,
IncomingRequest). Access rules: **data-layer checks**, not RLS — every read/write takes
`owner_id` from the session and the model scopes by it.

```text
secret:object:<objid>    string(JSON) EX ttl   encrypted payload + passphrase hash
secret:receipt:<objid>   hash         EX ttl   metadata only
customer:object:<id>     hash                  account, Argon2id hash, role
customer:email:<sha256>  string -> id          hashed email index (no raw emails as keys)
customer:<id>:secrets    zset                  owner receipt index, score=created_at
session:<token>          hash         EX 14d   server-side session
limiter:<client>:<scope>[ :counter ]           fixed-window counters
```

Hard constraints:

- `secret:object` stays a JSON string so `Store.consume` can compare-and-delete one value.
- Both secret keys share the same TTL; a reveal deletes both.
- No plaintext, passphrase, or decoded content in any key (DATABASE.md invariants).
- IDs are ≥128 bits from a CSPRNG; the email index is a SHA-256 of the normalized email.

## API

| method path | does | who | input | output | flow |
| --- | --- | --- | --- | --- | --- |
| GET `/api/v3/config` | UI options | public | — | TTLs, auth mode, limits | F01/F04 |
| POST `/api/v3/guest/conceal` | create secret | public | JSON secret, ttl, passphrase? | 201 key + receipt | F01/F09 |
| POST `/api/v3/secret/conceal` | create as owner | session | same | 201 key + receipt | F04/F09 |
| GET `/api/v3/guest/secret/:key` | reveal (no passphrase) | public | — | 200 plaintext once | F02 |
| POST `/api/v3/guest/secret/:key/reveal` | reveal with passphrase | public | passphrase | 200 or 401 | F02/F05 |
| POST `/api/v1/share` | legacy create | public | form secret, ttl, passphrase? | 200 key + receipt | F09 |
| GET/POST `/api/v1/secret/:key` | legacy reveal | public | — | 200 plaintext once | F09 |
| POST `/api/v3/account/signup` | create account | public | email, password | 201 + cookie | F03 |
| POST `/api/v3/account/signin` | log in | public | email, password | 200 + cookie | F03 |
| POST `/api/v3/account/signout` | log out | session | — | 204 | F03 |
| GET `/api/v3/account/me` | session info | session | — | 200 customer | F03 |
| GET `/health` | liveness | public | — | 200/503 | ops |

Webhooks in/out: none in v1. Jobs: none (TTL expiry). Full contract and error codes:
[../API.md](../API.md).

## The parts that bite

- **Race:** two reveals must yield one 200 and one 404. Solved by compare-and-delete Lua,
  not by Ruby read-then-delete. Test with parallel requests.
- **Passphrase parity:** the original claims the server cannot decrypt without the
  passphrase. This design encrypts with an instance key and gate-checks the hash, so the
  server can. Decision needed (K-21/T-48) before claiming parity.
- **Rate limiting behind a proxy:** the client IP must come from a trusted, overwritten
  header; otherwise limits are spoofable or shared by everyone.
- **Memory:** Redis holds up to 1 MiB per secret for up to the max TTL. `noeviction` plus
  monitoring; cap ingress.
- **Key rotation:** changing `SECRET` destroys unread secrets; no re-encryption tool yet.
- **CSRF:** cookie-authenticated v3 mutations require JSON content type + origin checks;
  v1 must never read the session cookie.
- **No files:** the original does not support file secrets (FAQ); do not add uploads
  while claiming parity.
- **Expiry UX:** a gone link must look the same whether expired, consumed, or never
  existed; do not leak which.

## Build order

1. **Vertical slice (proves the stack):** S02 create → S03 link → S04/S05 reveal → S06
   gone, with `secret:object`/`receipt`, `POST /api/v3/guest/conceal`,
   `/api/v3/guest/secret/:key`, and the Roda shell. Ugly is fine.
2. **Must-haves:** API v1 compatibility, TTL options, passphrase flow, rate limits,
   `/health`, conceal/reveal UI (S01–S06), encryption/atomic-reveal specs.
3. **Should-haves:** simple accounts + dashboard (S07–S10), API v3 authenticated routes,
   config endpoint, theme.
4. **Deferred:** custom domains (S13), incoming requests (S15), teams/SSO (S14), i18n,
   MFA, billing.
5. **Fixes from `/replica-entrepreneur`:** after the core loop is tested and scored by
   `/replica-diff`.

## As built (M1, 2026-11-11)

The API half of step 1 is real; the browser half is M2.

| Planned | Actual |
| --- | --- |
| `apps/api` split | One `lib/onetime/web/app.rb` Roda class; split only if routes grow |
| `models/secret.rb` + `models/receipt.rb` | One `models/secret.rb` owns both keys so the TTLs and cleanup stay together |
| Otto/Familia | Plain Roda + explicit Redis mapping (D-001, D-002) |
| logic objects | `logic/conceal_secret.rb`, `logic/reveal_secret.rb` (validation and ordering) |
| v1 + v3 routes | v1 form/JSON; v3 guest routes (anonymous or session-attached) and authenticated owner routes |
| owner index | Written when a session is present; removed by atomic reveal; dashboard lists receipts |
| frontend | Built: Vue 3 SPA in `frontend/`, tokens from `replica/design/`, served by Rack |

Verified behavior: create → reveal once → gone in the browser and API; 8-way race = one
winner; TTL expiry; ciphertext-only Redis; wrong passphrase does not consume; `429` +
`Retry-After`; no plaintext in URL/localStorage. Evidence: 68 specs, a live Puma run, and
a headless Chrome journey. Simple-mode accounts/sessions and a second browser journey
landed in M3. Next: test/diff (M4). Brand work
(`/replica-brand`) must run before any launch; the current name is a working title.
