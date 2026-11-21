# Database (Redis)

Status: **all shipped v1 key families below are implemented (2026-11-21); rows marked Deferred (P2) are not**; Redis is the only datastore in v1 (D-003). `lib/onetime/models/secret.rb`
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
| Encryption | Payload values (`secret:object:*`, `request:secret:*`) are JSON of `Crypto.encrypt` output; metadata/account/session/limiter/audit keys carry no secret content |

Redis 7+ (or Valkey 7+). Commands used (notably): `GET`, `SET ... EX/NX/KEEPTTL`,
`DEL`, `EVAL`, `INCR`, `EXPIRE`, `ZADD`, `ZREM`, `ZRANGE`, `ZREVRANGE`, `ZSCORE`,
`HGETALL`, `HGET`, `HSET`, `SADD`, `SMEMBERS`, `SREM`, `XADD`, `XREVRANGE`, `TTL`,
`TYPE`, `EXISTS`, `PING`, `INFO`. Large scans use `SCAN` (never `KEYS`).

## 2. Key catalogue

`<objid>` = `Ids.extid` (16 random bytes, URL-safe base64, 22 chars).
`<id>` = a generated customer identifier (organizations are deferred, P2).

| Key | Type | TTL | Purpose | Status |
| --- | --- | --- | --- | --- |
| `secret:object:<objid>` | string (JSON) | `ttl` | Encrypted secret record | Implemented (T-20) |
| `secret:receipt:<objid>` | hash | `ttl`, then 30 d after reveal/burn | Non-sensitive metadata and lifecycle status | Implemented (T-20); retained per D-017 |
| `customer:<id>` | hash | none | Account record (`id`, `email`, `password_hash`, `role`, `created_at`) | Implemented (T-40) |
| `customer:index:<sha256>` | string → `<id>` | none | Email lookup/uniqueness index (hashed, never raw email) | Implemented (T-40) |
| `customer:<id>:secrets` | sorted set | sliding, ≥ longest TTL option | Owner's receipt index, score = `created_at` epoch | Implemented (T-28); reveal/burn keep the member until the index's 30-day retention expires; members whose receipt hash is gone are pruned lazily on listing (T-117) |
| `customer:<id>:requests` | sorted set | sliding, ≥ longest TTL option | Owner's incoming-request index, score = `created_at` epoch | Implemented (T-117); expires after a dormant window and any new request refreshes it |
| `session:<sha256(token)>` | hash | `SESSION_TTL` (14 d, sliding) | Server-side session (`customer_id`, `created_at`, `last_seen`) | Implemented (T-41); Redis never stores the raw token |
| `customer:sessions:<id>` | set | `SESSION_TTL` | Digest of each live session for a customer, so a password change can revoke them all | Implemented (K-34); removed on signout/revoke |
| `audit:events` | stream | `MAXLEN` ~100k | Append-only account/security events (`event`, `at`, `actor_id`, `request_id`, `ip_day`, `detail`) | Implemented (K-34, D-retention); no raw IP — `ip_day` is a 12-hex HMAC reference that rotates daily; request-link keys appear only as truncated SHA-256 references; readable with `ots audit --limit N` |
| `organization:object:<id>` | hash | none | Organization record | Deferred (P2) |
| `organization:<id>:members` | set | none | Member customer IDs + roles | Deferred (P2) |
| `customdomain:<domain>` | hash | none | Domain → org mapping + verification state | Deferred (P2) |
| `limiter:<client>:<scope>` | string (int) | window (60 s) | Rate-limit count for the window | Implemented (`lib/onetime/limiter.rb`) |
| `limiter:<client>:<scope>:counter` | string (int) | window (60 s) | Raw request counter | Implemented (`lib/onetime/limiter.rb`) |
| `schema:version` | string (int) | none | Redis schema version for migrations | Implemented (T-66) — written by `ots migrate` |
| `request:object:<key>` | string (JSON, `v=2`) | `ttl` | Inbound request metadata with an HMAC over `v owner_id label created_at ttl request_key` | Implemented (T-117, T-130); reveal verifies the MAC before trusting `owner_id` |
| `request:secret:<key>` | string (JSON, Crypto envelope) | remaining request TTL | One submitted answer, written with `SET NX` and consumed by compare-and-delete | Implemented (T-117, T-130) |
| `webhook:endpoint:<id>` | hash | none | Endpoint URL, pinned IP, events and encrypted signing secret | Implemented (T-118, T-130) |
| `webhook:owner:<id>` | sorted set | none | Owner's endpoint index, score = `created_at` | Implemented (T-118) |
| `webhook:queue` | sorted set | entries older than 7 d pruned on claim | Queued metadata-only events, score = due time | Implemented (T-118, D-queue); delivered by `bin/ots webhooks:work` |
| `webhook:delivery:<id>` | hash | 7 days | Delivery status/attempts/response code | Implemented (T-118); listing can be filtered by endpoint id |
| `webhook:seen:<id>` / `webhook:inflight:<id>:<attempt>` | string | 7 d / 120 s | Delivery deduplication and in-flight lock | Implemented (T-118); deliberately excluded from backups |

