# {{PROJECT_NAME}} — Agent Operating Contract

Every agent (Claude Code, Codex, agy/Antigravity, OpenCode) working in this repo follows this file. `CLAUDE.md` symlinks here so all four CLIs read one contract. Humans start at `README.md` when present; otherwise start here until the project README exists.

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

## Task management — Linear

Backlog lives in Linear: team `{{LINEAR_TEAM}}`, project `{{LINEAR_PROJECT}}`, issues `{{ISSUE_PREFIX}}-xx`. **No work without an issue.** Rules: `docs/orchestration/linear.md`.

## Orchestration — coordinator/worker

- The coordinator plans, dispatches, verifies, commits, and updates Linear. Workers implement. **Workers never commit.**
- Dispatch = Linear issue → prompt file → worker → report file → verify → commit. Checklist: `docs/orchestration/index.md`. Orca substrate + stability rules: `docs/orchestration/orca.md`.
- Model allocation: coordinator = codex (must have Linear MCP); planning + decision reviews = Claude `fable` first; implementation = agy; review = codex; misc/cheap work = agy/codex/free models — never `fable`.
- Cross-model review: the model that authored a change never reviews it.
- Every commit and report names the exact role used: `<role>: <summary> ({{ISSUE_PREFIX}}-xx)`.

## Roster (project-scoped roles)

Same 9 roles in each CLI dir: `.claude/agents/` (Claude), `.codex/agents/` (Codex), `.agents/agents/` (agy), `.opencode/agents/` (OpenCode).

| Role | Use for |
| --- | --- |
| `engineering-minimal-change-engineer` | Default implementation — smallest correct diff |
| `engineering-backend-architect` | Services, APIs, data-store design |
| `engineering-frontend-developer` | UI work |
| `engineering-ai-engineer` | LLM features, classification, retrieval pipelines |
| `engineering-prompt-engineer` | Prompt design + evals |
| `engineering-devops-automator` | CI, env management, deploy pipeline |
| `engineering-code-reviewer` | Review of worker output |
| `engineering-software-architect` | Architecture/planning reviews (pairs with `fable`) |
| `engineering-technical-writer` | Docs — must respect the CAG budgets above |

## Layout

TODO(project): keep one line per path; keep the two rows below.

| Path | What |
| --- | --- |
| `docs/` | Concern-indexed documentation — start at `docs/index.md` |
| `.orchestration/` | Dispatch prompts + worker reports (see its README) |
