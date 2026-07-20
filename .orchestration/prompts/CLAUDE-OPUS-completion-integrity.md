# Claude Opus implementation brief — completion integrity

- Task ID: task_c90bc3c964ed
- Attempt: 1
- Role: engineering-minimal-change-engineer
- Base SHA: 6fb6bac0e7335608d385db7d2eaae9c178115845
- Risk tier: medium
- Allowed paths: README.md,init.sh,template/**,tests/**,verify.sh,.orchestration/prompts/CLAUDE-OPUS-completion-integrity.md,.orchestration/reports/CLAUDE-OPUS-completion-integrity.md
- Verify command: ./verify.sh
- Acceptance check: run: ./tests/verify-report.sh

## Goal

Implement the first vertical slice from `.orchestration/reports/fused-session-audit.md`: make completion evidence behavior-aware and prevent a task from being reported `done` without an explicit acceptance check and final-state verification.

## Context

The branch already contains user-authored baseline work: hash-bound prompt/report templates, `.orchestration/verify.sh`, `verify.sh`, and tests. Preserve it and extend it minimally.

## Required outcomes

1. Add an `Acceptance check` field to the prompt and report templates.
2. Update `.orchestration/verify.sh` so a `done` report requires matching acceptance-check fields and non-empty acceptance evidence. Support executable checks and observable-artifact checks without inventing project-specific syntax.
3. Add a safe `--run-verify REPORT.md` mode, or equivalent portable command, that re-runs the prompt’s `Verify command` during validation, captures bounded results, and rejects failure. Do not silently execute external-action commands.
4. Add tests for acceptance omission/mismatch, missing evidence, verify-command failure, and success after the final edit.
5. Update relevant docs/README briefly; keep indexes ≤40 lines.

## Allowed paths

`.orchestration/prompts/CLAUDE-OPUS-completion-integrity.md`, `.orchestration/prompts/TEMPLATE.md`, `.orchestration/reports/TEMPLATE.md`, `.orchestration/verify.sh`, `tests/**`, `verify.sh`, `README.md`, `template/AGENTS.md`, `template/docs/orchestration/index.md`, `template/docs/orchestration/orca.md`, `template/.orchestration/**`.

## Constraints

- Do not commit, push, create a PR, or mutate external trackers.
- Read all touched files before editing.
- Keep shell portable across macOS BSD and GNU tools.
- Keep output byte-bounded and failures explicit.
- Run focused tests, then `./verify.sh`.
- Write `.orchestration/reports/CLAUDE-OPUS-completion-integrity.md` using the report template. First line must be `done` or a precise `blocked:` outcome.
