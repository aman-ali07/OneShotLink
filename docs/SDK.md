# OneShotLink developer guide

OneShotLink ships an HTTP API, not a published SDK package. This guide gives copy-paste
examples in curl, TypeScript and Python using only each platform's standard library. The
served OpenAPI 3.1 document at `GET /api/v3/openapi.json` is the machine-readable contract;
[API.md](../API.md) is the human-readable one.

Set `BASE_URL` to your instance (default `http://127.0.0.1:3000`). Run the complete
examples in [`examples/`](../examples/) after starting a local stack:

```bash
BASE_URL=http://127.0.0.1:3000 bash examples/curl/quickstart.sh
BASE_URL=http://127.0.0.1:3000 node examples/typescript/quickstart.mjs
BASE_URL=http://127.0.0.1:3000 python3 examples/python/quickstart.py
```

## 1. Discover the instance

```bash
curl -fsS "$BASE_URL/api/v3/config"
```

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

Read `ttl_options` instead of hard-coding durations: a deployment may narrow the allowlist,
and any other TTL is rejected with `422 validation_error`. `max_secret_bytes` is the body
ceiling (default 1 MiB). `auth_mode` is `disabled`, `simple`, or `full` (full answers `501`).

## 2. Create a secret

```bash
curl -fsS -X POST "$BASE_URL/api/v3/guest/conceal" \
  -H 'content-type: application/json' \
  -d '{"secret":"correct horse battery staple","ttl":1800}'
```

```json
{
  "secret_key": "Hk3v9QpL2mR8sT4uW6xY1a",
  "receipt": {
    "identifier": "Hk3v9QpL2mR8sT4uW6xY1a",
    "secret_ttl": 1800,
    "passphrase_required": false,
    "kind": "text"
  },
  "links": { "secret": "/secret/Hk3v9QpL2mR8sT4uW6xY1a" }
}
```

The key is opaque (≥128 bits from a CSPRNG). The plaintext is encrypted with AES-256-GCM
under the instance `SECRET` before it is stored; never log the request body. The v1
equivalent is `POST /api/v1/share` with form fields `secret`, `ttl`, `passphrase` and a
legacy response shape — use v3 for new integrations.

## 2b. File secrets (v3)

Files travel as strict base64 inside the same JSON envelope. Read `max_file_bytes` from
`GET /api/v3/config` (512 KiB by default) before reading a file into memory.

```sh
PAYLOAD=$(base64 -w0 ./notes.bin)
curl -sS -X POST http://localhost:3000/api/v3/guest/conceal \
  -H 'content-type: application/json' \
  -d "{\"secret\":\"$PAYLOAD\",\"ttl\":1800,\"kind\":\"file\",\"filename\":\"notes.bin\"}"
```

```ts
export async function concealFile(baseUrl: string, file: File): Promise<string> {
  const bytes = new Uint8Array(await file.arrayBuffer());
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  const res = await fetch(`${baseUrl}/api/v3/guest/conceal`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ secret: btoa(binary), ttl: 86400, kind: "file", filename: file.name }),
  });
  if (!res.ok) throw new Error(`file conceal failed: ${res.status}`);
  const body = (await res.json()) as { links: { secret: string } };
  return new URL(body.links.secret, baseUrl).toString();
}
```

A reveal of a file returns `secret_value` as base64 with `metadata.kind === "file"` and
`metadata.filename` set. Decode before writing it to disk. The filename is metadata only —
never build a destination path from an untrusted string without sanitising it.

## 3. Preview, then reveal (the contract that matters)

`GET` is a **preview**. It returns metadata only and never consumes the secret, so chat
clients and link scanners cannot destroy it:

```bash
curl -fsS "$BASE_URL/api/v3/guest/secret/$KEY"
# {"passphrase_required":false,"metadata":{"kind":"text","filename":null,
#  "created_at":1762819200,"ttl":1800}}
```

`POST …/reveal` is the **only consuming route**:

```bash
curl -fsS -X POST "$BASE_URL/api/v3/guest/secret/$KEY/reveal" \
  -H 'content-type: application/json' -d '{}'
# {"secret_value":"correct horse battery staple","metadata":{...}}

curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  "$BASE_URL/api/v3/guest/secret/$KEY/reveal" -H 'content-type: application/json' -d '{}'
# 404
```

Exactly one concurrent reveal wins: the consume is an atomic Redis compare-and-delete of
the exact serialized record, and there is an 8-way race spec proving one `200` and seven
`404`s. A preview never decrypts, so a rotated `SECRET` turns a reveal into an error without
destroying the record. Do **not** use v1 `GET /api/v1/secret/:key` from automation: that
frozen legacy route consumes.

## 4. Passphrase-protected secrets

A passphrase is an extra **access gate**, not a second encryption key: the server holds the
instance key and can decrypt. Do not describe this as zero-knowledge (decision D-012).

