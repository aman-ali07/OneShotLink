# Architectural decisions

Format: context → decision → consequences. Status: `accepted`, `proposed`, `superseded`.
Dates reflect when the decision was first recorded, not when code landed.

## D-001 — Plain Roda on Rack 3 instead of Otto 2

**Status:** accepted (2026-11-11)

**Context.** The brief names Otto 2 as the framework layer, but the Otto 2/Familia v2
combination is not available as a documented, installable dependency for this stack.
Depending on unpublished internals would make the build unreproducible.

**Decision.** Use `roda` directly on `rack` 3, with Puma as the server. Routes live in
`lib/onetime/web/app.rb` (no `apps/` directory — superseded by T-87).

**Consequences.** We lose Otto's conventions and any inherited plugin ecosystem. Roda's
tree routing is sufficient; the missing structure is replaced by explicit logic objects
and model modules. Revisit only if Otto becomes a supported dependency.

## D-002 — No ORM; explicit Redis mapping

**Status:** accepted

**Context.** Familia v2 is unavailable (D-001). Sequel is only justified by relational
accounts, which are deferred.

**Decision.** Keep Redis access in `Onetime::Store` and small model modules that build
keys and serialize records. No generic persistence abstraction until 2–3 models share
enough behavior to earn one.

**Consequences.** More explicit key/TTL code, fewer moving parts. Serialization and TTL
correctness are the model's responsibility and must be tested.

## D-003 — Defer full auth (PostgreSQL + RabbitMQ + Rodauth)

**Status:** accepted for v1; revisit after T-55

**Context.** Full mode implies migrations, MFA, WebAuthn, magic links, SSO, email
delivery, background workers, and dead-letter handling — a second product. v1's core
value (one-time secrets) does not need accounts at all.

**Decision.** Ship `AUTH_MODE=disabled` and `simple` (Redis sessions, Argon2id).
`AUTH_MODE=full` fails closed with `501 not_configured`.

**Consequences.** The compose file will not include Postgres/RabbitMQ as working
services. Users who need SSO/MFA must wait or contribute. The config gate exists so a
future implementation does not change the surface.

## D-004 — Secrets are JSON strings, not Redis hashes

**Status:** accepted

**Context.** `Store.consume` performs an atomic compare-and-delete: `GET`, compare the
exact value, `DEL`, all inside one Lua script. Redis hashes would require `HGETALL` plus
a canonical re-serialization to compare, which is fragile and slower.

**Decision.** Store the encrypted record as a JSON string at `secret:object:<objid>` and
metadata in a separate hash. Pass the exact serialized string read from Redis back into
the consume script.

**Consequences.** Whole-record atomicity is trivial. Updating a single field requires
read-modify-write, which is acceptable because records are immutable after creation.
Models must never store the secret as a hash. This also rules out partial updates during
a reveal.

## D-005 — Verify passphrase before consuming

**Status:** accepted

**Context.** Consuming first and then verifying would destroy the secret on a typo. A
naive "read, verify, delete" re-opens the double-reveal race.

**Decision.** Read, verify the Argon2id hash, decrypt, then atomically compare-and-delete.
A failed passphrase never reaches the delete step.

**Consequences.** A wrong passphrase does not burn the record (good UX, mild
passphrase-guessing exposure, bounded by the reveal rate limit). **Amended 2026-11-12
(see D-013):** decryption also runs before the consume, so a rotated `SECRET` or a corrupt
record no longer destroys the secret — the reveal answers `500` and the record stays
readable once the key is right.

## D-006 — Serve the SPA from Rack; no separate web server

**Status:** accepted

**Context.** Self-hosting should be one container. The SPA is static after build.

**Decision.** Vite builds into `public/app`; Roda serves those files and returns
`index.html` for non-API GETs. In development, Vite runs separately and proxies `/api`.

**Consequences.** One origin in production (no CORS for the UI), simple Docker image.
Cache headers for hashed assets and `no-store` for `index.html` must be set explicitly.

## D-007 — Opaque server-side sessions, not JWTs

