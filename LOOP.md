# Loop Configuration — Minimal Triage (Claude Code)

## Active Loops

| Pattern | Cadence | Status | Command |
|---------|---------|--------|---------|
| Daily Triage | 1d | L1 report-only | `script/loop-free-pi.sh` |

### How this loop is actually invoked here

The kit was scaffolded with `--tool claude`, but this machine runs **free-pi**
(`npx free-pi-cli@latest`), which has no headless/print mode — it is a TUI. So the
cycle is driven through tmux by `script/loop-free-pi.sh`:

```bash
script/loop-free-pi.sh --keep      # one cycle, leave the session viewable
tmux attach -t loop-freepi         # watch it (detach: Ctrl-b d)
script/loop-free-pi.sh             # one cycle, clean up when done
```

The runner pastes a cycle prompt that points the agent at `.claude/skills/loop-triage/SKILL.md`
plus this repo's `loop-constraints.md`, waits for the screen to go idle, and drops the
transcript in `.loop-runs/` (git-ignored). It never commits: you review `STATE.md` and
`loop-run-log.md`, then commit them.

Daily scheduling without Claude Code's `/loop`:

```cron
17 9 * * *  cd ~/projects/onetime-secret && script/loop-free-pi.sh >> .loop-runs/cron.log 2>&1
```

## Human Gates

- No auto-fix until the L2 checklist in `loop-constraints.md` is complete and the
  verifier has been right for a week. Week one is report-only.
- `gate.yaml` is authoritative: crypto (`lib/onetime/crypto.rb`), passwords, sessions,
  `lib/onetime/web/app.rb`, `compose.yaml`, `Dockerfile`, `config.ru`, CI workflows and
  the preflight scripts are human-review paths.
- Never close T-70 (TLS) or T-71 (Redis firewall): they are operator infrastructure, not
  repository work.
- Copy rules from `docs/DECISIONS.md` D-012 are binding: never claim zero-knowledge, never
  claim "production ready" before `script/preflight.sh` is green on a real host.
- Secrets, passphrases, keys and ciphertext never appear in a log, fixture, issue or
  commit message (SECURITY.md).

## Worktrees

- Use `isolation: worktree` when spawning implementer sub-agents (L2+).
- One worktree per fix attempt; discard after verifier REJECT.

## Connectors (MCP)

- MCP optional for L1 report-only loops.
- For L2+: GitHub MCP to read CI/issues; scope connectors to read + comment only until trusted.

## Budget

- Max sub-agent spawns per run: 0 (L1)
- Review STATE.md daily

## Links

- Pattern: [daily-triage](https://github.com/cobusgreyling/loop-engineering/blob/main/patterns/daily-triage.md)
- Checklist: [loop-design-checklist](https://github.com/cobusgreyling/loop-engineering/blob/main/docs/loop-design-checklist.md)
- This repo's own rules: `AGENTS.md` (working rules), `SECURITY.md` (prohibited actions),
  `TESTING.md` (the gates a fix must pass), `TASKS.md` (status of record).