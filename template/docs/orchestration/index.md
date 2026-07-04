# Orchestration — operating card

Read when: dispatching, supervising, or executing work as coordinator or worker.

## Model

- **Coordinator** (the interactive session): plans, dispatches, verifies, commits, updates Linear. Does not implement worker tasks itself.
- **Workers**: project-scoped roles (roster in `AGENTS.md`), spawned yolo/non-interactive, one per worktree. **Workers never commit.**
- Planning/decision reviews → Claude Code model `fable` first. Engineering → codex/agy with project roles.

## Dispatch checklist (every task)

1. Linear issue exists (`{{ISSUE_PREFIX}}-xx`) and is unblocked per [`../gates/index.md`](../gates/index.md).
2. Write prompt file `.orchestration/prompts/{{ISSUE_PREFIX}}-xx-<role>-<slug>.md` (lowercase prefix): role file, scope, allowed files, acceptance criteria, "do not commit".
3. Spawn worker per substrate rules: [`orca.md`](./orca.md).
4. Worker writes `.orchestration/reports/{{ISSUE_PREFIX}}-xx-<role>-<slug>.md` (same basename as prompt).
5. Coordinator: `{{VERIFY_CMD}}` → commit as `<role>: <summary> ({{ISSUE_PREFIX}}-xx)` → update Linear per [`linear.md`](./linear.md).

## Detail

| File | Covers |
| --- | --- |
| [`orca.md`](./orca.md) | Spawn flags, stability rules, hang recovery, substrate fallback |
| [`linear.md`](./linear.md) | Status flow, branch naming, who updates what |