**Status:** accepted

**Context.** Simple mode needs logout/revocation and minimal moving parts.

**Decision.** Random 32-byte token in an `HttpOnly`, `SameSite=Lax`, `Secure`-when-SSL
cookie; `session:<sha256(token)>` (digest only) in Redis with a TTL. No signing, no JWT, no refresh tokens.

**Consequences.** Revocation is a `DEL`. Every request costs one Redis lookup. Multi-app
SSO is not possible without a shared Redis (acceptable).

## D-008 — Redis TTL is the only expiry mechanism in v1

**Status:** accepted

**Context.** A sweeper adds a worker, a schedule, and failure modes for no user-visible
benefit.

**Decision.** Set `EX` on secret and receipt keys; no cron/worker. Owner indexes are
pruned lazily when read.

**Consequences.** Expiry is exact and O(1). Orphaned index entries can exist until read;
they are ignored and expire with the receipt. If a future feature needs "expiring soon"
emails, that requires the deferred worker.

## D-009 — Argon2id for new hashes, bcrypt verification for legacy

**Status:** accepted

**Context.** The brief requires Argon2id but also mentions bcrypt migration. Existing
deployments may hold bcrypt hashes.

**Decision.** `Password.create` always emits Argon2id. `Password.verify` detects `$2a$`
/`$2b$`/`$2y$` and verifies with bcrypt, then the caller rehashes on successful login.
The `bcrypt` gem is declared in the Gemfile; K-03 is resolved.

**Consequences.** New data is memory-hard. Legacy support is an explicit, removable
branch. If bcrypt is absent, legacy verification raises internally and returns `false`
rather than crashing the request (current rescue).

## D-010 — Documentation is the source of truth for status

**Status:** accepted

**Context.** The repository is being built with AI assistance; plans are easy to mistake
for implementations.

**Decision.** Every doc carries a status banner; `TASKS.md` separates `DONE*` (code
present, unverified) from `TODO`; `KNOWN_ISSUES.md` records real defects. Claims require
command output.

**Consequences.** Handoffs take slightly longer but prevent false "done" claims. Docs
must be updated in the same change that invalidates them.

## D-011 — No OpenCode project configuration

**Status:** accepted

**Context.** OpenCode v2.2.7 discovers `AGENTS.md` by walking up from the project
directory and loads the global `~/.config/opencode/AGENTS.md`. There is no project
`opencode.json`/`opencode.jsonc`.

**Decision.** Use root `AGENTS.md` as the single instruction file, and reference the
other docs from it. Do not add `opencode.json` or nested `AGENTS.md` until a concrete
need appears (MCP server, permissions, subtree-specific rules).

**Consequences.** No config duplication; the docs remain tool-agnostic. If the project
adds an MCP server or custom agent, add a minimal `opencode.json` and document it here.

## D-012 — Passphrase is an access gate, not a second encryption key

**Status:** accepted (2026-11-11)

**Context.** The original advertises that its server cannot decrypt a
passphrase-protected secret. This clone encrypts every record with the instance `SECRET`
and stores an Argon2id hash of the passphrase. A server operator can therefore decrypt a
protected secret after the gate is passed. Deriving the data key from the passphrase
would close that gap, but it conflicts with two explicit requirements: verify the
passphrase before consuming (a wrong attempt must not burn the secret), and let an owner
manage receipts/dashboards server-side. It also makes a lost passphrase unrecoverable.

**Decision.** Keep instance-key encryption plus the Argon2id gate for v1. Ordering is
verify → decrypt → atomic consume (D-013). UI and docs describe the passphrase as an extra access
check, never as "zero-knowledge" or "the server cannot decrypt". Revisit only as an
opt-in client-side-encryption mode (v2), with its own UX and recovery trade-offs.

**Consequences.** K-21 remains a deliberate parity gap, not an implementation bug.
Passphrase guessing is bounded by the per-IP reveal limiter **and**, since D-012b, a per-secret
budget (5 guesses / 900 s keyed by the opaque secret id). A leaked `SECRET` plus a leaked record
still exposes content without the passphrase.
T-48 is closed; future copy must not overclaim.

