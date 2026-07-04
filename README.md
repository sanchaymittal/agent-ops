# agent-ops-template

Operating system for multi-agent repos, extracted from munshi (SAN-30/SAN-31): one thin `AGENTS.md` contract, CAG-style docs indexes, Linear-first task management, prompt→report dispatch protocol, and a 9-role roster for four CLIs (Claude Code, Codex, agy/Antigravity, OpenCode).

## Apply to a repo

```sh
./init.sh TARGET_DIR PROJECT_NAME LINEAR_TEAM LINEAR_PROJECT ISSUE_PREFIX [VERIFY_CMD]
./init.sh ~/github/myapp myapp sanchay myapp MYA "npm run verify"
```

Works on new and existing repos. Refuses to run if `TARGET_DIR/AGENTS.md` exists. Ships only `AGENTS.md`, `docs/`, `.orchestration/`, and `*/agents/` role files — existing settings (`.claude/settings.json` etc.) are untouched.

Then, in the target repo:

1. `AGENTS.md` — fill both `TODO(project)` blocks (project description, layout table).
2. `docs/gates/index.md` — one row per human-provisioned dependency (infra, credentials, external data, owner decisions).
3. Ensure the verify command exists and is green; it is the definition of done.
4. Commit. Create the Linear team/project if it doesn't exist.

## What you get

```
AGENTS.md              # thin contract: read protocol, non-negotiables, Linear, roster
CLAUDE.md -> AGENTS.md # all four CLIs read one file
docs/
  index.md             # concern router + CAG read protocol
  gates/               # live blocker table (index) + per-gate detail (blockers.md)
  orchestration/       # dispatch checklist (index) + orca.md + linear.md
  product/ runbooks/ engineering/   # skeleton indexes, fill as the project grows
.orchestration/        # prompts/ + reports/ dispatch records (README documents conventions)
.claude/agents/ .codex/agents/ .agents/agents/ .opencode/agents/   # same 9 roles each
```

## The protocol

- **CAG reads:** always load `AGENTS.md` + `docs/index.md` + `docs/gates/index.md`; concern indexes on touch; leaf docs only when an index says so. Indexes ≤ 40 lines.
- **Linear-first:** no work without an issue, including meta/process work.
- **Dispatch:** issue → prompt file → yolo non-interactive worker (one per worktree, never commits) → report file → coordinator verifies → commit `<role>: <summary> (PREFIX-xx)` → Linear updated.
- **Stability:** prompt files are the idempotent dispatch unit — hung worker = kill + respawn same file; orchestrator substrate down = same protocol via subagents or a plain terminal.
