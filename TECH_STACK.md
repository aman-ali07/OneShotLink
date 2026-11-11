# Tech stack

Versions below are what the repository **declares**, what the host **has**, or what is
**still planned**. Backend gems are installed in the `ots-dev` Docker image and locked by
`Gemfile.lock`; the Ruby suite runs there. The Vue frontend is scaffolded and locked by
`frontend/package-lock.json`; its typecheck/build runs on Node 24. Ruby itself is still
absent on the host.

## Runtime

| Layer | Technology | Declared / planned | Host availability | Rationale |
| --- | --- | --- | --- | --- |
| Language (backend) | Ruby | `>= 3.2` (`Gemfile`) | **not installed** | Matches the reference implementation; small runtime surface |
| App server | Puma | `~> 6.6` | via Bundler (not installed) | Rack-native, production default |
| Rack | Rack | `~> 3.1` | via Bundler | Modern Rack 3 API |
| Framework | Roda | `~> 3.87` | via Bundler | Tree-routing, low overhead; no Rails |
| Datastore | Redis / Valkey | 7+ target | 8.10.3 local | TTL + atomic Lua primitives the product depends on |
| Redis client | `redis` gem | `~> 5.4` | via Bundler | Official client, redis-client transport |
| JSON | OJ | `~> 3.16` | via Bundler | Fast serialization; strict mode planned |
| Passwords | Argon2id via `argon2` | `~> 2.3` | via Bundler | Memory-hard hashing; `bcrypt` legacy path verified (K-03 resolved) |
| CLI | Ruby `OptionParser` (stdlib) | Ruby 3.3 | stdlib | `bin/ots` subcommands without an extra runtime dependency |
| Logging | semantic_logger | `~> 4.16` | via Bundler | Declared; current app uses Ruby `Logger` + request IDs, not wired yet |
| i18n | ruby-i18n | `~> 1.14` | via Bundler | Declared for later localization; unused |
| Tests | RSpec + rack-test | `~> 3.13`, `~> 2.2` | via Bundler | Integration specs through the real Rack stack |
| Frontend | Vue 3 | `^3.5.13` | Node 24.22.0 | Composition API, `<script setup>` |
| Build | Vite | `^6.0.7` | Node 24 | Dev server + static build to `public/app` |
| Language (frontend) | TypeScript | `~5.7.2` | — | Strict + `noUncheckedIndexedAccess`; `vue-tsc` gate |
| Styling | Tailwind CSS | `^4.0.0` (`@tailwindcss/vite`) | — | Utility-first, tokens from `replica/design` |
| Validation | Zod | `^3.24.1` | — | Runtime parsing + inferred types |
| State | Pinia | not used | — | Local component state is enough for two views |
| Routing | Vue Router | `^4.5.0` | — | `/` and `/secret/:key` |
| Container | Docker + Compose | 29.1.3 available | yes | Single-image self-hosting |

## Deliberate deviations from the brief

| Brief | This repo | Why |
| --- | --- | --- |
| Otto 2 | Roda on Rack 3 | Otto 2 / Familia v2 internals are not available as documented; adding an unavailable dependency would block the build (D-001) |
| Familia v2 ORM | Explicit Redis mapping in `Store` + model modules | Same reason; a small, auditable mapping is enough for ~6 models (D-002) |
| Rodauth (full mode) | Deferred; `AUTH_MODE=full` returns 501 | Full auth needs Postgres + RabbitMQ and is a product of its own (D-003) |
| Sequel/PostgreSQL | Not used in v1 | No relational data in v1; receipts live in Redis |
| RabbitMQ | Not used in v1 | No background work in v1; TTL handles expiry |

## Version policy

- Pin exact versions in `Gemfile.lock` and `package-lock.json` once generated.
- Ruby runtime image pins `ruby:3.3-slim` (Debian) for reproducible native gem builds.
- Redis major version must support `EVAL`, `GET`, `SET EX`, `INCR`, `ZADD`; Redis 7+ and
  Valkey 7+ qualify. Tests must not depend on Redis 8-only commands.
- Frontend Node version pinned via `.nvmrc`/Docker base once the scaffold exists.
- Upgrade work is a task, not a drive-by: see [TASKS.md](TASKS.md).

## Dependency verification

OpenCode/AI agents must verify a package exists and is canonical before adding it (see
AGENTS.md). Current declarations are limited to well-known gems. `bcrypt` is declared and
loaded; the legacy verify path has a passing spec (K-03 resolved).