## D-013 — Decrypt before the atomic consume

**Status:** accepted (amends the ordering half of D-005)

**Context.** D-005 put the atomic compare-and-delete before `Crypto.decrypt` and accepted
the loss: "decryption failure after consume loses the record and returns a generic 500 —
the fail-closed choice". In practice that choice has a sharp edge. A `SECRET` rotation, a
stale key left in an environment, or a corrupt record means the reveal deletes the
ciphertext and *then* fails — so an operator fixing the key finds the secret already gone,
and the reader is told it never existed. The destructive step was being taken on data the
server had just proven it could not read.

**Decision.** Run the pure checks first and the irreversible one last: read, verify the
passphrase, decrypt, then compare-and-delete. A decryption failure answers `500` and leaves
the record untouched.

**Consequences.** Operator key mistakes become recoverable (rotate back, or finish the
rotation) instead of permanent; the reveal path reports a genuine server fault rather than
silently consuming. Nothing is lost on the double-reveal invariant: two racers still both
read and decrypt, exactly one wins the compare-and-delete, and the loser gets `404` without
ever seeing plaintext. Cost: a losing racer does the decryption work for nothing, which is
measured in microseconds and already covered by the concurrency load test.

## D-014 — An 8-byte floor on the passphrase

**Status:** accepted (narrows D-012; supersedes the "1–256" bound in T-47)

**Context.** The create path accepted any non-empty passphrase, including a single
character, and TESTING.md asserted that behaviour deliberately. The passphrase is an access
gate whose only guessing control is the per-IP reveal limiter (60 attempts per minute by
default). A 1–2 character passphrase therefore falls to a handful of attempts from a few
addresses — the Argon2id cost buys little when the secret space is a few dozen values, and
distributed guessing defeats the per-IP limiter entirely.

**Decision.** Reject a supplied passphrase shorter than 8 bytes at the create boundary
(`422 validation_error`, nothing written). An empty string or absent field still means "no
passphrase". The bound is a constant in `ConcealSecret`, not an environment knob: a floor
that can be lowered to 1 is not a control. The reveal path does not enforce a length, so
records created before this decision keep revealing with their original passphrase.

**Consequences.** This is a contract change for API clients: a 1–7 byte passphrase that
used to return `201` now returns `422`. The UI sets `minlength`, mirrors the check, and
explains the rule next to the field. 8 bytes is still short for a human-chosen passphrase —
the honest ceiling is a longer minimum or a generated one, which is a copy/UX decision, not
a code one. MFA and passphrase-strength scoring remain out of scope (D-012, K-21); a per-secret
attempt budget was added later in D-012b.

## D-015 — Patch inside the declared constraint; do not add a gem for a bump

**Status:** accepted (2026-11-20)

**Context.** A fresh `bundler-audit check --update` on 2026-11-20 found four advisories
against the locked Puma 7.2.1 (GHSA-r885-m39c-939g, GHSA-rf6g-xhmp-gm7v,
GHSA-x646-wp7c-h9mg, GHSA-xw3h-pgr9-3vg7). The `Gemfile` already declared `~> 7.2`, so
this was a stale lockfile, not a missing dependency or a reason to change the server.

**Decision.** Run `bundle update puma` inside the `ots-dev` image and commit only the
resolved lockfile change (to 7.2.3). Keep `Gemfile`, the server choice (D-001), and the
version constraint untouched. Re-run the full gates and rebuild the image in the same
change.

**Consequences.** No new dependency, so the "new gem needs an ADR + canonical check" rule
does not fire; this decision records the reasoning anyway. The declared constraint is a
range precisely so patch fixes can land without another product decision. `TECH_STACK.md`,
`CHANGELOG.md`, `TASKS.md` and `KNOWN_ISSUES.md` carry the new resolved version; a future
bump outside `~> 7.2` needs a fresh decision.

## D-016 — Automated WCAG 2.2 AA gate and component tests

