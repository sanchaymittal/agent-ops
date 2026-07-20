# Claude Fable review brief — completion integrity

Review the current `claude/opus-completion-integrity` worktree read-only. The implementation was produced by Claude Opus for the completion-integrity slice described in `.orchestration/prompts/CLAUDE-OPUS-completion-integrity.md`.

Read the fused audit, the implementation prompt/report, all changed files, and the current diff against `6fb6bac0e7335608d385db7d2eaae9c178115845`. Run `./verify.sh`, the focused verifier tests, and any additional safe checks needed.

Review correctness, acceptance enforcement, final-state verification, shell portability, external-action safety, scope, backward compatibility, tests, and whether the existing user baseline is preserved. Do not edit implementation files, commit, push, create a PR, or update trackers.

Write `.orchestration/reports/CLAUDE-FABLE-review-completion-integrity.md` with:

- first line `approve`, `approve with improvements`, or `request changes`
- exact findings with severity, file/line evidence, user impact, and reproduction
- commands and exit codes
- remaining risks

The review report is the only allowed write.
