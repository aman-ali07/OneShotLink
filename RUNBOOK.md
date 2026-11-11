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
   # Then set SECRET=$NEW in the environment/secret manager and restart the web service.
   docker compose up -d --force-recreate web
   ```

3. Anything the old key could already have decrypted stays compromised. Rotation
   protects secrets **at rest going forward**, not past exposure.

**Verification that rotation worked:** a secret created before rotation must still
reveal after restart; and the old key must no longer decrypt
(`spec/unit/ops_spec.rb` asserts both directions).

---

## 2. Redis lost or corrupted

**Symptom:** `/health` returns `503` with `"redis":"error"`, or Redis restarted from an
empty dataset.

**Impact:** with Redis gone, **every live secret is gone**. A one-time secret service
has no second copy by design; this is data loss for the period since the last backup.

**First response:**

1. Confirm Redis state: `docker compose exec redis redis-cli DBSIZE`.
2. Restore the most recent backup into a clean Redis (verified):

   ```sh
   docker compose exec web ruby bin/ots restore --in /backups/dump.json
   ```

3. The service resumes normal operation once `/health` returns `200`.

**RPO / RTO (target, not a guarantee):** back up on a schedule shorter than your
longest TTL — with a 1-hour AOF and hourly `bin/ots backup`, RPO ≈ 1 hour and RTO ≈
time to restore the dump plus one web restart. A secret whose TTL expired during the
outage is correctly absent after restore (its `ttl` is preserved in the export).

**Backups never contain plaintext.** They are ciphertext under the instance `SECRET`,
so a stolen backup is useless without the key — and a restore requires the current key.

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

**Response:** the fixed-window counter lives at `limiter:<client>:<scope>`. Clear it for
that client only:

```sh
docker compose exec redis redis-cli DEL "limiter:<client-ip>:reveal" "limiter:<client-ip>:reveal:counter"
```

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
