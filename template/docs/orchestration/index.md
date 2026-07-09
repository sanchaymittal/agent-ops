# Orchestration — operating card

Read when: dispatching, supervising, or executing work as coordinator or worker.

## Model

- **Coordinator** (the interactive session): plans, dispatches, verifies, commits, updates the configured tracker. Does not implement worker tasks itself.
- **Workers**: project-scoped roles (roster in `AGENTS.md`), spawned yolo/non-interactive, one per worktree. **Workers never commit.**
- Dispatch independent issues in parallel, one worker per worktree each; serialize anything touching the same files.

## Model allocation

Slot→model bindings live in one place: [`models.md`](./models.md). Docs (including this one) name slots — COORDINATOR, PLANNER, CODER, REVIEWER, MISC — never models. Verifying dispatches the COORDINATOR coordinated is fine; reviewing code it authored is not (cross-model review rule, in `models.md`).

## Dispatch checklist (every task)

1. Tracked issue/task exists (`{{ISSUE_PREFIX}}-xx`) and is unblocked per [`../gates/index.md`](../gates/index.md).
2. Write prompt file `.orchestration/prompts/{{ISSUE_PREFIX_LOWER}}-xx-<role>-<slug>.md`: role file, scope, allowed files, acceptance criteria, "do not commit". Hard task → consult per [escalation.md](./escalation.md) before spawn.
3. Spawn worker per substrate rules: [`orca.md`](./orca.md).
4. Worker writes `.orchestration/reports/{{ISSUE_PREFIX_LOWER}}-xx-<role>-<slug>.md` (same basename as prompt).
5. Coordinator: `{{VERIFY_CMD}}` (fails twice → [escalation.md](./escalation.md)) → commit as `<role>: <summary> ({{ISSUE_PREFIX}}-xx)` → {{TASK_TRACKER_UPDATE}} per [`tasks.md`](./tasks.md).

## Detail

| File | Covers |
| --- | --- |
| [`models.md`](./models.md) | Slot→model bindings — the only file to edit when swapping a model |
| [`orca.md`](./orca.md) | Spawn flags, stability rules, hang recovery, substrate fallback |
| [`tasks.md`](./tasks.md) | Generic tracker rules, status flow, branch naming, who updates what |
| [`linear.md`](./linear.md) | Optional Linear-specific adapter rules |
| [`escalation.md`](./escalation.md) | Advisor triggers, consult mechanic, budget |
