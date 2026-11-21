# OneShotLink crypto and single-use spec

This document describes **what the code actually does**, so a reader can check the claims
against the source and against a running instance. It is deliberately not a marketing page.
Where a property is not provided, it is listed under *What this does not claim*.

Source of truth: `lib/onetime/crypto.rb`, `lib/onetime/password.rb`, `lib/onetime/ids.rb`,
`lib/onetime/store.rb`, `lib/onetime/models/secret.rb`,
`lib/onetime/logic/{conceal,reveal}_secret.rb`, and the specs under `spec/`.

## 1. Key and identifiers

| Item | Implementation | Code |
| --- | --- | --- |
| Instance key | `SECRET`, required at boot, ≥32 bytes | `config.rb#secret!`, `validate!` |
| Data key | `HKDF-SHA256(SECRET, salt, info="ots-secret", length=32)` | `crypto.rb#derive` |
| Record ID | 16 random bytes → 128-bit URL-safe base64 (`Ids.extid`) | `ids.rb` |
| Session token | 32 random bytes → 64 hex chars (`Ids.session_token`) | `ids.rb` |
| Index keys | SHA-256 of a normalized value; raw emails never used as keys | `ids.rb#opaque_index` |

Every record gets a fresh 16-byte random salt and a fresh 96-bit random IV. The salt is
also the GCM additional authenticated data, so swapping a record's salt with another's
fails decryption.

## 2. Encryption at rest

`Crypto.encrypt` uses AES-256-GCM with a 16-byte authentication tag. The stored JSON
string contains base64 `ciphertext`, `iv`, `tag`, `salt` and the `cipher` name; it contains
no plaintext and no key. Redis holds this JSON **as a string**, not as a hash — the consume
script compares a single value atomically (§4).

Tampering with ciphertext, IV, tag or salt raises `Onetime::Error, "Stored secret failed
integrity verification"`; the record is not returned and is not deleted. `decrypt` rewrites
malformed-base64 or missing-field failures into a typed `Onetime::Error` and never echoes
the payload.

## 3. Passphrase — an access gate, not a second key

`Password.create` produces Argon2id with `t_cost: 3`, `m_cost: 16` (the gem treats this as a
log2 exponent: 2^16 KiB = 64 MiB) and `p_cost: 2`. The hash is stored in the record as
`passphrase_hash`; the plaintext passphrase is never persisted or logged. Legacy bcrypt
hashes (`$2a$`/`$2b$`/`$2y$`) still verify for customer accounts.

Create rejects a supplied passphrase shorter than 8 bytes or longer than 256 bytes with
`422 validation_error`; absent or empty means "no passphrase". Verification runs **before**
the consume, so a wrong passphrase leaves the record intact and revealable.

**Important:** the passphrase does not derive the encryption key. The server holds `SECRET`
and can decrypt any record after the gate is passed. This is a deliberate, documented
parity gap (D-012, K-21). Never call it zero-knowledge or claim the server cannot decrypt.

## 4. Single-use destruction

The `secret:object:<id>` value is deleted by a Lua script evaluated atomically in Redis:

```lua
local current = redis.call('GET', KEYS[1])
if not current then return 0 end
if current ~= ARGV[1] then return 0 end
redis.call('DEL', KEYS[1])
return 1
```

The comparison is deliberately unconditional: an empty expected value must never turn this
into an unverified delete, even if a future caller forgets the Ruby guard (SA-20).
`expected_value` is mandatory in `Store.consume`. The record bytes read, verified and
decrypted are the exact bytes compared and deleted, so an intervening mutation cannot cause
the wrong record to be destroyed. Two concurrent reveals produce one winner (`200`) and
one or more `404`s — covered by an 8-way race spec.

Reveal order is: fetch → `verify_meta!` → verify passphrase → decrypt → atomic consume → receipt/index
cleanup (D-013). A rotated or wrong `SECRET`, a corrupt record or a wrong passphrase all
fail **before** the irreversible step and leave the secret readable.

Key rotation uses a separate compare-and-swap script (`Store.rewrite_if_unchanged`) with
`SET … KEEPTTL`: a secret consumed between read and write is skipped, never resurrected
(K-42).

## 5. Expiry and destruction semantics

- The record is written with `SET … EX <ttl>`; TTL must be one of `TTL_OPTIONS`
  (defaults `1800,43200,86400,259200` seconds). Receipt hashes and owner index entries
  receive matching TTLs in the same `MULTI`, so metadata does not outlive the secret until a terminal transition; the receipt is then retained for 30 days with no payload (D-017).
