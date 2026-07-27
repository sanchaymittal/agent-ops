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

## Supervision

Delete this section if the task dispatches no workers. Otherwise fill both
fields before dispatch — `verify.sh` rejects a report whose prompt still
carries an unresolved placeholder.

- Supervision window: <SUPERVISION_WINDOW> — never below 15 minutes.
- Re-dispatch cap: <REDISPATCH_CAP> review → fix rounds, then escalate.

One blocking wait covering every outstanding worker, at the window above.
Never one wait per worker, never a poll loop between waits. A timeout is a
checkpoint: re-wait at the same window.

Prefer a path where the wait happens **outside** the model loop — the
coordinator ends its turn and the substrate re-invokes it on the event. Wall
clock is free; wall clock held open inside a tool call is not. If the
substrate offers no such path, block in as few calls as possible:

```sh
# Two numbers, and the smaller one is the rule. The window below is the
# floor; the *yield* is how long the shell harness holds the call open
# before returning "still running", and it is what actually decides how
# often the coordinator wakes. Measured: a coordinator declared a
# one-minute window and woke every 30s anyway, because its yield was 30s.
# The window never bound. Raising the window while leaving the yield at
# 30s makes it worse -- a 15-minute window then costs 30 keepalive
# round-trips instead of 2.
orca orchestration check --wait --types worker_done --timeout-ms 900000 --json
# ...issued with the largest yield the substrate allows (300000 ms is the
# largest observed on Codex exec_command). Set both, or neither helps.
```

One wait covers every outstanding worker. Do not follow it with a per-worker
`terminal read` to see what each one is doing — measured, that habit was 83
extra round-trips across two sessions for information the completion event
already carries.

## Permissions

- Filesystem: worktree-only writes.
- Network: denied unless this task explicitly grants it.
- External actions: denied unless this task explicitly grants them.

## Stop conditions

- Stop on an unavailable capability, a blocked gate, an out-of-scope path, truncated evidence, or a second patch-context miss on one file.
- Return `blocked: missing <item>` or `blocked: decision: <question>`; never guess past the blocker.
