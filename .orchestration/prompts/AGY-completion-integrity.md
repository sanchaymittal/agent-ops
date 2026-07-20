# AGY implementation brief — completion integrity

## Goal

Implement the first vertical slice from `.orchestration/reports/fused-session-audit.md`: make completion evidence behavior-aware and prevent a task from being reported `done` without an explicit acceptance check and final-state verification.

## Context

The current branch already contains user-authored baseline work: hash-bound prompt/report templates, `.orchestration/verify.sh`, `verify.sh`, and tests. Preserve that work. Extend it minimally and compatibly.

## Required outcomes

1. Add an `Acceptance check` field to the prompt and report templates.
2. Update `.orchestration/verify.sh` so a `done` report requires matching acceptance-check fields and non-empty acceptance evidence. Support both executable checks and observable-artifact checks without inventing project-specific syntax.
3. Add a safe `--run-verify REPORT.md` mode, or an equivalent portable command, that re-runs the prompt’s `Verify command` during validation, captures a bounded result, and rejects a report when the command fails. Do not silently execute arbitrary external-action commands.
4. Add tests covering acceptance-check omission/mismatch, missing acceptance evidence, verify-command failure, and success after the final edit.
5. Update the relevant orchestration docs and README briefly so the protocol is discoverable. Keep indexes at or below 40 lines.

## Scope

Allowed paths: `.orchestration/prompts/AGY-completion-integrity.md`, `.orchestration/prompts/TEMPLATE.md`, `.orchestration/reports/TEMPLATE.md`, `.orchestration/verify.sh`, `tests/**`, `verify.sh`, `README.md`, `template/AGENTS.md`, `template/docs/orchestration/index.md`, `template/docs/orchestration/orca.md`, `template/.orchestration/**`.

Do not edit role bodies, `init.sh`, generated target repositories, or unrelated audit reports.

## Constraints

- Do not commit, push, create a PR, or mutate external trackers.
- Read all touched files before editing.
- Prefer a small shell implementation compatible with macOS BSD tools and GNU tools.
- Keep output byte-bounded and make failures explicit.
- Run focused tests, then `./verify.sh`.
- Write a report at `.orchestration/reports/AGY-completion-integrity.md` using the report template. First line must be `done` or a precise `blocked:` outcome.
