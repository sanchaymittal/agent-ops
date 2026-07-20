# Task

- Task ID: task_6a4d9e2c7f10
- Attempt: 1
- Role: engineering-minimal-change-engineer
- Base SHA: 1fdcf78851a069b7726493eb46b4c30801dcfaa6
- Risk tier: high
- Allowed paths: template/.orchestration/verify.sh,template/.orchestration/README.md,tests/verify-report.sh
- Verify command: ./verify.sh
- Acceptance check: run: ./tests/verify-report.sh

Harden the `template/.orchestration/verify.sh --run-verify REPORT.md` command
execution boundary. Claude Fable previously demonstrated that the current
external-action denylist can be bypassed with wrappers such as `sh -c` and
destructive spellings such as `rm -R`. The verifier must fail closed before
executing commands that contain shell composition or external/destructive
effects.

Use a small, auditable capability profile rather than trying to expand a
denylist. Preserve the repository's documented supported workflow, including
the existing `./verify.sh` re-execution. At minimum, reject command strings
containing pipes, lists, redirects, command substitution, backgrounding,
wrapper/interpreter executables, network utilities, and destructive utilities.
Do not invoke a shell to interpret the recorded command beyond the existing
controlled execution model. Keep output bounded and preserve current report
validation behavior.

Add adversarial regression cases to `tests/verify-report.sh` covering `sh -c`,
`bash -c`, `rm -R`, pipes, redirects, command substitution, and a permitted
local `./verify.sh` command. Run `./verify.sh` and the focused test suite.

Write `.orchestration/reports/CLAUDE-OPUS-harden-run-verify-safety.md` with
the required identity fields, exact policy, tests, and remaining risks. Do
not commit, push, or create a PR. Send worker_done.
