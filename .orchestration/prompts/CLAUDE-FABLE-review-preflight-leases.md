# Claude Fable review brief — preflight and writer leases

Review the current `claude/opus-preflight-leases` worktree read-only. Claude Opus implemented the next audit slice described in `.orchestration/prompts/CLAUDE-OPUS-preflight-leases.md`, on top of merged PR #6.

Read the fused audit, implementation report, all changed files, and the diff from base `1a85d0fc5665ccc854bbc42d99839d57470a4517`. Run `./verify.sh`, `./tests/preflight-lease.sh`, and additional safe/adversarial checks.

Review correctness, atomicity, owner safety, stale lease behavior, preflight false positives/negatives, shell portability, scope, security, tests, and backward compatibility. Do not edit implementation files, commit, push, create a PR, or update trackers.

Write `.orchestration/reports/CLAUDE-FABLE-review-preflight-leases.md` with:

- first line `approve`, `approve with improvements`, or `request changes`
- exact findings with severity, file/line evidence, user impact, and reproduction
- commands and exit codes
- remaining risks

The review report is the only allowed write.