**Status:** accepted (2026-11-21)

**Context.** Four frontend audits found real code-level WCAG gaps (per-route titles,
terminal-state focus, placeholder contrast, clipboard announcements, touch targets). The
only automated check was a `[role=alert]` assertion in one journey, so those defects shipped.
The same audits also found repeated primitives with no component-level tests; the API client
has 12 Vitest tests, but nothing exercises a button's loading/disabled or a copy button's
status behaviour.

**Decision.** Add two **test-only** dependency sets, each verified canonical before install:
- `@axe-core/puppeteer` (4.14.0, MPL-2.0, `github.com/dequelabs/axe-core-npm`) for a
  `e2e/a11y.mjs` gate run against the live stack with `wcag2a`, `wcag2aa`, `wcag21a`,
  `wcag21aa` and `wcag22aa` tag sets; any violation exits non-zero. It is wired into the
  container CI job after the existing journeys. **Superseded in the shipped build:** the gate
  uses canonical `axe-core` 4.14.1 (MPL-2.0) injected via CDP, because `@axe-core/puppeteer`
  pulled a full Puppeteer tree with known advisories. The tag sets and non-zero-on-violation
  contract are unchanged.
- `@vue/test-utils` (2.6.0, MIT, `github.com/vuejs/test-utils`) and `jsdom` (31.0.1, MIT,
  `github.com/jsdom/jsdom`, Node ^24.15 accepted) for component tests in Vitest. No
  production dependency is added; `frontend/src/lib/api.ts` remains the only fetch layer.

**Alternatives considered.** A hosted scanner (rejected: network + secret exposure); hand-
written ARIA assertions only (rejected: misses contrast, target size and reflow); Playwright
test runner (rejected: duplicate of the committed puppeteer journeys and another dependency).

**Consequences.** CI now fails on accessibility regressions, not just on TypeScript and
build errors. jsdom is an approximation: it does not compute layout or real screen-reader
announcements, so the live axe gate and the manual keyboard/reflow checks remain necessary.
A11y findings from the gate are fixed in code, never suppressed by rule exclusions; any
temporary exclusion must be recorded here with a reason and an expiry. Dark mode stays out
of scope — the app remains light-only and `DESIGN_SYSTEM.md` says so.

## D-017 — Receipt lifecycle, owner burn, and endpoint-scoped deliveries

**Status:** accepted (operator decision 2026-11-21; resolves D-receipt and B8)

**Context.** Reveal used to delete the owner receipt and its index member. That made the
dashboard's "newest secrets" list forget a secret the moment it was read, and there was no
way for an owner to destroy an unrevealed secret. Separately,
`GET /api/v3/webhooks/:id/deliveries` ignored `:id` and returned deliveries across every
endpoint the owner had registered. Both needed a recorded product decision before touching
the protected web layer.

**Decision (operator).**
- Keep the receipt after a successful reveal. The secret payload is permanently destroyed
  by the existing atomic compare-and-delete; only non-sensitive metadata survives.
- Lifecycle statuses are `new → previewed → revealed → burned`. A preview never consumes
  and cannot downgrade a terminal status; `revealed` and `burned` are terminal and applied
  at most once (Lua compare-and-set).
- Retain receipt metadata for **30 days** after `revealed` or `burned`, then let Redis expire
  it. The owner-index member carries the same retention TTL and stale members are pruned
  lazily by the receipts listing.
- Never put secret contents, passphrases, encryption keys, or the bearer key in a receipt,
  an audit event, or a log line.
- Add an owner-only burn route `DELETE /api/v3/secret/:key`: session required, CSRF/origin
  proof, a dedicated `RATE_LIMIT_BURN` scope, owner scoping with a uniform 404, and the
  same atomic consume as reveal (no decrypt, no plaintext returned).
- Webhook deliveries are filtered by the `:id` in the path; unknown or foreign ids answer
  `404` rather than an owner-wide listing.

