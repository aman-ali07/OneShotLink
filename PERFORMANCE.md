# OneShotLink — Performance findings (pre-release audit)

**Date:** 2026-11-21
**Role:** independent pre-release performance/load audit
**Target:** local staging stack `http://127.0.0.1:3100`, Puma 7.2.3 / Ruby 3.3 /
`AUTH_MODE=simple`, `WEB_CONCURRENCY=0` (1 process, 1–5 threads), app Redis on `127.0.0.1:6431`
DB 15. No public host was used; no production data or credentials were touched.

## 1. Method and evidence standard

An independent performance specialist measured the running stack with Python `http.client`
samples from distinct loopback source addresses (`127.0.0.X`) so the default per-IP rate limits
(30 conceal / 60 reveal per minute) would not skew results; X-Forwarded-* is not trusted on this
stack, which was verified (`X-RateLimit-Remaining` stayed independent per source IP). Redis was
inspected with `INFO`, `SLOWLOG`, `MEMORY USAGE`, `SCAN` and command statistics. Scripts lived in
`/tmp`, never in the repo; no `FLUSHALL` and no DB other than the app's DB 15 was used.

The main agent independently spot-checked the headline figures with `curl` (`%{time_total}`):
10 `/api/v3/health` samples gave 5.6–16.4 ms (median ≈11 ms); 5 real conceals (status `201`,
`ttl=1800`) gave 9.5–15.7 ms; 3 passphrase conceals gave 651/731/1026 ms; the hashed JS asset is
253,742 B on the wire with no `Content-Encoding` and 80,967 B gzipped. These agree with the
specialist's dataset below.

## 2. Measured latency

| Path | n | p50 | p95 | p99 | Notes |
| --- | ---: | ---: | ---: | ---: | --- |
| `GET /api/v3/health` | 120 | 10.49 ms | 20.87 ms | 25.78 ms | meta limiter + Redis PING |
| `GET /api/v3/health`, 5 threads | 120 | 23.90 ms | 47.23 ms | 61.80 ms | ~2.3× single-thread |
| `GET /api/v3/config` | 120 | 6.71 ms | 12.60 ms | 17.12 ms | |
| `GET /` (SPA shell) | 60 | 2.81 ms | 5.95 ms | 7.01 ms | |
| `GET /assets/index-*.css` | 10 | 3.11 ms | 5.09 ms | 5.09 ms | 22.9 kB |
| `GET /assets/index-*.js` | 10 | 7.13 ms | 20.83 ms | 20.83 ms | 253.7 kB |
| `POST /api/v3/guest/conceal` | 150 | 11.00 ms | 21.26 ms | 26.09 ms | no passphrase |
| `POST /api/v3/guest/conceal` **with passphrase** | 60 | **573.69 ms** | **779.80 ms** | **931.44 ms** | Argon2id create |
| `GET /api/v3/guest/secret/:key` (preview) | 120 | 8.38 ms | 14.59 ms | 18.17 ms | non-consuming |
| preview, 5 threads | 120 | 32.38 ms | 62.97 ms | 87.01 ms | ~3.9× single-thread |
| `POST .../reveal` (no passphrase) | 120 | 11.99 ms | 18.49 ms | 22.50 ms | |
| `POST .../reveal` **correct passphrase** | 40 | **639.86 ms** | **1176.91 ms** | **1535.83 ms** | Argon2id verify |
| `POST .../reveal` **wrong passphrase** | 30 | 544.37 ms | 777.77 ms | 1070.34 ms | 401, secret preserved |
| `GET /api/v3/account/receipts` (50 receipts) | 40 | 53.4 ms | 101.2 ms | 114.2 ms | ~52 `HGETALL`/request |
| `GET /api/v3/account/me` | 40 | 17.0 ms | 33.5 ms | — | baseline |
| `POST` owned conceal (session) | 50 | 17.3 ms | 59.0 ms | — | +6 ms vs guest |

Argon2id (`lib/onetime/password.rb:12`, `t=3`, `m_cost=16` = 64 MiB, `p=2`) is **52–53×** the
cost of the same path without a passphrase. Under 1/5/10 concurrent correct-passphrase reveals
the measured wall throughput stayed flat at **1.9 / 2.1 / 1.7 req/s** while p50 rose from 511 ms
to 5,580 ms — extra concurrency becomes queueing, not throughput. This is a security parameter
and a capacity fact, **not** a bug: verification must stay before the atomic consume.