Backup format 2 (`lib/onetime/backup.rb`) exports every section above except the ephemeral
webhook dedup keys, the audit stream and session digests; format 1 files remain restorable.
Records stay JSON strings (D-004), and request objects are MAC'd with the same primitive as
secret records under a distinct domain (`ots-request-meta/v1`).

`<client>` = client IP for every HTTP scope; authenticated routes do not switch the limiter
id to `cust_<id>` (`app.rb:224-230`). For the `passphrase` scope it is the opaque secret id,
so no personal data is stored. `<scope>` is one of
`conceal`, `reveal`, `signin`, `signup`, `request`, `respond`, `webhook`, `webhook_read`,
`password`, `delete`, `burn`, `signout`, `passphrase`, `metrics`, `metrics_auth` or `meta` (all 16 in `config.rb:15-18`); each has its own `RATE_LIMIT_<SCOPE>` setting so a burst
in one flow cannot
consume another flow's budget. Limiter keys are normalized to `[a-zA-Z0-9_.:-]` and
truncated to 120 chars.

## 3. `secret:object:<objid>` — the encrypted record

Stored with **`SET key <json> EX ttl`**, i.e. a JSON **string**, because
`Store.consume` compares a single `GET` value inside Lua (D-004). Do not convert this
record to a Redis hash. The model serializes once and reuses those exact bytes for the
compare-and-delete, so a concurrent writer cannot make a reveal return a mismatched
record.

