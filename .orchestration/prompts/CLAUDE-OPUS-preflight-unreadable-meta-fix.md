# Task

- Task ID: task_9d4e7f2a6c31
- Attempt: 1
- Role: engineering-minimal-change-engineer
- Base SHA: 1a85d0fc5665ccc854bbc42d99839d57470a4517
- Risk tier: medium
- Verify command: ./verify.sh
- Acceptance check: run: ./tests/preflight-lease.sh

Implement the remaining Claude Fable blocker in the current worktree. Claude
Fable confirmed the preflight/lease fixes are otherwise correct. In
`template/.orchestration/lease.sh`, make the metadata reader treat an
unreadable `.orchestration/.lease/meta` the same as a missing one, so
`release --force` can always clear a crash-window lease. Preserve normal
metadata reads and owner-aware non-force release behavior.

Add a focused regression case to `tests/preflight-lease.sh` that creates a
lease directory with unreadable meta, verifies normal release cannot claim it,
then verifies `release --force` removes it. Keep the test portable and restore
permissions/cleanup safely. Do not change unrelated behavior. Run:

- ./verify.sh
- ./tests/preflight-lease.sh

Write `.orchestration/reports/CLAUDE-OPUS-preflight-unreadable-meta-fix.md`
with the result. Do not commit, push, or create a PR. Send worker_done.
