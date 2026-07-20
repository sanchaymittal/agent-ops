# Claude Fable review: recorded verify command safety

- Task ID: task_REVIEW_HARDEN_VERIFY_SAFETY
- Attempt: 1
- Role: engineering-code-reviewer
- Base SHA: 1fdcf78851a069b7726493eb46b4c30801dcfaa6
- Risk tier: high
- Allowed paths: template/.orchestration/verify.sh,template/.orchestration/README.md,tests/verify-report.sh
- Verify command: ./verify.sh
- Acceptance check: run: ./tests/verify-report.sh

Review the current branch diff against `origin/main`/base SHA `1fdcf78851a069b7726493eb46b4c30801dcfaa6`, focusing on the hardening of `template/.orchestration/verify.sh --run-verify REPORT.md`.

Read-only review: do not edit implementation files, commit, push, or create/merge a PR. Write only the matching report at `.orchestration/reports/CLAUDE-FABLE-review-harden-run-verify-safety.md`.

Independently run safe checks, including `./verify.sh`, `./tests/verify-report.sh`, `git diff --check`, and adversarial probes for shell wrappers (`sh -c`, `bash -c`, `env`, `eval`), pipes/lists/redirects/substitution/backgrounding, path-shaped wrappers, destructive/network utilities, absolute/parent paths, and permitted local `./verify.sh`. Check Bash 3.2 compatibility if available. Verify that rejected commands cannot execute their payload and that the report's claims match observed output.

Report format:

- Verdict: APPROVE or REQUEST_CHANGES
- Findings ordered by severity, with exact paths/lines and reproductions
- Commands and results
- Scope/quality assessment
- Explicit blockers, if any

Do not claim checks you did not run. Send `worker_done` to the coordinator with the report path and verdict when finished.