- "Destroyed" means the Redis key is deleted (on reveal) or expires (on TTL). It is **not**
  cryptographic erasure: Redis AOF/RDB snapshots, backups, and filesystem snapshots taken
  while the key existed still contain the ciphertext until they age out or are deleted.
  Treat backups as sensitive.
- A full Redis (`maxmemory` at the ceiling, `noeviction`) answers `503 service_unavailable`
  with `Retry-After` instead of evicting live secrets; TTLs continue to run while storage is
  full (DEPLOYMENT.md §9).

## 6. Boundaries around the core

- Input validation in the Roda layer: TTL allowlist, `MAX_SECRET_BYTES` cap (default 1 MiB,
  both JSON and form bodies), passphrase length bounds, JSON-only v3.
- Fixed-window Redis rate limiting in one Lua call (`limiter.rb`): 30 conceals/min, 60
  reveals/min, 10 sign-ins/min by default, 60-second windows, `429` + `Retry-After`.
- `GET /api/v3/.../secret/:key` is a **non-consuming preview** with no decryption (K-35);
  `POST …/reveal` is the only consuming v3 route. The frozen v1 `GET` consumes by contract;
  `HEAD` on that route is refused with `405` (K-39).
- Sessions are opaque cookies (`HttpOnly`, `SameSite=Lax`, `Secure` under TLS); cookie
  mutations require a same-origin proof. Request logs redact secret paths and never record
  bodies, cookies or tokens.

## 7. Verify it yourself

From the repo root (Ruby runs in Docker on hosts without it):

```bash
# Crypto primitives: round-trip, fresh IV/salt, wrong key, tamper, no plaintext.
docker run --rm --network=host -v "$PWD":/app -v ots-bundle:/bundle \
  -e BUNDLE_PATH=/bundle -e REDIS_URL=redis://127.0.0.1:6399/15 -w /app \
  ots-dev bundle exec rspec spec/unit/crypto_spec.rb spec/unit/store_spec.rb \
    spec/integration/secrets_api_spec.rb

# Full suite includes the 8-way reveal race and the tamper-over-HTTP case.
docker run --rm --network=host -v "$PWD":/app -v ots-bundle:/bundle \
  -e BUNDLE_PATH=/bundle -e REDIS_URL=redis://127.0.0.1:6399/15 -w /app \
  ots-dev bundle exec rspec
```

To inspect a record yourself, create a secret against a **throwaway** Redis DB, then read
the raw value with `redis-cli GET secret:object:<key>`: you will see base64 fields and no
plaintext. The committed integration spec asserts exactly this (ciphertext-only Redis).

Executed live against a throwaway stack (2026-11-20), with `SECRET` generated at boot:

```text
GET secret:object:<id>  -> {"v":3,"meta_mac":"<hex>",...,"ciphertext":"X4VA...",
                            "iv":"67DR...","tag":"pjKH...","salt":"4E2n...","cipher":"aes-256-gcm"}
grep -c 'TAMPER_SENTINEL' over all secret:object values -> 0
flip one base64 char in ciphertext, POST .../reveal -> 500
  {"error":{"code":"internal_error","message":"Stored secret failed integrity verification",...}}
EXISTS secret:object:<id> after the failed reveal -> 1
restore the original bytes, POST .../reveal -> 200 with the exact value
```

That is the D-013 guarantee observed at runtime, not inferred from source: an integrity
failure neither leaks nor destroys the secret.

## 8. What this does not claim

- No zero-knowledge: the instance `SECRET` can decrypt every record (D-012).
- Not a zero-knowledge passphrase: the passphrase is an access gate, not a second key, and
  guessing is bounded by both the per-IP reveal limiter and a per-secret budget
  (5 guesses / 900 s, D-012b). A leaked `SECRET` plus a leaked record exposes the content.
- No forward secrecy, no per-recipient keys, no client-side encryption. Text and text-file
  secrets use the same server-side AES-256-GCM path (see API.md §5.1); there is no separate
  file-encryption primitive.
- No cryptographic erasure from backups or storage snapshots (§5).
- No distributed tracing; metrics counters are per Puma worker.
- No claim that static inspection proves runtime behavior — the specs and live requests in
  §7 are the runtime evidence.
