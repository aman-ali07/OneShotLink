# Database (Redis)

Status: **secret keys implemented (M1, 2026-11-11).** `lib/onetime/models/secret.rb`
writes the encrypted object and receipt in one `MULTI`; integration specs assert the
TTL, ciphertext-only storage, and deletion on reveal. Simple-mode customer and session
keys are implemented (M3). Redis is the only datastore in v1; PostgreSQL is not used (see
[docs/DECISIONS.md](docs/DECISIONS.md) D-003).

## 1. Topology

| Item | Value |
| --- | --- |
| App database | `REDIS_URL` (default `redis://127.0.0.1:6379/0`) |
| Test database | DB **15** only; `spec_helper` must `FLUSHDB` it, never `FLUSHALL` |
| Persistence | AOF (`appendonly yes`) in Compose; Redis is the system of record |
| Eviction | `noeviction` recommended — a secret must never be silently evicted before TTL |
| Encryption | All values are JSON of `Crypto.encrypt` output; no plaintext at rest |

Redis 7+ (or Valkey 7+). Commands used: `GET`, `SET ... EX`, `DEL`, `EVAL`, `INCR`,
`EXPIRE`, `ZADD`, `ZREM`, `ZRANGE`, `HGETALL`, `HSET`, `SADD`, `SISMEMBER`, `TTL`.

## 2. Key catalogue

`<objid>` = `Ids.extid` (16 random bytes, URL-safe base64, 22 chars).
`<id>` = a generated customer/org identifier (also opaque).

| Key | Type | TTL | Purpose | Status |
| --- | --- | --- | --- | --- |
| `secret:object:<objid>` | string (JSON) | `ttl` | Encrypted secret record | Implemented (T-20) |
| `secret:receipt:<objid>` | hash | `ttl` | Non-sensitive metadata for the owner | Implemented (T-20); deleted on reveal |
| `customer:<id>` | hash | none | Account record (`id`, `email`, `password_hash`, `role`, `created_at`) | Implemented (T-40) |
| `customer:index:<sha256>` | string → `<id>` | none | Email lookup/uniqueness index (hashed, never raw email) | Implemented (T-40) |
| `customer:<id>:secrets` | sorted set | none | Owner's receipt index, score = `created_at` epoch | Implemented (T-28); reveal removes the member |
| `session:<sha256(token)>` | hash | `SESSION_TTL` (14 d, sliding) | Server-side session (`customer_id`, `created_at`, `last_seen`) | Implemented (T-41); Redis never stores the raw token |
| `customer:sessions:<id>` | set | `SESSION_TTL` | Digest of each live session for a customer, so a password change can revoke them all | Implemented (K-34); removed on signout/revoke |
| `audit:events` | stream | `MAXLEN` ~100k | Append-only account/security events (`event`, `at`, `actor_id`, `request_id`, `ip`, `detail`) | Implemented (K-34) |
| `organization:object:<id>` | hash | none | Organization record | Deferred (P2) |
| `organization:<id>:members` | set | none | Member customer IDs + roles | Deferred (P2) |
| `customdomain:<domain>` | hash | none | Domain → org mapping + verification state | Deferred (P2) |
| `limiter:<client>:<scope>` | string (int) | window (60 s) | Rate-limit count for the window | Implemented (`lib/onetime/limiter.rb`) |
| `limiter:<client>:<scope>:counter` | string (int) | window (60 s) | Raw request counter | Implemented (`lib/onetime/limiter.rb`) |
| `schema:version` | string (int) | none | Redis schema version for migrations | Planned (T-66) |

`<client>` = client IP, or `cust_<id>` when authenticated. `<scope>` = `conceal` or
`reveal`. Limiter keys are normalized to `[a-zA-Z0-9_.:-]` and truncated to 120 chars.

## 3. `secret:object:<objid>` — the encrypted record

Stored with **`SET key <json> EX ttl`**, i.e. a JSON **string**, because
`Store.consume` compares a single `GET` value inside Lua (D-004). Do not convert this
record to a Redis hash. The model serializes once and reuses those exact bytes for the
compare-and-delete, so a concurrent writer cannot make a reveal return a mismatched
record.

```json
{
  "v": 1,
  "cipher": "aes-256-gcm",
  "ciphertext": "<base64>",
  "iv": "<base64, 12 bytes>",
  "tag": "<base64, 16 bytes>",
  "salt": "<base64, 16 bytes>",
  "passphrase_hash": "<argon2id string; omitted when no passphrase>",
  "kind": "text",
  "filename": null,
  "owner_id": "<customer id or null>",
  "org_id": null,
  "created_at": 1762819200,
  "ttl": 86400
}
```

- `ciphertext`/`iv`/`tag`/`salt`/`cipher` are exactly the hash returned by
  `Crypto.encrypt` (implemented in `lib/onetime/crypto.rb`). The per-record `salt` is
  random; the AEAD `auth_data` is that salt. A wrong `SECRET` or tampering makes
  `Crypto.decrypt` raise, never return partial data.
