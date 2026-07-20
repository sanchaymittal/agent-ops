# agent-ops

Operating system for multi-agent repos: one thin `AGENTS.md` contract, CAG-style docs indexes, optional issue-tracker integration, hash-bound prompt-to-report evidence, and a 9-role roster shipped for four CLIs (Claude Code, Codex, agy/Antigravity, OpenCode). Model allocation is yours to choose at init — any CLI that reads `AGENTS.md` (hermes, claude/fable, codex, agy, opencode, …) can fill any slot; the protocol and role files stay the same.

## Apply to a repo

```sh
./init.sh TARGET_DIR PROJECT_NAME ISSUE_PREFIX [VERIFY_CMD]
./init.sh ~/github/example-app example-app EX "npm run verify"

# Optional Linear wiring
LINEAR_TEAM=eng LINEAR_PROJECT=example-app ./init.sh ~/github/example-app example-app EX "npm run verify"

# Optional model allocation (defaults: COORDINATOR=codex PLANNER=fable CODER=agy REVIEWER=codex)
# e.g. Hermes coordinates, fable plans AND codes, codex reviews:
COORDINATOR=hermes CODER=fable ./init.sh ~/github/example-app example-app EX "npm run verify"
```

`CODER` and `REVIEWER` must differ — the cross-model review rule (author never reviews own change) is enforced at init.

Allocation is modular: init writes the slot→model table into `docs/orchestration/models.md` and every other doc names slots (COORDINATOR/PLANNER/CODER/REVIEWER) only. Swap a model later by editing that one table — no re-init.

```sh
# Optional codebase map for large repos: agents navigate a generated wiki instead of grepping
GRAPHIFY=1 ./init.sh ~/github/example-app example-app EX "npm run verify"
```

`GRAPHIFY=1` only adds the pointer row in `docs/index.md`; generating `graphify-out/wiki/` is your tooling's job, and the row says so — a stale map is worse than grep. Skip it for small repos: the CAG indexes already cover them.

Works on new and existing repos. Refuses to overwrite any managed file that already exists in `TARGET_DIR`. Ships only `AGENTS.md`, `CLAUDE.md`, `docs/`, `.orchestration/`, and `*/agents/` role files; existing settings (`.claude/settings.json` etc.) are untouched.

Then, in the target repo:

1. `AGENTS.md` — fill both `TODO(project)` blocks (project description, layout table).
2. Create or refresh `README.md` if the target repo does not already have one.
3. `docs/gates/index.md` — one row per human-provisioned dependency (infra, credentials, external data, owner decisions).
4. Ensure the verify command exists and is green; it is the definition of done.
5. Run `./.orchestration/verify.sh --diff-sha` once to confirm the evidence tool works in the initialized Git repo.
6. Commit. Configure the repo's issue tracker if it needs an external backlog.

## What you get

```
AGENTS.md              # thin contract: read protocol, non-negotiables, task tracker, roster
CLAUDE.md -> AGENTS.md # all four CLIs read one file
docs/
  index.md             # concern router + CAG read protocol
  gates/               # live blocker table (index) + per-gate detail (blockers.md)
  orchestration/       # dispatch checklist + task tracker + escalation advisor + optional Linear adapter + orca.md
  product/ runbooks/ engineering/   # skeleton indexes, fill as the project grows
.orchestration/        # prompt/report templates + hash/scope verifier + immutable dispatch records
.claude/agents/ .codex/agents/ .agents/agents/ .opencode/agents/   # same 9 roles each
```

## The protocol

- **CAG reads:** always load `AGENTS.md` + `docs/index.md` + `docs/gates/index.md`; concern indexes on touch; leaf docs only when an index says so. Indexes ≤ 40 lines.
- **Issue-tracker-first:** no work without an issue/task, including meta/process work. Linear is supported but optional.
- **Dispatch:** issue/task → prompt from `TEMPLATE.md` → preflight + writer lease → least-privilege worker → hash-bound report → report verifier → coordinator verify/review → commit → tracker update.
- **Completion:** a `done` report must carry an `Acceptance check` (`run: <command>` or `artifact: <path>`) matching its prompt plus non-empty evidence; `.orchestration/verify.sh --run-verify <report>` re-executes the verify command after the final edit and refuses commands with external effects.
- **Stability:** prompt files are the idempotent dispatch unit — hung worker = preserve evidence + respawn the same file in a fresh worktree; orchestrator substrate down = same protocol via subagents or a plain terminal.
- **Escalation:** verify fails twice or a worker returns `blocked: decision:` → coordinator one-shot consults PLANNER (the advisor), appends the advice to the prompt file, respawns the same file; max 2 consults per issue, then escalate to a human.

## Verify this template

Run `./verify.sh`. It checks shell syntax, clean-install and failure behavior, report/diff attestation, CAG index budgets, cross-CLI role-body parity, and whitespace errors.

## License

MIT. See [LICENSE](./LICENSE).
