# API contract

> **Status: secret lifecycle and simple-mode accounts implemented (M3).**
> Health, config, v1 share/reveal, v3 guest/owner conceal/reveal, sessions, account
> routes, and owner receipts work and are covered by integration specs. The OpenAPI 3.1
> document is served at `GET /api/v3/openapi.json` and contract-checked by specs.
> Colonel and v2 are **not implemented**; those paths are listed as deferred in §6 and are not
> mounted. Shapes are
> frozen once shipped; v1 must remain backward compatible.

Base URL: `https://<HOST>` (or `http://` when `SSL=false`). All v3 bodies are JSON;
requests must send `Content-Type: application/json`. v1 accepts
`application/x-www-form-urlencoded` (legacy) and JSON.

## 1. Conventions

| Topic | Rule |
| --- | --- |
| Auth | Session cookie `ots_session` (opaque, `HttpOnly`, `SameSite=Lax`, `Secure` when `SSL=true`, 14-day sliding TTL). v1 endpoints do not require auth. Account routes and the owner burn/request/webhook routes return `403 forbidden` in `AUTH_MODE=disabled`; the owner secret conceal/reveal/preview aliases allow anonymous access in that mode (a session is used only to attach an owner receipt). All `/api` routes return `501 not_configured` in `AUTH_MODE=full` rather than degrading. |
| CSRF | v3 mutations require `Content-Type: application/json`. Cookie-authenticated requests must carry same-origin proof (`Sec-Fetch-Site: same-origin` or an `Origin` matching the full scheme, host and port); without it they are `403`. Signup/signin are also checked when a browser proof is present, so a cross-site forced login cannot bind a victim's session — headerless API clients are unaffected. No v1 endpoint reads the session cookie. |
| IDs | Opaque; `secret_key` is the only public secret identifier. |
| Errors (v3) | `{"error":{"code":"...","message":"...","request_id":"..."}}` |
| Errors (v1) | `{"message":"..."}` (legacy shape) |
| Success (v3) | `201` for creation, `200` for reads and session actions, `200 {"ok":true}` for signout |
| Secrets in URLs | Only the key appears in the path. Passphrases are never query parameters. |
| Caching | All secret/reveal responses: `Cache-Control: no-store`, `Pragma: no-cache`. |
| Rate limit | `429` + `Retry-After`. Every rate-limited response also carries `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset` (seconds until the window resets). Successful requests within a limit carry the same `X-RateLimit-*` headers. |
| Request ID | `X-Request-Id` echoed/generated; used in logs instead of payloads |
| Browser clients | Same-origin only: the app sends no `Access-Control-*` headers. Serve your UI from the same origin or put a same-origin reverse proxy in front of the API. Headerless server clients are unaffected. |

### Rate limits

All budgets are per client identity (proxies are only trusted from `TRUSTED_PROXIES`) and use a
fixed Redis window of `RATE_LIMIT_WINDOW` seconds (default 60), **except** the per-secret
passphrase budget, which uses `RATE_LIMIT_PASSPHRASE_WINDOW` (default 900). A `429` carries
`Retry-After` and `X-RateLimit-*`; `503 service_unavailable` (Redis down/at `maxmemory`) also
carries `Retry-After` but is not a rate limit and must not be counted as one.

| Scope | Applies to | Default | Window |
| --- | --- | --- | --- |
| `conceal` | `POST /api/v3/guest/conceal`, `POST /api/v3/secret/conceal` | 30 | 60 s |
| `reveal` | guest/owner reveal POSTs, `GET /api/v3/requests/:key`, and the two GET secret previews (`/api/v3/guest/secret/:key`, `/api/v3/secret/:key`) | 60 | 60 s |
| `passphrase` | wrong passphrase guesses, keyed by opaque secret id (D-012b) | 5 | 900 s |
| `signin` / `signup` | sign-in and sign-up — **separate buckets** | 10 each | 60 s |
| `request` / `respond` | create incoming request / submit an answer | 10 each | 60 s |
| `webhook` / `webhook_read` | mutate endpoints / list deliveries (`GET /api/v3/webhooks/:id/deliveries`); the endpoint list itself is session-scoped only | 10 each | 60 s |
| `password` / `delete` / `burn` / `signout` | account mutations | 5 / 3 / 10 / 10 | 60 s |
| `metrics` / `metrics_auth` | successful scrapes / failed token attempts | 5 each | 60 s |
| `meta` | unauthenticated `/health`, `/api/v3/config`, OpenAPI probes | 300 | 60 s |