**Alternatives considered.** Deleting receipts on reveal (rejected by the operator: owners
want a 30-day record); a separate receipt token/API (deferred — P1-1 token model is not
decided, and the opaque secret key already acts as a capability); a dedicated burn limiter
scope (chosen so a burst of burns cannot exhaust the reveal or account-delete budgets).

**Consequences.** `secret:receipt:*` now has a 30-day TTL after a terminal transition
instead of the original secret TTL; dashboard receipts expose `status`. A new audit event
`secret.burned` and a `RATE_LIMIT_BURN` env var are part of the contract. Burn is idempotent
at the HTTP layer only in the sense that a replay is `404` — it is not a two-step
prepare/commit. Auditing and webhook emission for preview are deliberately absent to avoid
high-volume traffic in the append-only audit stream and the operator-run webhook worker.

## D-012b — Per-secret passphrase budget with the existing Redis limiter

**Status:** accepted (2026-11-21). **Budget:** ₹0.

**Context.** Only a per-IP reveal limiter existed, so distributed guessing of a protected
secret was unbounded. A paid WAF or bot service is unnecessary for a self-hosted service
with Redis already running.

**Decision.** Reuse `Onetime::Limiter` (the same atomic Lua fixed-window script used by
every other scope) with a new `passphrase` scope, keyed by the **opaque secret id** rather
than an IP. `RATE_LIMIT_PASSPHRASE` defaults to 5 guesses, bounded over a dedicated
`RATE_LIMIT_PASSPHRASE_WINDOW` of 900 s (not the general 60 s HTTP window), so an attacker
cannot simply outwait a minute. The check runs in `RevealSecret#call` after the metadata MAC and before
`verify_passphrase!`, decrypt and consume. Requests with no passphrase are not guesses and
do not spend the budget. Exhaustion is `429` with `Retry-After`; the record stays readable.

**Trade-offs / limitations.** A fixed window allows a burst across a window boundary; it
is a rate limit, not a permanent lockout. Keys are capability identifiers, not personal
data, and expire with the window. A distributed attacker with many links still gets 5
guesses per link per window — acceptable given 8-byte minimum passphrases (D-014) and
Argon2id cost. No CAPTCHA, no third-party service, no new datastore.

## D-retention — No raw IPs in the audit stream

**Status:** accepted (2026-11-21). **Budget:** ₹0.

**Context.** `audit:events` stored the raw client IP for every account/security event and
was retained at `MAXLEN 100000` with no time bound — unnecessary personal data for a
self-hosted one-time secret service.

**Decision.** `Audit.record` now stores `ip_day`: the first 12 hex characters of an
HMAC-SHA256 over the IP, keyed by `Crypto.derive(SECRET, "ots-audit-ip/v1:<utc-day>")`.
The daily salt rotates, so the same IP maps to a different reference tomorrow; no raw IP
is persisted. Abuse prevention continues to use the existing 60-second limiter keys,
which are already short-lived and expire automatically.

**Trade-offs / limitations.** Same-day correlation is preserved; cross-day correlation is
deliberately impossible. The digest is still a personal-data derivative and is covered by
the stream's retention decision below; operators should set a retention window suited to
their jurisdiction. `ip_day` is not reversible without `SECRET` plus the IP. No IP-based
notification or geo features are planned.

## D-queue — Bounded webhook queue and delivery records in Redis

**Status:** accepted (2026-11-21). **Budget:** ₹0.

**Context.** `webhook:queue` and `webhook:delivery:*` had no TTL; a deployment that never
scheduled `bin/ots webhooks:work` (K-46) could grow the keyspace indefinitely.

**Decision.** Keep the existing Redis sorted-set queue and external worker. Add
`QUEUE_TTL = DELIVERY_TTL = 7 days` (matching `webhook:seen:*`): `emit` sets an `EX` on each
delivery hash, and `claim` atomically prunes queue members older than the TTL before
claiming due work via `ZREMRANGEBYSCORE`. Retry limit remains 3 attempts with backoff; a
terminal delivery is marked `failed` and never re-queued.

