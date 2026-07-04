# Task tracker rules

Read when: creating, dispatching, blocking, or closing work items.

- Backlog lives in {{TASK_TRACKER_DETAILS}}.
- **No work without a tracked issue/task.** Create one before dispatching anything, including meta/process work.
- Branch names: use the tracker-provided branch name when available; otherwise use `{{ISSUE_PREFIX_LOWER}}-xx-<slug>`.
- Status flow: `Todo` → `In Progress` (on dispatch) → `In Review` (report landed, awaiting verify) → `Done` (verified + committed). Blocked work: comment on the issue/task linking the gate row in `docs/gates/index.md`; do not start it.
- The coordinator updates {{TASK_TRACKER_NAME}} — workers do not need tracker access. On completion, post the prompt + report paths as an issue/task comment when the tracker supports comments.
- Commits reference the issue/task: `<role>: <summary> ({{ISSUE_PREFIX}}-xx)`.