`AUTH_MODE=full` returns `501 not_configured` for **every** `/api` path, including v1; it never
falls back to anonymous behaviour.

### Versioning and compatibility

`v1` is frozen: existing paths and response shapes stay backward compatible, with no
planned removal. `v3` is additive — new routes and optional fields can appear, but existing
fields do not change meaning. A future deprecation would be announced and would use
`Deprecation`/`Sunset` headers; none are in use today.

### Error codes

| Code | HTTP | When |
| --- | --- | --- |
| `validation_error` | 422 | Bad TTL, empty secret, malformed body, bad passphrase length, bad `kind`/`filename` (oversized bodies are `413`) |
| `not_found` | 404 | Unknown, expired, or already-consumed secret |
| `unauthorized` | 401 | No/invalid session where auth is required |
| `passphrase_required` | 401 | Secret is protected; no passphrase supplied |
| `invalid_passphrase` | 401 | Passphrase supplied and wrong (secret is not consumed) |
| `invalid_credentials` | 401 | Sign-in failed (email unknown or password wrong; same response for both) |
| `forbidden` | 403 | Authenticated but not allowed; auth disabled for account routes |
| `conflict` | 409 | The request already has an answer, or a concurrent create lost the race |
| `email_taken` | 409 | Signup email is already registered (case-insensitive) |
| `rate_limited` | 429 | Limit exceeded |
| `payload_too_large` | 413 | The secret value exceeds `max_secret_bytes` (1 MiB default); the HTTP read cap is `max_secret_bytes + 16 KiB` to leave room for JSON overhead |
| `not_configured` | 501 | `AUTH_MODE=full` route, unimplemented feature |
| `service_unavailable` | 503 | Redis is unreachable or at maxmemory. Temporary; the response carries `Retry-After` and the request can be retried once storage has capacity |
| `internal_error` | 500 | Crypto failure or an unexpected bug; generic message only |

## 2. Public configuration

`GET /api/v3/config` → `200`

```json
{
  "ttl_options": [1800, 43200, 86400, 259200],
  "default_ttl": 86400,
  "auth_mode": "disabled",
  "ui_enabled": true,
  "max_secret_bytes": 1048576,
  "max_file_bytes": 524288,
  "version": "0.1.0"
}
```

## 3. Health

| Route | Response |
| --- | --- |
| `GET /health` | `200 {"status":"ok","redis":"ok","version":"0.1.0"}` or `503 {"status":"degraded","redis":"error","version":"0.1.0"}` |
| `GET /api/v3/health` | Same body, API-shaped |

Health checks must not reveal Redis URL, keyspace size, or configuration values.

## 3a. Metrics

| Route | Response |
| --- | --- |
| `GET /metrics` | `200` Prometheus text exposition, or `404` when `METRICS_ENABLED` is off (default) or the scrape token is missing/wrong |

Disabled by default because the series reveal traffic volume. When enabled, a
**bearer token is mandatory**: send `Authorization: Bearer <METRICS_TOKEN>` (at least
32 bytes). A missing or wrong token returns the same uniform `404`; more than
`RATE_LIMIT_METRICS_AUTH` failures per window return `429`. Configure the scrape
target with that header — Prometheus supports `authorization` in `scrape_configs`.
The exact build version is deliberately not published in the exposition.

Series:
`onetime_up`, `onetime_redis_up`,
`onetime_requests_total{family,status}`, `onetime_errors_total`,
`onetime_request_duration_seconds_{sum,count}{family}`, and
`onetime_redis_memory_{used_bytes,max_bytes,used_ratio}`, and
`onetime_best_effort_failures_total{operation}` where `operation` is `cleanup`, `audit` or `other`.

`family` is a fixed, bounded label (`health`, `metrics`, `web`, `api_v1`,
`api_v3_guest`, `api_v3`, `other`) — never a secret key or raw path. Counters are
per-process; scrape every worker to see totals. Alert on `onetime_redis_up == 0`,
`onetime_redis_memory_used_ratio >= 0.8`, and a rising
`rate(onetime_errors_total[5m])`.

