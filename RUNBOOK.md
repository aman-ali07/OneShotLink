# Incident runbook

Procedures for the failure modes that actually take this service down or compromise
it. Each entry states the **symptom**, the **signal** you would see, the **first
response**, and the **recovery**. Keep this file current when behaviour changes; do not
describe steps that have not been tried (the ones marked *verified* were).

Operators should also read [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md) and
[DEPLOYMENT.md](DEPLOYMENT.md).

---

## 0. Orientation

| Thing | Where |
| --- | --- |
| Health check | `GET /health` → `200 {"status":"ok"}` or `503 {"status":"degraded"}` |
| CLI | `ruby bin/ots <command>` inside the `web` container |
| Audit log | Redis stream `audit:events` (`ruby bin/ots health` shows overall state) |
| Config validation | boot fails closed; `Config.validate!` runs in `config.ru` |

The CLI is packaged into the image at `/app/bin/ots`. Run it inside the running
container:

```sh
docker compose exec web ruby bin/ots health
docker compose exec web ruby bin/ots customers list
```

---

## 1. Instance key (`SECRET`) suspected compromised

**Symptom:** the 32-byte `SECRET` may have leaked (env dump, image, secret manager
audit, accidental commit).

**Impact:** anyone with the key and read access to Redis can decrypt live secrets.

**First response:**

1. Treat every stored secret as potentially disclosed. Reveal nothing further until
   rotation is planned.
2. Rotate the key (this is **non-destructive** to the data — verified):

   ```sh
   NEW=$(openssl rand -hex 32)
   # Re-encrypt all stored secrets under the new key, preserving TTLs.
   docker compose exec -e OTS_NEW_SECRET="$NEW" web ruby bin/ots rotate-key
   ```

   The CLI prints `Re-encrypted N secret(s) with the new key.` and then reminds you to
   update `SECRET`. **Do that before restarting** — the rotation is already applied to the
   data, so a web process still holding the old key cannot read it:

   ```sh
   # .env (or your secret manager), not the shell alone: `compose up` re-reads the file
   SECRET=$NEW docker compose up -d --force-recreate web
   ```

3. Anything the old key could already have decrypted stays compromised. Rotation
   protects secrets **at rest going forward**, not past exposure.

**Verification that rotation worked:** a secret created before rotation must still
reveal after restart; and the old key must no longer decrypt
(`spec/unit/ops_spec.rb` asserts both directions).

**Drilled 2026-11-12** through Compose with two secrets (one passphrase-protected):
`rotate-key` reported `Re-encrypted 2 secret(s)`. Restarting with the **old** key answers
`500 {"code":"internal_error","message":"Stored secret failed integrity verification"}`
and **both records are still in Redis** — the decrypt-before-consume rule (D-013) means a
half-done rotation costs nothing: set the correct key, restart, and both secrets reveal
`200` (the passphrase gate still enforced). That is also why skipping the `SECRET` update
is recoverable rather than destructive.

---

## 2. Redis lost or corrupted

**Symptom:** `/health` returns `503` with `"redis":"error"`, or Redis restarted from an
empty dataset.

**Impact:** with Redis gone, **every live secret is gone**. A one-time secret service
has no second copy by design; this is data loss for the period since the last backup.

**First response:**

1. Confirm Redis state. Auth is mandatory, so an unauthenticated `redis-cli` answers
   `NOAUTH Authentication required.` **and still exits 0** — do not read that as "0 keys":

   ```sh
   docker compose exec redis sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning DBSIZE'
   ```
2. Restore the most recent backup into a clean Redis (verified):

   ```sh
   docker compose exec web ruby bin/ots restore --in /backups/dump.json
   ```

3. The service resumes normal operation once `/health` returns `200`.

**RPO / RTO (measured 2026-11-11, single host):** a restore-into-clean-volume drill was
run end to end. With 81 stored secrets, `bin/ots backup` took **1.5 s**, a full
`docker compose down -v` + `up` took **10.5 s** to `/health = 200`, and `bin/ots restore`
took **1.7 s** — a **total RTO of ~12.4 s**. A sentinel secret was confirmed `404` while the
volume was gone and returned its value with its TTL preserved after the restore. These
are local figures; expect more on a remote host. RPO is set by your backup interval —
back up more often than your shortest TTL. A secret whose TTL expired during the outage
is correctly absent after restore (its `ttl` is preserved in the export).

**Backups never contain plaintext.** They are ciphertext under the instance `SECRET`,
so a stolen backup is useless without the key — and a restore requires the current key.

---

## 2b. Redis is up but full (memory ceiling)

**Symptom:** `/health` returns `200 {"status":"ok","redis":"ok"}` — Redis answers `PING`
fine — but creates and reveals answer `503 service_unavailable` with `Retry-After`. The web
log shows `OOM command not allowed when used memory > 'maxmemory'.`

