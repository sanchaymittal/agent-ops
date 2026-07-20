# Task

## Identity

- Task ID: task_8f1c2f7b6d21
- Attempt: 1
- Role: engineering-minimal-change-engineer
- Base SHA: 1a85d0fc5665ccc854bbc42d99839d57470a4517
- Risk tier: medium
- Verify command: ./verify.sh
- Acceptance check: run: ./tests/preflight-lease.sh

## Brief

Fix the correctness blockers found by Claude Fable in the preflight/worktree
lease slice. Work only in this worktree. Do not commit, push, create a PR, or
modify unrelated behavior.

Required fixes:

1. A freshly acquired lease must not immediately appear stale. The current
   lease records the short-lived lease.sh PID; use a process identity that is
   still valid for the owner/preflight lifecycle (or an explicit PID contract),
   and add a regression test proving a fresh lease is not marked stale.
2. `release --force` must remove a malformed/crash-window lease directory even
   when `.lease/meta` is missing or unreadable. Add a regression test for that
   case.
3. Remove the duplicated `blocked: lease: lease:` prefix in preflight output.
4. Reject owner and dispatch values containing newlines so the metadata format
   cannot be corrupted. Add focused tests if practical.
5. Treat an indeterminate `kill -0` result conservatively rather than marking a
   live process stale. Keep the existing explicit-force policy.

Keep the implementation portable to the repository's supported macOS Bash
environment. Preserve atomic acquisition and owner-aware release. Update the
relevant docs only if the behavior contract changes.

## Verification

- ./verify.sh
- ./tests/preflight-lease.sh

## Report

Write `.orchestration/reports/CLAUDE-OPUS-preflight-lease-fixes.md` with the
required identity fields, files changed, tests run, acceptance result, and any
remaining risks. Do not claim completion unless the acceptance check passes.
