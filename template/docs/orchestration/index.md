# Optional worker delegation

Read when: dispatching, supervising, or executing delegated work.

## Model

- Direct work in the interactive session is the default. Use this flow only when the user explicitly requests delegation or parallel agent work.
- The coordinator plans, dispatches, verifies, and commits; it updates a tracker only when one is in use.
- Workers are spawned with the narrowest capability profile and never commit.
- Independent tasks may run in parallel only in separate worker sessions/worktrees; serialize anything touching the same files.

## Dispatch checklist

1. Give the worker a bounded task, allowed paths, acceptance check, and permissions.
2. For a writing worker, run `.orchestration/preflight.sh` and acquire `.orchestration/lease.sh`.
3. Wait for completion without polling; rules are in [`supervision.md`](./supervision.md).
4. Inspect the worker diff/status and run the acceptance check plus `{{VERIFY_CMD}}` for code changes.
5. Add independent review only for high-risk work or when the user requests it; update a tracker only when one is in use.

## Detail

| File | Covers |
| --- | --- |
| [`supervision.md`](./supervision.md) | Preflight, leases, supervision budget, and hang recovery |
| [`tasks.md`](./tasks.md) | Optional tracker rules |
| [`linear.md`](./linear.md) | Optional Linear-specific adapter rules |
