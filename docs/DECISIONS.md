# Architectural decisions

Format: context → decision → consequences. Status: `accepted`, `proposed`, `superseded`.
Dates reflect when the decision was first recorded, not when code landed.

## D-001 — Plain Roda on Rack 3 instead of Otto 2

**Status:** accepted (2026-11-11)

**Context.** The brief names Otto 2 as the framework layer, but the Otto 2/Familia v2
combination is not available as a documented, installable dependency for this stack.
Depending on unpublished internals would make the build unreproducible.

**Decision.** Use `roda` directly on `rack` 3, with Puma as the server. Routes live in
`lib/onetime/web/app.rb` and versioned sub-apps under `apps/api/`.

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
cookie; `session:<token>` in Redis with a TTL. No signing, no JWT, no refresh tokens.

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
Passphrase guessing is bounded only by the per-IP reveal limiter (no per-secret budget),
and a leaked `SECRET` plus a leaked record still exposes content without the passphrase.
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
a code one. MFA, per-secret attempt budgets and passphrase-strength scoring remain out of
scope (D-012, K-21).
