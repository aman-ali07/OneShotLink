# API contract

> **Status: secret lifecycle and simple-mode accounts implemented (M3).**
> Health, config, v1 share/reveal, v3 guest/owner conceal/reveal, sessions, account
> routes, and owner receipts work and are covered by integration specs. Colonel,
> OpenAPI, and v2 are **not implemented**; those sections remain contracts. Shapes are
> frozen once shipped; v1 must remain backward compatible.

Base URL: `https://<HOST>` (or `http://` when `SSL=false`). All v3 bodies are JSON;
requests must send `Content-Type: application/json`. v1 accepts
`application/x-www-form-urlencoded` (legacy) and JSON.

## 1. Conventions

| Topic | Rule |
| --- | --- |
| Auth | Session cookie `ots_session` (opaque, `HttpOnly`, `SameSite=Lax`, `Secure` when `SSL=true`, 14-day sliding TTL). v1 endpoints do not require auth. Account and owner routes require a session in `AUTH_MODE=simple`; in `disabled` they return `403 forbidden`, and in `full` they return `501 not_configured` rather than degrading. |
| CSRF | v3 mutations require `Content-Type: application/json` and, when a session cookie is present, same-origin proof (`Sec-Fetch-Site: same-origin` or an `Origin` host matching `Host`). Cookie-authenticated conceal requests are rejected without it. No v1 endpoint reads the session cookie. |
| IDs | Opaque; `secret_key` is the only public secret identifier. |
| Errors (v3) | `{"error":{"code":"...","message":"...","request_id":"..."}}` |
| Errors (v1) | `{"message":"..."}` (legacy shape) |
| Success (v3) | `201` for creation, `200` for reads and session actions, `200 {"ok":true}` for signout |
| Secrets in URLs | Only the key appears in the path. Passphrases are never query parameters. |
| Caching | All secret/reveal responses: `Cache-Control: no-store`, `Pragma: no-cache`. |
| Rate limit | `429` + `Retry-After`. Every rate-limited response also carries `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset` (seconds until the window resets). Successful requests within a limit carry the same `X-RateLimit-*` headers. |
| Request ID | `X-Request-Id` echoed/generated; used in logs instead of payloads |

### Error codes

| Code | HTTP | When |
| --- | --- | --- |
| `validation_error` | 422 | Bad TTL, empty/oversized secret, malformed body, bad passphrase length |
| `not_found` | 404 | Unknown, expired, or already-consumed secret |
| `unauthorized` | 401 | No/invalid session where auth is required |
| `passphrase_required` | 401 | Secret is protected; no passphrase supplied |
| `invalid_passphrase` | 401 | Passphrase supplied and wrong (secret is not consumed) |
| `invalid_credentials` | 401 | Sign-in failed (email unknown or password wrong; same response for both) |
| `forbidden` | 403 | Authenticated but not allowed; auth disabled for account routes |
| `rate_limited` | 429 | Limit exceeded |
| `payload_too_large` | 413 | Body over `MAX_SECRET_BYTES` (1 MiB default) |
| `not_configured` | 501 | `AUTH_MODE=full` route, unimplemented feature |
| `internal_error` | 500 | Redis down, crypto failure; generic message only |

## 2. Public configuration

`GET /api/v3/config` → `200`

```json
{
  "ttl_options": [1800, 43200, 86400, 259200],
  "default_ttl": 86400,
  "auth_mode": "disabled",
  "ui_enabled": true,
  "max_secret_bytes": 1048576,
  "version": "0.1.0"
}
```

## 3. Health

| Route | Response |
| --- | --- |
| `GET /health` | `200 {"status":"ok","redis":"ok","version":"0.1.0"}` or `503 {"status":"degraded","redis":"error"}` |
| `GET /api/v3/health` | Same body, API-shaped |

Health checks must not reveal Redis URL, keyspace size, or configuration values.

## 3a. Metrics

| Route | Response |
| --- | --- |
| `GET /metrics` | `200` Prometheus text exposition, or `404` when `METRICS_ENABLED` is off (default) |

Disabled by default because the series reveal traffic volume. Series:
`onetime_up`, `onetime_redis_up`, `onetime_version_info`,
`onetime_requests_total{family,status}`, `onetime_errors_total`,
`onetime_request_duration_seconds_{sum,count}{family}`, and
`onetime_redis_memory_{used_bytes,max_bytes,used_ratio}`.

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
| `passphrase` | string | no | 1–256 chars |
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

`422` → `{"message":"..."}`. Rate-limited → `429` with `Retry-After`.

### `POST /api/v1/secret/:key` and `GET /api/v1/secret/:key`

No passphrase parameter in v1 (legacy behaviour). A passphrase-protected secret
returns `401` with the legacy `{"message":"..."}` shape and is **not** consumed; reveal
it through v3 or the UI.

Both form-encoded and JSON bodies are accepted; JSON must send
`Content-Type: application/json`.

`200`:

