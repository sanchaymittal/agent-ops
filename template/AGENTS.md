# {{PROJECT_NAME}} — Agent Operating Contract

Every agent CLI working in this repo (Claude Code, Codex, agy/Antigravity, Grok, OpenCode, Hermes, or any other that reads `AGENTS.md`) follows this file. `CLAUDE.md` symlinks here so every CLI reads one contract. Humans start at `README.md` when present; otherwise start here until the project README exists.

## What this repo is

TODO(project): 2–3 lines — what this product is. When scope exists, freeze it in `docs/product/positioning.md` and state here: scope additions require editing that doc first.

## Read protocol (CAG — keep context small)

1. Always load: this file → `docs/index.md` → `docs/gates/index.md`. Nothing else by default.
2. Task touches a concern → read that concern's `index.md`; leaf docs only when the index says so.
3. Never bulk-read `docs/`. Indexes stay ≤ 40 lines; leaf docs carry a one-line `Read when:` header.

## Non-negotiables

- Never invent product requirements, integrations, credentials, identifiers, metrics, user data, or test results. Missing data → name exactly what is missing and stop.
- Never assume human-provisioned infra. A gate opens only when its row in `docs/gates/index.md` records a real value.
- Never commit secrets or private user data. `{{VERIFY_CMD}}` is the definition of done for any code change.
- Smallest verifiable change, with tests or smoke checks. Report exact files changed and commands run.

## Working method (every slot, every model)

The method is the contract — whichever CLI fills a slot, it works like this:

- Understand first: read every file the change touches and trace the flow end to end before editing. No pattern-match patches.
- Root cause over symptom: before changing shared code, check its callers; fix once, where all paths converge.
- Prefer deletion and reuse over addition. No speculative abstraction, config, or scaffolding.
- Verify by execution: run the check and read its output before claiming anything. A claim without a run is invention.
- Report outcome first: `done`, `blocked: missing <item>`, or `blocked: decision: <question>` in the first line, failures quoted verbatim, deviations from the prompt named.
- Parallel when independent, serial when coupled — never two writers in one worktree.

## Task management

Backlog lives in {{TASK_TRACKER_DETAILS}}. **No work without a tracked issue/task.** Rules: `docs/orchestration/tasks.md`. Linear-specific rules are optional: `docs/orchestration/linear.md`.

## Orchestration — coordinator/worker

- The coordinator plans, dispatches, verifies, commits, and updates the configured tracker. Workers implement. **Workers never commit.**
- Dispatch = tracked issue/task → prompt file → worker → report file → verify → commit. Checklist: `docs/orchestration/index.md`. Orca substrate + stability rules: `docs/orchestration/orca.md`.
- Model allocation is modular: docs name slots (COORDINATOR orchestrates, PLANNER advises + escalation consults, CODER implements, REVIEWER reviews); the slot→model table lives only in `docs/orchestration/models.md`. Swap a model there — nothing else changes.
- Slots are bindings, not identities: any CLI can fill any slot; the protocol and role files do not change with the model.
- Cross-model review: the model that authored a change never reviews it.
- Typo-class changes (no behavior, no design choice) → coordinator fixes inline and commits; the dispatch ceremony is for real tasks.
- Every commit and report names the exact role used: `<role>: <summary> ({{ISSUE_PREFIX}}-xx)`.

## Roster (project-scoped roles)

Same 9 roles in each CLI dir: `.claude/agents/` (Claude), `.codex/agents/` (Codex), `.agents/agents/` (agy), `.opencode/agents/` (OpenCode). CLIs without a native roster dir (e.g. Hermes, Grok) load the role file by path from the dispatch prompt.

| Role | Use for |
| --- | --- |
| `engineering-minimal-change-engineer` | Default implementation — smallest correct diff |
| `engineering-backend-architect` | Services, APIs, data-store design |
| `engineering-frontend-developer` | UI work |
| `engineering-ai-engineer` | LLM features, classification, retrieval pipelines |
| `engineering-prompt-engineer` | Prompt design + evals |
| `engineering-devops-automator` | CI, env management, deploy pipeline |
| `engineering-code-reviewer` | Review of worker output |
| `engineering-software-architect` | Architecture/planning reviews (pairs with the PLANNER slot) |
| `engineering-technical-writer` | Docs — must respect the CAG budgets above |

## Layout

TODO(project): keep one line per path; keep the two rows below.

| Path | What |
| --- | --- |
| `docs/` | Concern-indexed documentation — start at `docs/index.md` |
| `.orchestration/` | Dispatch prompts + worker reports (see its README) |