## 4. API v1 (legacy compatibility)

Form-encoded, anonymous, no session. Rate limits still apply (per IP).

### `POST /api/v1/share`

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `secret` | string | yes | 1 byte – 1 MiB |
| `passphrase` | string | no | 8–256 bytes; an empty string means no passphrase (D-014) |
| `ttl` | integer | no | Must be in `TTL_OPTIONS`; default `DEFAULT_TTL` |

`200`:

```json
{
  "secret_key": "Hk3v9QpL2mR8sT4uW6xY1a",
  "receipt": {
    "identifier": "Hk3v9QpL2mR8sT4uW6xY1a",
    "secret_ttl": 86400,
    "passphrase_required": false
  }
}
```

`422` → `{"message":"..."}`. An oversized body is `413` whether the size is declared in
`Content-Length` or not — the bytes actually read are capped, so a chunked upload cannot
exceed `MAX_SECRET_BYTES`. Rate-limited → `429` with `Retry-After`.

### `POST /api/v1/secret/:key` and `GET /api/v1/secret/:key`

No passphrase parameter in v1 (legacy behaviour). A passphrase-protected secret
returns `401` with the legacy `{"message":"..."}` shape and is **not** consumed; reveal
it through v3 or the UI.

`HEAD /api/v1/secret/:key` answers `405` with `Allow: GET, POST`. HEAD is rewritten to GET
internally, and because the v1 GET consumes, a HEAD would otherwise destroy the secret
while its body is discarded — link unfurlers and probes must not be able to do that.

Both form-encoded and JSON bodies are accepted; JSON must send
`Content-Type: application/json`.

`200`:

```json
{
  "secret_value": "the plaintext, exactly once",
  "metadata": { "kind": "text", "filename": null, "created_at": 1762819200, "ttl": 86400 }
}
```

`404` → `{"message":"..."}`. Second call is `404`. Response is `no-store`.

## 5. API v3

Guest routes work with `AUTH_MODE=disabled|simple`. Authenticated routes set an owner and
require a session.

Three cross-cutting properties of the v3 surface:

- **Creates are not idempotent.** Retrying a timed-out `POST` (conceal, request, webhook)
  creates a second resource and spends another rate-limit slot. Deduplicate on the returned
  `secret_key`/`request_key`/`id`. Webhook *deliveries* are idempotent by `delivery id`, which
  is a separate guarantee.
- **List endpoints are fixed slices**, not paginated: receipts, incoming requests and webhook
  endpoints return at most the newest 50, and support no `page`/`per_page`/filter parameters.
  Do not treat a short list as the complete set.
- **Secrets are not end-to-end encrypted.** The passphrase is an access gate checked by the
  server before the atomic delete; the server can decrypt revealed values (D-012).

### 5.1 Conceal

`POST /api/v3/guest/conceal` (anonymous; attaches an owner receipt when a valid session is present)
`POST /api/v3/secret/conceal` (session required when `AUTH_MODE != disabled`)

```json
{
  "secret": "correct horse battery staple",
  "ttl": 86400,
  "passphrase": "optional",
  "kind": "text"
}
```

`201`:

```json
{
  "secret_key": "Hk3v9QpL2mR8sT4uW6xY1a",
  "receipt": {
    "identifier": "Hk3v9QpL2mR8sT4uW6xY1a",
    "secret_ttl": 86400,
    "passphrase_required": false,
    "kind": "text"
  },
  "links": { "secret": "/secret/Hk3v9QpL2mR8sT4uW6xY1a" }
}
```

Errors: `422 validation_error` (bad TTL, empty/oversized secret, passphrase shorter than 8
or longer than 256 bytes; an empty passphrase means none),
`413 payload_too_large`, `429 rate_limited`, `401 unauthorized` for the authenticated
route. Under `AUTH_MODE=full` the authenticated routes return `501 not_configured` rather
than silently falling back to anonymous creation (D-003); full mode is not implemented and
must never degrade quietly.

#### File secrets (v3 only)

Send `kind: "file"`, a safe `filename` (1–255 bytes, no path separators or control
characters) and `secret` containing **strict base64** of the file bytes. The decoded size
must not exceed `max_file_bytes` from `/api/v3/config` (512 KiB by default); the encoded
body still passes through the ordinary `MAX_SECRET_BYTES` ceiling. The record is encrypted
exactly like text, and the metadata keeps `kind` and `filename`.

