# agent-ops

Operating system for multi-agent repos: one thin `AGENTS.md` contract, CAG-style docs indexes, optional issue-tracker integration, prompt-to-report dispatch protocol, and a 9-role roster for four CLIs (Claude Code, Codex, agy/Antigravity, OpenCode).

## Apply to a repo

```sh
./init.sh TARGET_DIR PROJECT_NAME ISSUE_PREFIX [VERIFY_CMD]
./init.sh ~/github/example-app example-app EX "npm run verify"

# Optional Linear wiring
LINEAR_TEAM=eng LINEAR_PROJECT=example-app ./init.sh ~/github/example-app example-app EX "npm run verify"
```

Works on new and existing repos. Refuses to overwrite any managed file that already exists in `TARGET_DIR`. Ships only `AGENTS.md`, `CLAUDE.md`, `docs/`, `.orchestration/`, and `*/agents/` role files; existing settings (`.claude/settings.json` etc.) are untouched.

Then, in the target repo:

1. `AGENTS.md` — fill both `TODO(project)` blocks (project description, layout table).
2. Create or refresh `README.md` if the target repo does not already have one.
3. `docs/gates/index.md` — one row per human-provisioned dependency (infra, credentials, external data, owner decisions).
4. Ensure the verify command exists and is green; it is the definition of done.
5. Commit. Configure the repo's issue tracker if it needs an external backlog.

## What you get

```
AGENTS.md              # thin contract: read protocol, non-negotiables, task tracker, roster
CLAUDE.md -> AGENTS.md # all four CLIs read one file
docs/
  index.md             # concern router + CAG read protocol
  gates/               # live blocker table (index) + per-gate detail (blockers.md)
  orchestration/       # dispatch checklist + task tracker + optional Linear adapter + orca.md
  product/ runbooks/ engineering/   # skeleton indexes, fill as the project grows
.orchestration/        # prompts/ + reports/ dispatch records (README documents conventions)
.claude/agents/ .codex/agents/ .agents/agents/ .opencode/agents/   # same 9 roles each
```

## The protocol

- **CAG reads:** always load `AGENTS.md` + `docs/index.md` + `docs/gates/index.md`; concern indexes on touch; leaf docs only when an index says so. Indexes ≤ 40 lines.
- **Issue-tracker-first:** no work without an issue/task, including meta/process work. Linear is supported but optional.
- **Dispatch:** issue/task → prompt file → yolo non-interactive worker (one per worktree, never commits) → report file → coordinator verifies → commit `<role>: <summary> (PREFIX-xx)` → tracker updated.
- **Stability:** prompt files are the idempotent dispatch unit — hung worker = kill + respawn same file; orchestrator substrate down = same protocol via subagents or a plain terminal.

## License

MIT. See [LICENSE](./LICENSE).
