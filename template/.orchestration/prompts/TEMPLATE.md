# <TASK_ID> — task title

- Task ID: <TASK_ID>
- Attempt: <ATTEMPT>
- Role: <ROLE>
- Base SHA: <BASE_SHA>
- Risk tier: <RISK_TIER>
- Allowed paths: <ALLOWED_PATHS>
- Verify command: {{VERIFY_CMD}}
- Acceptance check: <ACCEPTANCE_CHECK>

## Scope

State the required outcome and the behavior that must not change.

## Acceptance criteria

- One observable, testable requirement per bullet.

## Required verification

- State the acceptance check as `run: <command>` or `artifact: <path>`; the report must repeat it verbatim and cite its result under `Acceptance evidence`.
- Run the verify command after the final edit and record its exit code.
- Run focused checks while iterating; preserve long output as an artifact.
- Run `git diff --check`, inspect status/untracked files, then compute `./.orchestration/verify.sh --diff-sha`.

## Permissions

- Filesystem: worktree-only writes.
- Network: denied unless this task explicitly grants it.
- External actions: denied unless this task explicitly grants them.

## Stop conditions

- Stop on an unavailable capability, a blocked gate, an out-of-scope path, truncated evidence, or a second patch-context miss on one file.
- Return `blocked: missing <item>` or `blocked: decision: <question>`; never guess past the blocker.
