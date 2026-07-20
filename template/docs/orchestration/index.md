# Orchestration — operating card

Read when: dispatching, supervising, or executing work as coordinator or worker.

## Model

- **Coordinator** (the interactive session): plans, dispatches, verifies, commits, updates the configured tracker. Does not implement worker tasks itself.
- **Workers**: project-scoped roles (roster in `AGENTS.md`), spawned non-interactive with the least-privilege capability profile, one writer lease per worktree. **Workers never commit.**
- Dispatch independent issues in parallel, one worker per worktree each; serialize anything touching the same files.

## Model allocation

Slot→model bindings live in one place: [`models.md`](./models.md). Docs (including this one) name slots — COORDINATOR, PLANNER, CODER, REVIEWER, MISC — never models. Verifying dispatches the COORDINATOR coordinated is fine; reviewing code it authored is not (cross-model review rule, in `models.md`).

## Dispatch checklist (every task)

1. Tracked issue/task exists (`{{ISSUE_PREFIX}}-xx`) and is unblocked per [`../gates/index.md`](../gates/index.md).
2. Copy `.orchestration/prompts/TEMPLATE.md` to `.orchestration/prompts/{{ISSUE_PREFIX_LOWER}}-xx-<role>-<slug>.md`; fill every identity, scope, permission, acceptance, and verification field. Hard task → consult [escalation.md](./escalation.md).
3. `.orchestration/preflight.sh --verify-cmd '{{VERIFY_CMD}}' --base-sha <sha> --cli <cli> --role <role>`, then `.orchestration/lease.sh acquire --dispatch {{ISSUE_PREFIX}}-xx`; spawn with the narrowest capability profile per [`orca.md`](./orca.md). Any `blocked:` line → fix the cause, do not spawn.
4. Worker writes the matching report from `.orchestration/reports/TEMPLATE.md`, runs final checks after the last edit, records the diff SHA, then runs `.orchestration/verify.sh <report>`.
5. Coordinator runs `.orchestration/verify.sh --run-verify <report>` (re-runs `{{VERIFY_CMD}}` itself) plus independent review against the same diff SHA (two verify failures → [escalation.md](./escalation.md)).
6. Commit as `<role>: <summary> ({{ISSUE_PREFIX}}-xx)` only after all evidence is green, then {{TASK_TRACKER_UPDATE}} per [`tasks.md`](./tasks.md).

## Detail

| File | Covers |
| --- | --- |
| [`models.md`](./models.md) | Slot→model bindings — the only file to edit when swapping a model |
| [`orca.md`](./orca.md) | Spawn flags, stability rules, hang recovery, substrate fallback |
| [`tasks.md`](./tasks.md) | Generic tracker rules, status flow, branch naming, who updates what |
| [`linear.md`](./linear.md) | Optional Linear-specific adapter rules |
| [`escalation.md`](./escalation.md) | Advisor triggers, consult mechanic, budget |