```json
{
  "v": 3,
  "meta_mac": "<hex HMAC-SHA256 over v/kind/filename/owner_id/created_at/ttl/passphrase_hash/ciphertext>",
  "cipher": "aes-256-gcm",
  "ciphertext": "<base64>",
  "iv": "<base64, 12 bytes>",
  "tag": "<base64, 16 bytes>",
  "salt": "<base64, 16 bytes>",
  "passphrase_hash": "<argon2id string; omitted when no passphrase>",
  "kind": "text" | "file",
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
- `v: 3` records carry `meta_mac`, an HMAC-SHA256 over the access-control and display fields (including `ciphertext`)
  using a key derived from `SECRET` via `Crypto.derive(SECRET, "ots-record-meta/v1")`.
  `RevealSecret` verifies it before the passphrase gate and the decrypt, so a Redis writer
  cannot strip `passphrase_hash` or rewrite `filename`/`kind`/`ttl` without detection.
  Rotation re-signs the MAC under the new key. **v3 is enforced with no legacy window:**
  a `v != 3` or missing/empty `meta_mac` record is rejected with a typed 500 and left intact,
  so a Redis writer cannot downgrade a protected secret to bypass the passphrase gate.
- `passphrase_hash` is an Argon2id hash produced by `Password.create`; the key is omitted
  when no passphrase is set. It is not encryption key material — content is always encrypted
  with the instance key.
- `kind` is `text` or `file` in v3; a `file` record carries a validated `filename` and base64 content (T-116).
- `owner_id` is set only for authenticated creation.
- The JSON is serialized once by the model and reused verbatim for the compare-and-delete
  step.
- On reveal or burn the model **finalizes** the receipt (`revealed`/`burned`, 30-day TTL)
  **after** the atomic consume succeeds. Neither a failed passphrase nor a failed decryption
  deletes anything: both run before the consume. Finalization is best-effort and cannot turn
  a spent secret into a 5xx.

**Never** add the plaintext, passphrase, decrypted length, or any derived plaintext
fingerprint to this record.

## 4. `secret:receipt:<objid>` — metadata

Hash. TTL is the secret's TTL until a terminal transition, then **30 days** (D-017).

| Field | Meaning |
| --- | --- |
| `identifier` | The `objid` (same as the URL key) |
| `owner_id` | Customer ID or empty for guests |
| `created_at` | Unix seconds |
| `ttl` | Original TTL in seconds |
| `kind` | `text` |
| `passphrase` | `1`/`0` — whether a gate was set, never the passphrase itself |
| `status` | `new → previewed → revealed → burned` (Lua compare-and-set; terminal states never downgrade) |
| `viewed` | `0` until a terminal transition, then `1` |
| `previewed_at` / `revealed_at` / `burned_at` | Unix seconds for the transition that occurred |

Receipts are created for every secret so owner listings are possible without touching
ciphertext. Reveal and burn permanently delete `secret:object:*` with the same atomic
compare-and-delete; only non-sensitive metadata survives for 30 days, then Redis expires it.
The owner `zset` carries the same 30-day TTL and stale members are pruned lazily by the
receipts listing. A wrong passphrase, a failed MAC check or a failed decryption runs before
the consume and leaves both keys untouched. The receipt never contains plaintext, a
passphrase, ciphertext, or an encryption key (D-017).

## 5. Accounts (simple mode)

`customer:<id>` hash:

| Field | Meaning |
| --- | --- |
| `id`, `email`, `role` | Opaque id; normalized email; currently `customer` and no admin role is enforced |
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
3. `secret:object:*` and its receipt share the same TTL (±1 s) at creation, so metadata does not outlive the secret. On a terminal transition both get a 30-day retention TTL (D-017). Both are written in one `MULTI`.
4. A reveal deletes the secret key and marks the receipt terminal; the receipt keeps only
   non-sensitive metadata for 30 days. A failed passphrase **or a record that cannot be
   decrypted** deletes nothing (decrypt runs before the consume — D-013).
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
- `bin/ots backup` exports exclude session digests, audit, limiter and webhook dedup keys (`backup.rb:39`). A raw Redis AOF/RDB snapshot is a broader artifact: treat it as sensitive (ciphertext, passphrase hashes, live session digests) and encrypt it at rest. Rotating `SECRET` does not invalidate sessions, so flush `customer:sessions:*` if such a snapshot leaks.

## 8. Migrations (T-66, implemented)

`Onetime::Migrate` (`lib/onetime/migrate.rb`) owns `schema:version`. The operator runs it
with the CLI; it is safe to run on a live instance and safe to re-run:

```sh
docker compose exec web ruby bin/ots migrate --dry-run   # report planned steps, no writes
docker compose exec web ruby bin/ots migrate             # apply pending steps
```

`current_version` treats a missing key as 0 and rejects a non-integer value; `dry_run`
performs no writes; `apply!` stamps version 1 with `SET NX` (so concurrent runners cannot
double-apply) and refuses to run against a newer schema version rather than downgrading it.
The initial schema has no data to reshape, so the marker is the whole step.

When record shapes change later:

1. Add the next ordered step to `Onetime::Migrate::STEPS` and increment `TARGET_VERSION`.
2. Make each step idempotent and safe while old records exist (expand → backfill →
   contract); never rewrite a `secret:object` value in place without preserving its exact
   serialization, because `Store.consume` compares those bytes for in-flight reveals.
3. Keep the old read path for one release and re-run the dry-run/apply pair through the
   operator CLI. Migrations are operator-run; an agent run never applies them to a live
   instance.

Verified: `spec/unit/migration_spec.rb` (6 examples) and a live CLI run against a scratch Redis DB (never a shared one)
(dry-run → no marker, apply → `1`, re-apply → nothing applied).

## 9. Full mode (not implemented)

PostgreSQL 17 + RabbitMQ 4.3 appear in the brief for Rodauth accounts and background
jobs. They are **not** part of v1 and no schema exists. The Redis layout above stays the
same for secrets even if relational accounts land later, so secret data does not need a
second migration.