```json
{
  "secret": "AAH+/0FCQg==",
  "ttl": 1800,
  "kind": "file",
  "filename": "notes.bin"
}
```

A reveal of a file returns `secret_value` as **base64**, not as raw text:

```json
{
  "secret_value": "AAH+/0FCQg==",
  "metadata": { "kind": "file", "filename": "notes.bin", "created_at": 1762819200, "ttl": 1800 }
}
```

Base64 is used because the decrypt path forces UTF-8; arbitrary binary bytes would be
corrupted if stored raw. Decode in the browser (or your client) before writing the file.
Invalid base64 is `422 validation_error`; a decoded file over the ceiling is `413
payload_too_large`; an unsafe or missing filename is `422 validation_error`. All other
single-use, passphrase and preview semantics are identical to text secrets. v1 has no file
support and keeps its frozen shape.

### 5.2 Reveal

`POST /api/v3/guest/secret/:key/reveal` is the **only** route that spends a secret. JSON
body `{"passphrase": "..."}` (`{}` is valid for unprotected secrets). Authenticated
equivalent: `POST /api/v3/secret/:key/reveal`.

`GET /api/v3/guest/secret/:key` **describes** the secret and never touches it, so a chat
client's link preview cannot burn it:

```json
{
  "passphrase_required": false,
  "metadata": { "kind": "text", "filename": null, "created_at": 1762819200, "ttl": 86400 }
}
```

`404 not_found` (unknown/expired/consumed) and `429 rate_limited` apply to both. The
authenticated `GET /api/v3/secret/:key` behaves the same way but requires a session.
The frozen v1 contract is different: `GET /api/v1/secret/:key` **does** consume (§4) —
link the UI, not a v1 API URL.

The passphrase is an **access gate**, not a second encryption key (D-012): content is
encrypted with the instance `SECRET`, and the Argon2id hash is verified before the
atomic delete. Do not describe this as zero-knowledge.

`200`:

```json
{
  "secret_value": "the plaintext, exactly once",
  "metadata": { "kind": "text", "filename": null, "created_at": 1762819200, "ttl": 86400 }
}
```

Errors (on the `reveal` POST):

- `401 passphrase_required` — no passphrase sent; the secret still exists.
- `401 invalid_passphrase` — wrong passphrase; the secret still exists.
- `422 validation_error` — non-string or over-256-byte passphrase; no guess is spent.
- `404 not_found` — unknown, expired, or already consumed (indistinguishable by design).
- `429 rate_limited`.

The record is consumed **before** the response is sent, and only after the passphrase
check and the decryption have succeeded — a wrong passphrase, a rotated `SECRET` or a
corrupt record leaves it intact (D-013). The response is `no-store`.
If the request carries a valid session, the owner receipt is created on either conceal
route. Reveal permanently deletes the payload with the atomic consume; the receipt stays as
`revealed` with non-sensitive metadata for 30 days (D-017). A public `GET` preview marks it
`previewed` without consuming or decrypting anything, and cannot downgrade a terminal
status.

**Owner burn (D-017):** `DELETE /api/v3/secret/:key` destroys an unrevealed secret without
returning it. It requires a session and CSRF/origin proof, is rate-limited by
`RATE_LIMIT_BURN` (default 10 per `RATE_LIMIT_WINDOW`), and is owner-scoped — a foreign or
unknown key answers the same `404`. Success is
`200 {"ok":true,"metadata":{"identifier":"…","status":"burned"}}`; the payload is gone, the
receipt becomes `burned` with the same 30-day retention, and a replay is `404`. No plaintext
or bearer key appears in the response, audit stream, or logs; the audit event is
`secret.burned`.

### 5.3 Incoming secret requests (simple mode)

An owner creates a public link; anyone with the link sends **one** secret; the owner opens
that answer once. Creation, listing and reveal require a session; preview and respond are
public capabilities (C2) and work in the default `AUTH_MODE=disabled` — they are rate-limited
(`:reveal` for preview, `:respond` for answering), validated, and accept only one answer via
`SET NX`. Only owner-side creation/listing/reveal need `AUTH_MODE=simple`.

