# Review task

## Identity

- Task ID: task_5b7e4a1c9d22
- Attempt: 1
- Role: engineering-software-architect
- Base SHA: 1a85d0fc5665ccc854bbc42d99839d57470a4517
- Risk tier: medium
- Verify command: ./verify.sh
- Acceptance check: run: ./tests/preflight-lease.sh

## Brief

Perform a read-only Claude Fable review of the corrected preflight/worktree
lease slice in the current worktree. Review the exact diff from Base SHA to
HEAD plus uncommitted files. Do not edit implementation files, commit, push,
or create a PR.

Check especially:

1. A fresh lease does not report stale, and the recorded PID contract remains
   meaningful for direct and wrapped callers.
2. `release --force` removes a lease directory when metadata is missing.
3. Owner/dispatch newline rejection occurs before lock creation or metadata
   corruption.
4. `kill -0`/`ps` liveness handling is conservative and portable to macOS Bash.
5. Preflight error formatting, atomic acquisition, owner safety, diff-SHA
   hygiene, tests, and documentation remain correct.

Run safe focused verification as useful:

- ./verify.sh
- ./tests/preflight-lease.sh
- adversarial probes for fresh lease status, missing-meta force release, and
  concurrent acquisition.

Write `.orchestration/reports/CLAUDE-FABLE-review-preflight-lease-fixes.md`
with verdict `approve` or `request changes`, severity-ordered findings with
exact file/line references, commands/results, and remaining risks. Send
worker_done with the report path and verdict. Do not modify implementation
files.
