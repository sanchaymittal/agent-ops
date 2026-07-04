# Linear task rules

Read when: creating, dispatching, blocking, or closing work items.

- Backlog lives in Linear: team `{{LINEAR_TEAM}}`, project `{{LINEAR_PROJECT}}`, issues `{{ISSUE_PREFIX}}-xx`.
- **No work without an issue.** Create one before dispatching anything, including meta/process work.
- Branch names: use Linear's `gitBranchName` when branching.
- Status flow: `Todo` → `In Progress` (on dispatch) → `In Review` (report landed, awaiting verify) → `Done` (verified + committed). Blocked work: comment on the issue linking the gate row in `docs/gates/index.md`; do not start it.
- The coordinator updates Linear — workers have no MCP access. On completion, post the prompt + report paths as an issue comment.
- Commits reference the issue: `<role>: <summary> ({{ISSUE_PREFIX}}-xx)`.