| Route | Auth | Body | Success |
| --- | --- | --- | --- |
| `POST /api/v3/requests` | session + CSRF proof | `{"label":"API key please","ttl":1800}` (label ≤ 120 bytes, optional) | `201 {"request_key":"…","metadata":{"label":…,"created_at":…,"ttl":…},"links":{"request":"/request/<key>"}}` |
| `GET /api/v3/requests` | session | — | `200 {"requests":[{request_key,label,created_at,ttl,fulfilled}]}` (newest 50) |
| `GET /api/v3/requests/:key` | public | — | `200 {"fulfilled":false,"metadata":{"label":…,"created_at":…,"ttl":…}}` — never returns the submitted value |
| `POST /api/v3/requests/:key/respond` | public | `{"secret":"…"}` | `201 {"ok":true,"label":"…"}`; a second answer is `409 conflict` |
| `POST /api/v3/requests/:key/reveal` | session + CSRF proof | `{}` | `200 {"secret_value":"…","metadata":{"kind":"text","filename":null,"label":…,"created_at":…,"ttl":…}}`; replay is `404` |

The submission is encrypted with the same AES-256-GCM path as ordinary secrets and stored
under `request:secret:<key>` with `SET NX`, so exactly one responder wins a race. Reveal
decrypts *before* the atomic compare-and-delete, so a rotated `SECRET` cannot destroy the
answer. Unknown, expired and already-revealed keys all answer the same `404`. Submitted
secrets are text only and have **no passphrase**; use an ordinary secret link when a
passphrase is needed. Audit events use the stable names `request.created`,
`request.responded` and `request.revealed`.

### 5.4 Sessions (simple mode)

All return `403 forbidden` when `AUTH_MODE=disabled`, `501 not_configured` when `full`.

| Route | Body | Success |
| --- | --- | --- |
| `POST /api/v3/signup` | `{"email":"a@b.c","password":"..."}` (12–256 chars) | `201 {"customer":{"id":"...","email":"...","role":"customer","created_at":...}}`, sets cookie |
| `POST /api/v3/signin` | `{"email":"...","password":"..."}` | `200` same customer body, sets cookie |
| `POST /api/v3/signout` | `{}` | `200 {"ok":true}`, clears cookie and deletes the session key |
| `GET /api/v3/account/me` | — | `200 {"customer":{...}}` or `401 unauthorized` |
| `GET /api/v3/account/receipts` | — | `200 {"receipts":[{identifier,secret_ttl,created_at,passphrase_required,kind,status,secret_url}]}` (newest 50, stale entries pruned; `status` is `new\|previewed\|revealed\|burned`) |
| `POST /api/v3/account/password` | `{"current_password":"...","new_password":"..."}` | `200 {"ok":true}`; wrong current password is `401 invalid_credentials` |
| `DELETE /api/v3/account` | `{"password":"..."}` | `200 {"ok":true}`, clears the cookie and removes the customer record, its email index, every session and every receipt. A wrong password is `401 invalid_credentials` and deletes nothing. Secrets still inside their TTL keep working for their recipients until they expire |

Signup and sign-in use separate buckets (`RATE_LIMIT_SIGNUP` and `RATE_LIMIT_SIGNIN`,
each default 10 per window) so a burst in one flow cannot lock out the other. Webhook
creation/deletion, password change, account deletion, signout and request creation also
have their own `RATE_LIMIT_*` settings; every limited response carries `429`, `Retry-After`
and `X-RateLimit-*`. Duplicate emails return `409 email_taken`. Email lookup is
case-insensitive and normalized; raw emails are never written into Redis keys.

Login failures are always `401 {"error":{"code":"invalid_credentials"}}`; do not reveal
whether the email exists. Passwords/tokens never appear in responses or logs.

### 5.5 Webhooks (simple mode)

Owner-scoped endpoints receive **metadata-only** lifecycle events. Payloads never contain
plaintext, ciphertext, passphrases or tokens — only identifiers and the same metadata the
dashboard shows.