**Trade-offs / limitations.** An event unclaimed for 7 days is dropped — an operator who
cannot schedule the worker within a week will lose notifications. At-least-once delivery
still means receivers must deduplicate on the stable delivery id. No managed queue, no
dead-letter exchange; the delivery hash retains `status`/`last_error` for inspection until
its TTL. `webhook:seen:*` and `webhook:inflight:*` are excluded from backups (ephemeral).

## C2 — Public request preview/respond, owner routes remain authenticated

**Status:** accepted (2026-11-21). **Budget:** ₹0.

**Context.** API.md described request preview/respond as public, but both routes called
`require_accounts!` and returned `403` in the default `AUTH_MODE=disabled`. Owners could
only create requests in simple mode; recipients should not need an account.

**Decision.** Recipient-facing `GET /api/v3/requests/:key` and `POST …/respond` are public
capabilities: remove `require_accounts!`. Keep `verify_csrf!` (a no-op without a cookie),
keep the `:respond` rate limiter on submission, add the `:reveal` limiter to the preview so
`fulfilled` cannot be polled for free, and keep strict input validation plus `SET NX`
single-answer semantics. Owner create/list/reveal stay session-scoped.

**Trade-offs / limitations.** Anyone with the 128-bit link can answer once; that is the
product contract, not a vulnerability. Abuse is bounded by per-IP windows, not by identity.
Requests cannot be created without an account in the default mode — the feature is
owner-initiated; ordinary guest secret creation remains fully anonymous. No email
verification or CAPTCHA (both would add infrastructure and friction).

## D-TLS/FW — Free Let's Encrypt TLS and host firewall only

**Status:** accepted (2026-11-21). **Budget:** ₹0.

**Context.** T-70/T-71 remained open because they need the operator's host, not code.

**Decision.** Terminate TLS with Caddy (its built-in ACME client obtains and renews Let's
Encrypt certificates free for a real hostname) or nginx with a free Certbot certificate;
the app stays on loopback behind the proxy. Restrict inbound traffic with the host's own
nftables/ufw: loopback + established allowed, 80/443 public, SSH only from an explicit
`ADMIN_CIDR`, everything else dropped; deny outbound to the Redis subnet on 6379.
`script/host-firewall.sh` prints the exact rules and is a **dry run unless `--apply` is
passed as root**, and refuses to generate a rule with world-open SSH.

**Trade-offs / limitations.** The real hostname, DNS record, public ACME challenge and the
firewall change require actual server-owner access and cannot be performed from this repo.
A local rehearsal behind Caddy with a throwaway CA passed 7 assertions (certificate chain,
HSTS, hardening headers, Secure/HttpOnly/SameSite cookies, HTTP→HTTPS redirect); it does
not prove a public certificate chain or the host rule. No paid CDN, WAF, or managed
firewall is used; scaling to paid infrastructure is deferred until traffic or revenue
justifies it.

## D-018 — Hand-written examples now; generated clients later

**Status:** accepted (2026-11-21, developer-experience pass)

**Context.** The served OpenAPI 3.1 document is the machine-readable contract, but the
repository ships only hand-written examples and a hand-written Zod client. Consumers repeatedly
ask whether a generated SDK exists and which language/runtime is supported.

**Decision.** Keep dependency-free, stdlib-only curl/TypeScript/Python examples as the supported
integration path for the pre-1.0 API. Do **not** add a published SDK package or a codegen step
to CI yet. When a stable v3 consumer is committed, generate it from `/api/v3/openapi.json` with
a canonical generator (`openapi-generator` or `hey-api`), pinned in a `docs/DECISIONS.md`
follow-up and verified by `script/test-examples.sh`.

**Consequences.** Every response-shape change must still be mirrored in the examples and the
Zod client; the example harness and the OpenAPI spec tests are the drift gates. Generated
clients must preserve two contract facts a naive generator loses: v1 GET *consumes* while v3 GET
is a preview, and the legacy `{"message":...}` envelope differs from the v3 `{"error":...}` one.
The support matrix and retry rules live in `docs/SDK.md`.