```bash
# create: 8–256 bytes; absent/empty means no passphrase
curl -fsS -X POST "$BASE_URL/api/v3/guest/conceal" -H 'content-type: application/json' \
  -d '{"secret":"api key","ttl":1800,"passphrase":"correct horse"}'

curl -fsS "$BASE_URL/api/v3/guest/secret/$KEY"
# {"passphrase_required":true,"metadata":{...}}   -- no content

curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  "$BASE_URL/api/v3/guest/secret/$KEY/reveal" -H 'content-type: application/json' -d '{}'
# 401, code "passphrase_required"; secret NOT consumed

curl -fsS -X POST "$BASE_URL/api/v3/guest/secret/$KEY/reveal" \
  -H 'content-type: application/json' -d '{"passphrase":"wrong"}'
# 401, code "invalid_passphrase"; secret NOT consumed

curl -fsS -X POST "$BASE_URL/api/v3/guest/secret/$KEY/reveal" \
  -H 'content-type: application/json' -d '{"passphrase":"correct horse"}'
# 200 with the value
```

A passphrase shorter than 8 bytes is rejected at create time with `422` and nothing is
written. Pre-existing records created before that floor still reveal with their original
passphrase.

## 5. Errors, limits and retries

Every v3 error has the same envelope; keep `request_id` when reporting a problem:

```json
{"error":{"code":"rate_limited","message":"Too many requests.","request_id":"…"}}
```

| Code | HTTP | Meaning for a client |
| --- | --- | --- |
| `validation_error` | 422 | Bad TTL, empty/oversized secret, bad passphrase length — fix the request |
| `not_found` | 404 | Unknown, expired or already-consumed — do not retry |
| `passphrase_required` / `invalid_passphrase` | 401 | Supply / correct the passphrase; the record is intact |
| `rate_limited` | 429 | Back off for `Retry-After` seconds |
| `payload_too_large` | 413 | Body over `max_secret_bytes` |
| `service_unavailable` | 503 | Redis down or full; retry after `Retry-After` |
| `internal_error` | 500 | Server fault; report with `request_id` |

Defaults: 30 conceals/minute, 60 reveals/minute, 10 sign-in attempts/minute, all in a
60-second window, keyed per client IP. `TRUSTED_PROXIES` controls whether `X-Forwarded-For`
is honored. A full datastore answers `503` rather than dropping secrets.

## 6. Accounts (simple mode only)

When `auth_mode` is `simple`, sessions are opaque cookies (`HttpOnly`, `SameSite=Lax`,
`Secure` when the site runs under TLS). Sign-up and sign-in share the sign-in rate limit;
duplicate emails return `409 email_taken`; failures are always generic `401 invalid_credentials`.

```bash
curl -fsS -c cookies.txt -X POST "$BASE_URL/api/v3/signup" -H 'content-type: application/json' \
  -d '{"email":"dev@example.com","password":"a long unique password"}'
curl -fsS -b cookies.txt "$BASE_URL/api/v3/account/me"
curl -fsS -b cookies.txt "$BASE_URL/api/v3/account/receipts"
curl -fsS -b cookies.txt -X POST "$BASE_URL/api/v3/signout" -H 'content-type: application/json' -d '{}'
```

Cookie-authenticated mutations require a same-origin proof (`Origin` matching the
configured `HOST`, or `Sec-Fetch-Site: same-origin`); plain headerless API clients without a
cookie are allowed. With `AUTH_MODE=disabled` account routes return `403`; with `full`
they return `501` — never silently fall back.

Concealing while signed in attaches an owner receipt; revealing removes it. Receipts show
metadata and a link, never the plaintext.

## 7. Language examples

- [TypeScript (Node 24 `fetch`)](../examples/typescript/quickstart.mjs) — no npm packages.
- [Python 3 (stdlib `urllib`)](../examples/python/quickstart.py) — no pip packages.
- [curl + `python3` JSON parsing](../examples/curl/quickstart.sh).

Each script creates a secret, previews it, reveals it once, asserts the second reveal is
`404`, and prints a one-line result. To check all three against a throwaway stack (Docker,
curl, python3 and node required; no container left behind):

```bash
script/test-examples.sh
```

Verified output: all three print `ok: create=… preview=no-content reveal=match replay=404`.
See `TESTING.md` for the canonical stack and spec commands.

## 8. Security notes for integrators

- Never put the secret in a URL, query string, log, or analytics event. Only the opaque key
  belongs in a link.
- Keep the instance `SECRET` out of source control; rotate with `bin/ots rotate-key`.
- Treat backups as sensitive: they contain ciphertext plus passphrase hashes and session
  digests.
- `GET` is safe for link previews; `POST …/reveal` spends the secret. v1 `GET` is the
  documented exception.
- The passphrase is not a second key; server-side compromise is a real threat (D-012).