| Route | Auth | Body | Success |
| --- | --- | --- | --- |
| `POST /api/v3/webhooks` | session + CSRF proof | `{"url":"https://hooks.example.com/ots","events":["secret.revealed"]}` | `201` with `id`, `url`, `events`, `enabled`, `created_at` and `signing_secret` (**returned once**) |
| `GET /api/v3/webhooks` | session | — | `200 {"webhooks":[…]}` — newest 50, never includes `signing_secret` |
| `GET /api/v3/webhooks/:id/deliveries` | session | — | `200 {"deliveries":[{id,event,status,attempts,response_code,created_at}]}`; only that endpoint's deliveries, `404` for an unknown/foreign id (B8) |
| `DELETE /api/v3/webhooks/:id` | session + CSRF proof | — | `200 {"ok":true}` |

Event names: `secret.created`, `secret.revealed`, `request.created`, `request.responded`,
`request.revealed`. Unknown names and non-public URLs are `422 validation_error`; private
addresses are refused unless the operator explicitly sets `WEBHOOK_ALLOW_PRIVATE=true` for
local development.

Delivery runs in `bin/ots webhooks:work` (optionally with a limit), so web traffic never
waits on an external HTTP call. Each delivery has a stable `X-OneShotLink-Delivery` id and
is claimed with Redis `SET NX`, so a replayed event cannot produce a second POST. The body
is signed with HMAC-SHA256 over the raw JSON using the per-endpoint signing secret and sent
as `X-OneShotLink-Signature: sha256=<hex>` alongside `X-OneShotLink-Event`. Failed deliveries
are retried up to three times with backoff and recorded with status/failure class only —
response bodies and secret material are never logged. The signing secret is encrypted at
rest with the same AES-256-GCM path used for secrets.

## 6. Deferred endpoints (not in the v1 contract)

Listed so nobody implements them accidentally. Organizations, domains, invites, account
SSO/MFA, and v2 are **out of scope** until [TASKS.md](TASKS.md) Phase 5:

- `/api/v3/organizations*`, `/api/v3/invite*`, `/api/v3/domains*`
- `/api/v3/account/mfa*`, `/api/v3/account/webauthn*`, `/api/v3/account/sso*`
- `/api/v3/colonel*` — the admin console. The CLI covers the operator's needs today
  (`bin/ots customers list|show|set-role`), so these routes are not mounted: they answer
  `404`, and any future version must be added here, to `openapi.rb` and to the specs
  together
- `/api/v2/*`

## 7. OpenAPI

`GET /api/v3/openapi.json` returns an OpenAPI 3.1 document built in
`lib/onetime/web/openapi.rb` (T-44). The served document is the source of truth for
clients; there is no committed copy to drift out of date. A spec asserts that every
documented path is actually mounted and every `$ref` resolves, and the document must only
describe implemented routes — deferred routes are omitted, not stubbed. Every
Redis-backed route documents `503 service_unavailable`, including the incoming-request
operations and the webhook list; the webhook delivery listing also documents `404` for a foreign
or unknown endpoint id. `/api/v3/openapi.json` is authoritative. Frozen v1
error responses reference the legacy `{"message":...}` envelope (including 429 and 503), and
v1 share documents both JSON and form bodies; the mount gate detects the generic catch-all
404 body by code and message, with a bogus-path negative control proving the gate has teeth.

## 8. Examples

```bash
# create (v3 guest)
curl -sX POST http://localhost:3000/api/v3/guest/conceal \
  -H 'content-type: application/json' \
  -d '{"secret":"hello","ttl":1800}'

# preview only — GET never consumes and never returns the value
curl -si http://localhost:3000/api/v3/guest/secret/<key>

# reveal once: POST is the only consuming route
curl -si -X POST http://localhost:3000/api/v3/guest/secret/<key>/reveal \
  -H 'content-type: application/json' -d '{}'

# second reveal -> 404
curl -si -X POST http://localhost:3000/api/v3/guest/secret/<key>/reveal \
  -H 'content-type: application/json' -d '{}'

# v1 create + reveal (frozen legacy contract: v1 GET consumes)
curl -sX POST http://localhost:3000/api/v1/share -d 'secret=hello&ttl=1800'
curl -sX POST http://localhost:3000/api/v1/secret/<key>
```

Runnable, dependency-free versions of this flow (curl, TypeScript, Python) live in
[`examples/`](examples/) and are documented in [`docs/SDK.md`](docs/SDK.md).

Verified against the production image through Compose (Redis DB 15 for the specs): create
`201`, preview `200` with metadata only, first reveal `200`, second reveal `404`; parallel
reveals produce exactly one `200`. The v1 shapes above were copied from live responses.