**Impact:** nothing is lost, but writes **and** reveals are refused because the atomic
consume is a Lua `EVAL` and Redis will not run it at the ceiling. TTLs keep running while
storage is full, so a secret can expire before you free space — this is the reason the
ratio alert exists (DEPLOYMENT.md §5.1).

**First response:**

1. Confirm the ceiling:
   `docker compose exec redis sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning info memory'`
   — `used_memory_human` at or above `maxmemory_human`.
2. Raise the ceiling (`docker compose` reads `REDIS_MAXMEMORY`; a runtime change works
   until the next restart):
   `docker compose exec redis sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning config set maxmemory 512mb'`
3. Then find out why: is `REDIS_MAXMEMORY` below the working set, or is `TTL_OPTIONS`
   offering long TTLs with 1 MiB secrets? Fix the setting, not the data.
4. Do **not** lower `maxmemory` to force evictions: the policy is `noeviction` on purpose,
   and evicting a live secret would destroy it silently.

**Verified 2026-11-12** on a 6 MB ceiling: the write that crossed it got `503` +
`Retry-After: 5`, reveals answered `503` while full, and once `maxmemory` was raised the
secrets stored before the ceiling revealed `200` with their full contents.

---

## 3. Atomic reveal regression suspected (a secret shown twice)

**Symptom:** a secret may have been revealed more than once.

**This must never happen.** The invariant is a compare-and-delete Lua script in
`Onetime::Store.consume`; two concurrent reveals race there and exactly one wins.

**Verify under load (runs the real invariant):**

```sh
docker run --rm --network=host -v "$PWD":/app -w /app \
  -e BASE_URL=http://127.0.0.1:3000 ruby:3.3-slim ruby script/loadtest.rb 200 20
```

It creates secrets, then races 8 concurrent reveals per secret and fails if any secret
has a reveal count other than 1. Last verified: 400 secrets, 40 threads, **0 double
reveals**.

If it ever fails, **do not patch the comparison to "make it pass."** Reverting to
read-then-delete is a security regression (see `AGENTS.md`, prohibited actions). Fix the
Lua path, add a failing spec first, and re-run the load test.

---

## 4. Rate-limit lockout (a legitimate client is blocked)

**Symptom:** a client gets `429` with `Retry-After`; `X-RateLimit-Remaining: 0`.

**Response:** the fixed-window counter lives at `limiter:<client>:<scope>` plus a
`…:counter` companion. Find the key first — the `<client>` part is the client IP only when
`TRUST_PROXY=true` and the peer is in `TRUSTED_PROXIES`; otherwise it is the direct peer
(the proxy or the Docker gateway, e.g. `172.x`):

```sh
docker compose exec redis sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning keys "limiter:*"'
```

Then clear both keys for that client only (**authentication is required** — an
unauthenticated `redis-cli` prints `NOAUTH` *and exits 0*, so a script that ignores output
would think it succeeded):

```sh
docker compose exec redis sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning DEL "limiter:<client>:reveal" "limiter:<client>:reveal:counter"'
```

**Verified 2026-11-12** with `RATE_LIMIT_CONCEAL=2`: two `201`s then a `429`, keys
`limiter:172.22.0.1:conceal` and `…:conceal:counter`, and after deleting both the next
request answered `201` again.

Do not raise the global limits for one incident unless the limit itself is wrong; a
raised ceiling widens the abuse window for everyone. Adjust
`RATE_LIMIT_CONCEAL`/`RATE_LIMIT_REVEAL` deliberately and record why.

---

## 5. Full auth mode requested

**Symptom:** a client sets `AUTH_MODE=full` and expects Rodauth features.

**Response:** this deployment returns `501 not_configured`. Full mode is intentionally
unimplemented (decision D-003) and must fail closed, never silently fall back to simple
mode. Point the requester at `docs/DECISIONS.md` D-003 and the `T-60` task.

---

## 6. Rollback

1. Deployments are immutable images; roll back by pinning the previous tag:
   ```sh
   docker compose down
   docker pull <registry>/<image>:<previous-tag> && docker compose up -d
   ```
2. Data is backward compatible across patch releases (the record has a `"v"` field).
   A rollback never requires a Redis migration today; if a schema change adds one, this
   section must be updated before that release.
3. Re-run the lifecycle smoke test and the load test after any rollback.

---

## 7. What to check first for any "site down"

```sh
docker compose ps                         # both services Up/healthy?
docker compose exec web ruby bin/ots health   # config + redis + key count
curl -sS localhost:3000/health            # 200 ok / 503 degraded
docker compose logs --tail=100 web        # redacted request log, no secret values
```

Logs never contain secret plaintext, passphrases, ciphertext, tokens, or cookies; they
carry request ids, paths (secret keys redacted), status, and duration.