## 3. Redis / datastore measurements

- Redis 7.4.12, `used_memory` 1.76 MiB → 4.94 MiB after ~600 probe secrets; 416 → 1,782 keys,
  331 → 1,668 with TTLs; `maxmemory 0`, `noeviction`, AOF **off** on this dev stack.
- **`SLOWLOG LEN = 0` at every check** (10 ms threshold, 128 entries) — no single Redis command
  exceeded 10 ms, including 1 MiB values.
- Command costs (µs/call): `eval` 93.58 (5,188 calls, the limiter's single Lua script),
  `hgetall` 19.38, `xadd` 37.81, `scan` 14.22, `exec` 51.31, `ping` 1.92. The limiter is **not**
  the bottleneck.
- TTL hygiene works: receipts outlive objects by design (486 vs 202 keys at one snapshot) and
  owner zsets had positive TTLs. No-TTL keys are `customer:*`, `customer:index:*`,
  `webhook:endpoint:*`, `webhook:owner:*` — intentional persistence, but unbounded growth.
- A 1 MiB text secret measured `STRLEN 1,398,414` / `MEMORY USAGE 1,572,944` bytes (base64 +
  JSON + Redis overhead), so `DATABASE.md`'s "~1 MiB + ~350 B" estimate understates large records.

## 4. Verified limits and body behavior

| Case | Result |
| --- | --- |
| 1,048,576-byte text secret | `201`, 73.4 ms, no Redis command over 10 ms |
| 1,048,577 bytes (declared and chunked) | `413 payload_too_large` both ways |
| 512 KiB decoded file (~699 kB base64) | `201`, 77.8 ms |
| 512 KiB + 1 byte | `413` |
| 200-level nested JSON | `422` (no 500, no DoS) |
| 31st conceal from one source IP | `429` + `Retry-After`, 12.3 ms |

The documented 1 MiB text / 512 KiB file / 30-per-minute limits hold locally.

## 5. Ranked bottlenecks and disposition

| # | Bottleneck | Evidence | Disposition |
| --- | --- | --- | --- |
| 1 | Argon2id `t=3/64 MiB/p=2` | 573–640 ms p50, ~2 req/s flat | **Documented capacity trade-off.** Do not lower parameters or move verification after consume; needs a product decision before any change |
| 2 | Receipt listing N+1 (`app.rb:557-575`) | ~52 `HGETALL`/request, 53.4 ms p50 with 50 receipts | **Proposed, not applied** — `app.rb` is a protected path |
| 3 | No static compression | 253,742 → 80,967 B JS (−68%), 22,946 → 5,590 B CSS (−76%) | **Operator/proxy action** or thin Rack middleware (protected `config.ru`); no cache-header change needed |
| 4 | `Webhook.emit` did two sequential Redis round trips on the hot path | +51 `ZREMRANGEBYSCORE` and +51 `ZRANGE` over 50 owned conceals | **Fixed this audit** — both commands now run in one `pipelined` block (`webhook.rb`); spec asserts the batch and the full webhook suite (15 examples) is green |
| 5 | Session touch on every authenticated request | ~1 `EVAL` + 2 `HGETALL` + writes; `account/me` 17 ms vs `config` 6.7 ms | Required for sliding TTL; accepted |
| 6 | Audit `XADD ... MAXLEN 100000` per reveal/guess | 494 calls, 37.8 µs/call | Keep — dropping it weakens the security record |
| 7 | `Webhook.deliveries` `SCAN` over whole keyspace | O(total keys) per listing; latent at 0 delivery keys | Proposed secondary per-owner index (format change, not attempted) |
| 8 | Single memoized Redis connection, no pool | 2.3–3.9× p50 inflation with 5 threads | Proposed pool sized to Puma threads; `config/puma.rb` is protected |
| 9 | No-TTL account/webhook keys | unbounded by design | Product/operator decision |
| 10 | Large-record memory | 1 MiB plaintext ≈ 1.57 MiB Redis | Documentation correction proposed (`DATABASE.md`) |

## 6. Limitations — gates NOT run here

- The CI load test (`loadtest.rb 100 20` with `RATE_LIMIT_CONCEAL/REVEAL=100000`) and the
  400/40 soak are **not** locally reproducible: this host has no native Ruby and the dev stack's
  default limits must not be weakened. The specialist's concurrency figures used source-IP
  rotation under default limits, not the raised-limit CI soak.
- `/metrics` is disabled locally (404), so the token path, memory-ratio alert and scrape limits
  were not exercised.
- TLS rehearsal (T-70), host firewall (T-71), production AOF/`maxmemory` settings and real
  browser journeys were out of this audit's scope; the dev Redis has AOF off and unlimited memory.
- The `pipelined` optimization is verified functionally by specs, **not re-benchmarked** after
  the change; the expected gain is one Redis round trip per emitted event.
- One throwaway `perf-*@example.test` account and ~600 short-TTL secrets remain in the dev DB 15
  for traceability; all except the account and its index keys expire on their own TTLs.

## 7. Verdict

No measured result contradicts the release posture: the one-time-secret path remains correct
under load, Redis stays well inside its slow-log threshold, and all documented body/rate limits
hold. The material capacity constraint is the deliberate Argon2id cost (~2 passphrase reveals/s on
this single-worker staging stack); it must be treated as a documented capacity plan, not silently
"optimized" by weakening the gate.

## 8. Independent pre-release benchmark (2026-11-21, third directive)

A second, independent measurement was taken on a **throwaway** stack (Puma 7.2.3, 2 workers,
production env, Redis 7.4 on a private port, `AUTH_MODE=disabled`, raised test-only rate limits).

| Path | n | p50 | p95 | p99 | Statuses |
| --- | ---: | ---: | ---: | ---: | --- |
| `GET /health` | 100 | 3.23 ms | 6.96 ms | 7.68 ms | 200 ×100 |
| `POST /api/v3/guest/conceal` | 100 | 4.83 ms | 9.12 ms | 11.41 ms | 201 ×100 |
| `GET .../secret/:key` preview | 100 | 3.28 ms | 10.94 ms | 14.40 ms | 200 ×100 |
| `POST .../reveal` (no passphrase) | 60 | 5.75 ms | 10.35 ms | 11.05 ms | 200 ×60 |
| `POST conceal` with passphrase | 20 | 296.6 ms | 437.7 ms | 437.7 ms | 201 ×20 |
| `POST reveal` with passphrase | 20 | 363.8 ms | 514.8 ms | 514.8 ms | 200 ×20 |

These are lower than §2's figures (different host load and a 2-worker process) but agree on the
shape: non-hashed paths are single-digit milliseconds and Argon2id dominates the passphrase path
(~60–70× the unhashed create). An initially reported passphrase-reveal row was **discarded**: it
reused one single-use key and returned 19×404; the corrected run creates a fresh key per reveal.

**Load test.** The corrected `script/loadtest.rb 400 40` produced `Created 400 in 3.45s (115.8/s)`,
`400` exactly-once reveals, `0` wrong counts, `0` workers with no success. An earlier run on an
idle host measured `257.7/s`; the drop is CPU contention from running the full RSpec suites
concurrently, not a code regression. Redis after the soak: `used_memory 1.55M`, `SLOWLOG LEN 0`.

**Optimizations applied and verified.** `Webhook.emit` now batches endpoint reads and all writes
into pipelines instead of 1+4N sequential commands (red spec proved 3 batches for N=3; webhook
suites 19/0); `Webhook.list` and `SecretRequest.list` pipeline their per-row reads (requests and
index suites 18/0). `script/loadtest.rb` reuses a thread-local connection, removes a dead queue
and reports `reveal_fail` honestly.

**Limitations.** No native Ruby on this host, so all backend checks ran in Docker; the two
measurement runs used different host load and are not directly comparable. `/metrics`, production
AOF/`maxmemory`, real TLS/hostname (T-70), Redis host firewall (T-71), and a production-sized
dataset were not exercised. The MAC-over-full-ciphertext cost, session read+touch two-RTT pattern
(`session.rb` is protected), webhook delivery `SCAN`, and Redis connection pooling remain
documented, unapplied items from §5; no data-shape change was attempted.