```json
{
  "secret_value": "the plaintext, exactly once",
  "metadata": { "ttl": 86400, "kind": "text" }
}
```

`404` → `{"message":"..."}`. Second call is `404`. Response is `no-store`.

## 5. API v3

Guest routes work with `AUTH_MODE=disabled|simple`. Authenticated routes set an owner and
require a session.

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

Errors: `422 validation_error` (bad TTL, empty/oversized secret, passphrase > 256),
`413 payload_too_large`, `429 rate_limited`, `401 unauthorized` for the authenticated
route. `AUTH_MODE=full` is not reachable yet; it must eventually return `501`, never
silently fall back to anonymous creation (D-003).

### 5.2 Reveal

`GET /api/v3/guest/secret/:key` — no body; a protected secret returns
`401 passphrase_required`.
`POST /api/v3/guest/secret/:key/reveal` — JSON body `{"passphrase": "..."}` (`{}` is
valid for unprotected secrets).
Authenticated equivalents: `/api/v3/secret/:key` and `/api/v3/secret/:key/reveal`.

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

Errors:

- `401 passphrase_required` — no passphrase sent; the secret still exists.
- `401 invalid_passphrase` — wrong passphrase; the secret still exists.
- `404 not_found` — unknown, expired, or already consumed (indistinguishable by design).
- `429 rate_limited`.

The record is deleted **before** the response is sent. The response is `no-store`.
If the request carries a valid session, the owner receipt is created on either conceal
route and is removed from the owner index by the same atomic reveal.

### 5.3 Sessions (simple mode)

All return `403 forbidden` when `AUTH_MODE=disabled`, `501 not_configured` when `full`.

| Route | Body | Success |
| --- | --- | --- |
| `POST /api/v3/signup` | `{"email":"a@b.c","password":"..."}` (12–256 chars) | `201 {"customer":{"id":"...","email":"...","role":"customer","created_at":...}}`, sets cookie |
| `POST /api/v3/signin` | `{"email":"...","password":"..."}` | `200` same customer body, sets cookie |
| `POST /api/v3/signout` | `{}` | `200 {"ok":true}`, clears cookie and deletes the session key |
| `GET /api/v3/account/me` | — | `200 {"customer":{...}}` or `401 unauthorized` |
| `GET /api/v3/account/receipts` | — | `200 {"receipts":[{identifier,secret_ttl,created_at,passphrase_required,kind,secret_url}]}` (newest 50, stale entries pruned) |
| `POST /api/v3/account/password` | `{"current_password":"...","new_password":"..."}` | `200 {"ok":true}`; wrong current password is `401 invalid_credentials` |

Signup and sign-in share the `RATE_LIMIT_SIGNIN` limit (default 10 per window). Duplicate
emails return `409 email_taken`. Email lookup is case-insensitive and normalized; raw
emails are never written into Redis keys.

Login failures are always `401 {"error":{"code":"invalid_credentials"}}`; do not reveal
whether the email exists. Passwords/tokens never appear in responses or logs.

### 5.4 Colonel (admin)

Requires role `colonel`; otherwise `403 forbidden`.

| Route | Response |
| --- | --- |
| `GET /api/v3/colonel/stats` | `200 {"customers":12,"active_secrets":4,"redis":"ok"}` (counts only) |
| `GET /api/v3/colonel/customers?limit=50` | `200 {"customers":[{"id","email","role","created_at"}]}` |

## 6. Deferred endpoints (not in the v1 contract)

Listed so nobody implements them accidentally. Organizations, domains, invites, account
SSO/MFA, and v2 are **out of scope** until [TASKS.md](TASKS.md) Phase 5:

- `/api/v3/organizations*`, `/api/v3/invite*`, `/api/v3/domains*`
- `/api/v3/account/mfa*`, `/api/v3/account/webauthn*`, `/api/v3/account/sso*`
- `/api/v2/*`

## 7. OpenAPI

`GET /api/v3/openapi.json` returns an OpenAPI 3.1 document generated from the route
definitions (`lib/onetime/openapi.rb`, planned T-44). The generated file is committed to
`docs/openapi.json` for client generation. The document must only describe implemented
routes; deferred routes are omitted, not stubbed.

## 8. Examples

```bash
# create (v3 guest)
curl -sX POST http://localhost:3000/api/v3/guest/conceal \
  -H 'content-type: application/json' \
  -d '{"secret":"hello","ttl":1800}'

# reveal once
curl -si http://localhost:3000/api/v3/guest/secret/<key>

# second reveal -> 404
curl -si http://localhost:3000/api/v3/guest/secret/<key>

# v1 create + reveal
curl -sX POST http://localhost:3000/api/v1/share -d 'secret=hello&ttl=1800'
curl -sX POST http://localhost:3000/api/v1/secret/<key>
```

Verified 2026-11-11 with Puma on `:3100` (Redis DB 0): create `201`, first reveal
`200`, second reveal `404`; four parallel reveals produced one `200` and three `404`.
`bundle exec rspec` → 94 examples, 0 failures.
