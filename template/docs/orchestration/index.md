# Orchestration — operating card

Read when: dispatching, supervising, or executing work as coordinator or worker.

## Model

- **Coordinator** (the interactive session): plans, dispatches, verifies, commits, updates the configured tracker. Does not implement worker tasks itself.
- **Workers**: project-scoped roles (roster in `AGENTS.md`), spawned yolo/non-interactive, one per worktree. **Workers never commit.**

## Model allocation

| Slot | Model | Notes |
| --- | --- | --- |
| Coordinator | codex | Runs the checklist below; must have tracker access when an external tracker is configured. Verifying dispatches it coordinated is fine; reviewing code it authored is not. |
| Planning / decision review | Claude `fable` | Architecture, gates, tie-breaks — not misc work |
| Implementation | agy (Antigravity) | Default coder, with project roles |
| Review | codex | `engineering-code-reviewer` role |
| Misc / cheap | agy / codex / free models | Never `fable` |

Cross-model review rule: the model that authored a change never reviews it (agy writes → codex reviews; codex writes → agy or `fable` reviews).

## Dispatch checklist (every task)

1. Tracked issue/task exists (`{{ISSUE_PREFIX}}-xx`) and is unblocked per [`../gates/index.md`](../gates/index.md).
2. Write prompt file `.orchestration/prompts/{{ISSUE_PREFIX_LOWER}}-xx-<role>-<slug>.md`: role file, scope, allowed files, acceptance criteria, "do not commit".
3. Spawn worker per substrate rules: [`orca.md`](./orca.md).
4. Worker writes `.orchestration/reports/{{ISSUE_PREFIX_LOWER}}-xx-<role>-<slug>.md` (same basename as prompt).
5. Coordinator: `{{VERIFY_CMD}}` → commit as `<role>: <summary> ({{ISSUE_PREFIX}}-xx)` → {{TASK_TRACKER_UPDATE}} per [`tasks.md`](./tasks.md).

## Detail

| File | Covers |
| --- | --- |
| [`orca.md`](./orca.md) | Spawn flags, stability rules, hang recovery, substrate fallback |
| [`tasks.md`](./tasks.md) | Generic tracker rules, status flow, branch naming, who updates what |
| [`linear.md`](./linear.md) | Optional Linear-specific adapter rules |