- `passphrase_hash` is an Argon2id hash produced by `Password.create`; the key is omitted
  when no passphrase is set. It is not encryption key material — content is always encrypted
  with the instance key.
- `kind` is `text` in v1 (`password`/`file` reserved). `filename` is reserved for file
  secrets.
- `owner_id` is set only for authenticated creation.
- The JSON is serialized once by the model and reused verbatim for the compare-and-delete
  step.
- On reveal the model deletes the receipt and removes the owner-index entry **after** the
  atomic consume succeeds. Neither a failed passphrase nor a failed decryption deletes
  anything: both run before the consume.

**Never** add the plaintext, passphrase, decrypted length, or any derived plaintext
fingerprint to this record.

## 4. `secret:receipt:<objid>` — metadata

Hash, same TTL as the secret:

| Field | Meaning |
| --- | --- |
| `identifier` | The `objid` (same as the URL key) |
| `owner_id` | Customer ID or empty for guests |
| `created_at` | Unix seconds |
| `ttl` | Original TTL in seconds |
| `kind` | `text` |
| `passphrase` | `1`/`0` |
| `viewed` | `0` until consumed; the receipt is deleted on reveal |
| `viewed_at` | Reserved; v1 deletes the receipt on reveal instead of retaining it |

Receipts are created for every secret so weekly/owner listings are possible without
touching ciphertext. A receipt without its secret is harmless and expires; listings drop
it lazily. v1 deletes both keys on a successful reveal and keeps both on a wrong
passphrase.

## 5. Accounts (simple mode)

`customer:<id>` hash:

| Field | Meaning |
| --- | --- |
| `id`, `email`, `role` | Opaque id; normalized email; currently `customer` (colonel is reserved) |
| `password_hash` | Argon2id (`$argon2id$...`); legacy bcrypt verified then rehashed on login |
| `created_at` | Unix seconds |

- Email is stored for display and login; the **index key** is
  `customer:index:<sha256(lowercased email)>` (see `Ids.opaque_index`), so raw emails are
  never part of a Redis key.
- Duplicate signup is rejected atomically by a Lua script that checks the index and
  writes both keys in one step.
- `session:<sha256(token)>` stores `{customer_id, created_at, last_seen}` with
  `EX SESSION_TTL`. The cookie carries the raw token; Redis stores only its digest.
  Sliding expiry refreshes on each authenticated request. Signout deletes the key.
- Owner receipts are pruned lazily: a listed zset member with no receipt hash is removed.
- Account deletion reads the receipt zset and the session set, then removes the receipts,
  the owner index, every session record, the session index, the email index and the
  customer record in a single `MULTI`/`EXEC` (`Logic::DeleteAccount`). A crash cannot leave
  a half-deleted account. Secrets still inside their TTL are left to expire.

## 6. Invariants

1. No plaintext, passphrase, or decoded content is ever written to Redis.
2. Every user-visible key is ≥128 bits of CSPRNG output; no sequential IDs.
3. `secret:object:*` and its receipt share the same TTL (±1 s) so metadata does not
   outlive the secret. Both are written in one `MULTI`.
4. A reveal deletes the secret key and the receipt; a failed passphrase **or a record that
   cannot be decrypted** deletes nothing (decrypt runs before the consume — D-013).
5. `GET`+`DEL` for a reveal is prohibited — only `Store.consume` (Lua compare-and-delete).
6. Data written under one `SECRET` is undecryptable under another; `bin/ots rotate-key`
   re-encrypts existing records under a new key and preserves their TTL (T-65).
7. Account deletion is one transaction: either every account key is gone or none is (§5).

## 7. Expiry, memory, and operations

- Redis TTL is authoritative; there is no sweeper in v1.
- Memory per secret ≈ ciphertext + ~350 bytes overhead. A 1 MiB secret costs ~1 MiB until
  expiry; operators should cap ingress (NFR-2) and monitor `used_memory`.
- Recommended Redis settings: `maxmemory-policy noeviction`, AOF `everysec`, and a
  filesystem with enough headroom for the rewrite.
- Backups: AOF/RDB snapshots contain ciphertext only, but they also contain passphrase
  hashes and session tokens — treat backups as sensitive and encrypt them at rest.
- Sessions in a backup can be replayed until they expire; rotate `SECRET` does not
  invalidate sessions, so flush `session:*` if a backup leaks.

## 8. Migrations (planned, T-66)

Until the first release there is no data, so v1 can simply write `schema:version = 1`.
When shapes change:

1. Increment `schema:version`.
2. Ship idempotent scripts under `lib/tasks/migrations/` that can run while old records
   exist (expand → backfill → contract).
3. Never rewrite `secret:object` records in place without preserving their exact
   serialization for in-flight reveals; deploy during low traffic and keep the old read
   path for one release.

## 9. Full mode (not implemented)

PostgreSQL 17 + RabbitMQ 4.3 appear in the brief for Rodauth accounts and background
jobs. They are **not** part of v1 and no schema exists. The Redis layout above stays the
same for secrets even if relational accounts land later, so secret data does not need a
second migration.
