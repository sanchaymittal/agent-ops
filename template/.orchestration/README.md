# Optional worker safeguards

Use these only when the user explicitly requests delegation or parallel agent work.

- `preflight.sh` — checks the base SHA, verify runner, CLI, and lease before dispatch.
- `lease.sh` — atomic one-writer guard for a shared worktree.
- `burn.py` — read-only local diagnostic for polling and token cost in Codex and Claude session logs.
