# Claude Fable review: case-insensitive verify deny set

- Task ID: task_FABLE_CASE_INSENSITIVE_VERIFY_DENY
- Attempt: 1
- Role: engineering-code-reviewer
- Base SHA: 7fa26117c649fa18b07f6b8a6b8885f6ad05abd7
- Risk tier: medium
- Allowed paths: template/.orchestration/verify.sh,tests/verify-report.sh
- Verify command: ./verify.sh
- Acceptance check: run: ./tests/verify-report.sh

Review the current uncommitted diff against base SHA `7fa26117c649fa18b07f6b8a6b8885f6ad05abd7`. This is a narrow follow-up to the recorded verify-command capability profile: deny-set basenames are folded to lowercase before lookup, with mixed-case path-shaped regression tests.

Read-only review. Do not edit implementation files, commit, push, or create/merge a PR. Write only `.orchestration/reports/CLAUDE-FABLE-review-case-insensitive-verify-deny-set.md`.

Independently run `./tests/verify-report.sh`, `./verify.sh`, `git diff --check`, and `./template/.orchestration/verify.sh --diff-sha`. Check Bash 3.2 compatibility if available. Probe lowercase, uppercase, and mixed-case path-shaped denied utilities, permitted local verify commands, and ensure the change does not alter the runner allowlist or permit execution before refusal.

Report with structured fields matching this prompt, verdict APPROVE or REQUEST_CHANGES, severity-ordered findings with exact paths/lines, commands/results, scope assessment, failures, deviations, remaining risks, and explicit blockers. Do not claim checks you did not run. Send worker_done with the report path and verdict.
