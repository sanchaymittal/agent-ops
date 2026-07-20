# Review task

- Task ID: task_7c8e2d4f1a30
- Attempt: 1
- Role: engineering-software-architect
- Base SHA: 1a85d0fc5665ccc854bbc42d99839d57470a4517
- Risk tier: medium
- Verify command: ./verify.sh
- Acceptance check: run: ./tests/preflight-lease.sh

Review the final corrected preflight/worktree lease slice read-only. Claude Opus
changed the metadata guard from `[ -f "$META" ]` to `[ -r "$META" ]` and added
the unreadable-meta regression case after the last Fable finding. Review the
exact uncommitted diff and reports. Do not edit implementation files, commit,
push, or create a PR.

Run:

- ./verify.sh
- ./tests/preflight-lease.sh
- an adversarial probe confirming `release --force` clears both missing and
  unreadable metadata, plus fresh-lease liveness and concurrent acquisition.

Write `.orchestration/reports/CLAUDE-FABLE-final-review-preflight-lease.md`
with verdict `approve` or `request changes`, severity-ordered findings, exact
file/line references, commands/results, and remaining risks. Send worker_done
with the report path and verdict.
