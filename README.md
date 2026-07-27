# agent-ops

An operating contract for repos where more than one agent — and more than one model — writes code.

Coding agents are good at editing files and bad at everything around it: they read too much context, invent facts they cannot check, claim a task is done without running anything, and burn a coordinator's budget watching workers instead of dispatching them. agent-ops is the layer that makes those failures impossible rather than discouraged: a thin contract every CLI reads, a bounded read protocol, and executable gates that reject unverifiable work.

**Goal:** a change lands only when a tracked issue asked for it, a lease said one writer owned the tree, a prompt file scoped it, a report proved it, a verifier re-ran the check against the exact diff being committed, and a different model than the author reviewed it. Nothing in that chain depends on an agent's good intentions.

---

## Three ways in

### 1. New or empty repo — run init.sh

```sh
./init.sh TARGET_DIR PROJECT_NAME ISSUE_PREFIX [VERIFY_CMD]
./init.sh ~/github/example-app example-app EX "npm run verify"
```

```sh
# Optional Linear wiring (both vars or neither)
LINEAR_TEAM=eng LINEAR_PROJECT=example-app ./init.sh ~/github/example-app example-app EX "npm run verify"

# Optional model allocation (defaults: COORDINATOR=codex PLANNER=fable CODER=agy REVIEWER=codex)
# e.g. Hermes coordinates, fable plans AND codes, codex reviews:
COORDINATOR=hermes CODER=fable ./init.sh ~/github/example-app example-app EX "npm run verify"

# Optional codebase map for large repos: agents navigate a generated wiki instead of grepping
GRAPHIFY=1 ./init.sh ~/github/example-app example-app EX "npm run verify"
```

`CODER` and `REVIEWER` must differ — the cross-model review rule (author never reviews own change) is enforced at init, not left as advice.

`GRAPHIFY=1` only adds the pointer row in `docs/index.md`; generating `graphify-out/wiki/` is your tooling's job, and the row says so — a stale map is worse than grep. Skip it for small repos: the CAG indexes already cover them.

The install is atomic: the whole payload is rendered into a staging dir first, so a failed substitution or a missing optional feature never leaves a half-installed repo. Only `AGENTS.md`, `CLAUDE.md`, `docs/`, `.orchestration/`, and `*/agents/` role files are shipped; existing settings (`.claude/settings.json` and friends) are never touched.

### 2. Existing repo — paste this prompt into any agent CLI, from inside that repo

`init.sh` refuses when a managed path already exists (your own `CLAUDE.md`, your own `docs/`), so let an agent do the merge:

```text
Clone https://github.com/sanchaymittal/agent-ops to a temp dir, read its README,
run its init.sh into an empty scratch dir with parameters taken from THIS repo
(ask me for any you can't determine — especially VERIFY_CMD and the CODER/REVIEWER
models, which must differ), then merge that payload here: copy what's missing,
hand-merge what exists, never overwrite, never touch settings/CI/README. Fill the
TODO(project) blocks from real repo content only — invent nothing. Verify with
./.orchestration/verify.sh --diff-sha and report before committing.
```

### 3. Already on agent-ops — paste this to update

```text
Recover this repo's init parameters from AGENTS.md, docs/orchestration/models.md,
and docs/orchestration/tasks.md. Clone https://github.com/sanchaymittal/agent-ops,
run its init.sh with those exact parameters into an empty scratch dir, and diff it
against this repo's managed paths (AGENTS.md, docs/, .orchestration/, */agents/).
Take upstream's version where I haven't edited, hand-merge where I have (TODO
blocks, gates rows, layout, models table), never touch .orchestration/prompts or
reports except TEMPLATE.md — those are immutable history. Then tell me what
changed in the protocol itself.
```

Both prompts re-render through `init.sh` rather than copying `template/` directly — the payload is placeholder-substituted, so a raw `template/` diff is mostly `{{VERIFY_CMD}}` noise.

## After install, in the target repo

1. `AGENTS.md` — fill both `TODO(project)` blocks (project description, layout table).
2. Create or refresh `README.md` if the repo does not already have one.
3. `docs/gates/index.md` — one row per human-provisioned dependency (infra, credentials, external data, owner decisions).
4. Ensure the verify command exists and is green; it is the definition of done.
5. Run `./.orchestration/verify.sh --diff-sha` once to confirm the evidence tool works in the initialized Git repo.
6. Commit. Configure the repo's issue tracker if it needs an external backlog.

---

## What you get

```
AGENTS.md              # thin contract: read protocol, non-negotiables, working method, tracker, roster
CLAUDE.md -> AGENTS.md # symlink, so every CLI reads one file
docs/
  index.md             # concern router + CAG read protocol
  gates/               # live blocker table (index) + per-gate detail (blockers.md)
  orchestration/       # dispatch checklist, model bindings, tracker rules, supervision, escalation, optional Linear adapter
  product/ runbooks/ engineering/   # skeleton indexes, fill as the project grows
.orchestration/        # prompt/report templates + preflight + writer lease + hash/scope verifier + burn meter
.claude/agents/ .codex/agents/ .agents/agents/ .opencode/agents/   # the same 9 roles, four CLI formats
```

### The contract — `AGENTS.md`

One file, symlinked as `CLAUDE.md`, read by every CLI that honors either name (Claude Code, Codex, agy/Antigravity, OpenCode, Hermes, …). It carries the read protocol, the non-negotiables ("never invent requirements, credentials, metrics, or test results"), the working method every slot follows regardless of model, the task-tracker rule, the orchestration model, and the roster. It is deliberately short; everything else is behind an index.

### CAG read protocol — bounded context by construction

Context-augmented generation, enforced by budget rather than by hope:

- Always load `AGENTS.md` → `docs/index.md` → `docs/gates/index.md`. Nothing else by default.
- A task that touches a concern reads that concern's `index.md`; a leaf doc only when the index says it matters.
- Never bulk-read `docs/`. Every `index.md` stays ≤ 40 lines — `verify.sh` fails the repo if one grows past it.
- Stateful data (gate status) lives in indexes; prose detail lives in leaf docs with a one-line `Read when:` header.

### Gates — no work on unprovisioned infra

`docs/gates/index.md` is a live table of everything a human must provide: credentials, infra, external data, owner decisions. A gate opens **only** when its row records a real value. A task touching a `blocked` row must not start. `blockers.md` holds the owner actions, ordered by external latency, plus a "what agents CAN do while blocked" section so blocked never means idle.

### Dispatch — issue → prompt → report → verify → commit

Coordinator plans, dispatches, verifies, commits, and updates the tracker. Workers implement. **Workers never commit.** The full path for every task:

1. A tracked issue exists and is unblocked per the gates table.
2. Copy `.orchestration/prompts/TEMPLATE.md` → `<prefix>-xx-<role>-<slug>.md`; fill identity, scope, allowed paths, permissions, acceptance check, stop conditions. **The prompt file is the idempotent dispatch unit** — a hung worker is respawned from the same file in a fresh worktree, never patched mid-flight.
3. `preflight.sh` + `lease.sh acquire`, then spawn with the narrowest capability profile.
4. Worker writes the matching report from `reports/TEMPLATE.md`, runs final checks after the last edit, records the diff SHA, runs `verify.sh <report>`.
5. Coordinator runs `verify.sh --run-verify <report>` and an independent review against the same diff SHA.
6. Commit as `<role>: <summary> (<prefix>-xx)`, then update the tracker.

Prompts and reports are immutable history once a dispatch completes.

### Preflight — fail before spending context

`.orchestration/preflight.sh --verify-cmd CMD [--base-sha SHA] [--cli NAME] [--role NAME]` runs before a worker loads any task context. It checks that it is inside a Git worktree, that HEAD is the dispatch base SHA, that the verify command's program is executable or on PATH, that the CLI exists, that the role is in the *local roster* (the actual role files, not the docs table), and that the writer lease is free. Everything is local — no network, no model API, nothing that can pass for the wrong reason. Failures are structured: `blocked: capability|task|lease: <detail>` with a non-zero exit. Quota, gates, and credentials remain deliberately manual.

### Writer lease — one writer per worktree

`.orchestration/lease.sh acquire --dispatch ID | release | status`. The lock is an atomic `mkdir` of `.orchestration/.lease/` — POSIX-atomic everywhere, and gitignored so a held lease can never perturb the diff SHA. A second acquirer is rejected without touching the winner's record. Release is owner-aware and a no-op when nothing is held; breaking someone else's lease requires `--force`. Nothing is ever auto-reaped: a PID that can be *proven* gone is reported as stale, and a PID that cannot be checked (EPERM, unusable `ps`) is treated as live. The record stores the caller's PID, not the short-lived script's; `LEASE_PID` overrides for callers behind a transient wrapper. Newlines in caller values are rejected — the record is line-oriented, and a forged second `pid=` line would win.

### Report verifier — hash-bound evidence

`.orchestration/verify.sh` is what makes a report a claim you can check instead of prose you have to trust.

- `--diff-sha` hashes tracked *and* untracked worktree changes while excluding `prompts/**` and `reports/**` — so the hash never chases its own report.
- `verify.sh reports/<file>.md` rejects: a report with no matching prompt, identity mismatch (task ID, attempt, role, base SHA, risk tier, allowed paths), a HEAD that moved off the base SHA, changed paths outside the prompt's scope, unresolved `<PLACEHOLDER>` fields, missing required sections, a non-zero verify exit, and a final diff SHA that disagrees with the current worktree — i.e. **any edit made after the evidence was recorded**. A `done` report must additionally carry an `Acceptance check` (`run: <command>` or `artifact: <path>`, artifact must exist) that matches its prompt verbatim, plus non-empty evidence.
- `verify.sh --run-verify reports/<file>.md` does all of the above and then **re-runs the recorded verify command itself**, at the repo root, after the final edit, printing at most 32 KiB and failing on non-zero exit.

That re-run is fail-closed by capability profile, in three ordered rules: a restricted character set (so pipes, `;`/`&&` lists, redirects, substitution, globs, backgrounding, and quotes cannot appear at all); a program that must be a worktree-relative path or a bare name on a small runner allowlist (`make npm pnpm yarn cargo go mvn gradle pytest tox rake bundle …`); and a deny set matched against *every* word's basename — shells and interpreters, privilege/exec helpers, network utilities, destructive utilities — so `./sh`, `tools/curl`, and `rm -R` are refused regardless of shape. The command is then split and executed as argv; no shell ever parses the recorded string.

### Supervision budget — watching is not working

Coordinators default to polling, and polling is the single largest waste in multi-agent runs: on a measured day it was **43% of all tokens burned**, and 71% on the worst single coordinator, against 5% for the calls that actually applied patches. `docs/orchestration/supervision.md` states the rules — wait wide not often (one blocking wait covering every outstanding worker, never a poll loop), **≤ 2 supervision calls per dispatched task**, a re-dispatch cap fixed *before* the first dispatch, no source reads or greps in the coordinator session, and a hand-off at the first compaction.

Wall clock is not the cost; wall clock held open inside a tool call is. Waiting longer is free — waking is what bills, because each wake re-sends the coordinator's whole context. So the cheapest supervision waits **off the model loop**: end the turn, be re-invoked on the completion event. A coordinator that blocks in-call is bounded by the *smallest* window its call declares, and the shell harness's own yield usually outranks the flag — measured, a wait asking for one minute returned in 30 seconds, every time, with the worker still running.

`.orchestration/burn.py` measures it rather than trusting it. It reads Codex rollout logs **and Claude Code transcripts**, classifies every tool call as POLL / WORK / DISPATCH / EDIT, attributes each round-trip's tokens to the call that drove it, and exits non-zero when polls-per-dispatched-task breaches the budget or a supervision wait parks for less than the floor — reported both pooled and worst-session, because a pooled average is exactly what hides one runaway coordinator. It also prints tokens per round-trip, the context tax: on a measured repo 97% of all spend was context re-sent rather than text produced, so how much a turn carries moves the bill more than what the turn did. Its limits are documented on purpose: two schemas only, `EDIT` counts the editing tool so shell-applied patches land in WORK, and subagent threads are labeled but never excluded from totals.

### Escalation — a bounded loop that ends in a human

Verify fails twice on the same prompt file, or a worker returns `blocked: decision: <question>`, or dispatch triage marks a task hard → the coordinator makes one non-interactive call to the PLANNER slot with the specific question and minimal context (never a transcript dump), appends the answer to the same prompt file under `## Advice`, and respawns that file. The advisor answers only; it never edits, implements, or spawns. **Max 2 consults per issue**, then stop and escalate to a human. Every consult is visible in the prompt file and named in the report.

### Model allocation — slots, not identities

Docs name **slots**: COORDINATOR (orchestrates), PLANNER (advises, handles escalation consults), CODER (implements), REVIEWER (reviews), MISC (throwaway). The slot→model table lives in exactly one file, `docs/orchestration/models.md`. Swap a model by editing that table — no re-init, no other file changes. Any CLI that reads `AGENTS.md` can fill any slot; the protocol and role files are model-independent. The one hard rule: the model that authored a change never reviews it.

### Roster — 9 roles, 4 CLI formats, one body

`engineering-minimal-change-engineer` (the default implementer), `-backend-architect`, `-frontend-developer`, `-ai-engineer`, `-prompt-engineer`, `-devops-automator`, `-code-reviewer`, `-software-architect`, `-technical-writer`. Shipped as Claude/agy markdown, OpenCode markdown, and Codex TOML. `verify.sh` proves `.claude/` and `.agents/` are byte-identical, proves the OpenCode bodies match after frontmatter, and proves every file's declared `name:` equals its filename slug — because a role dispatched by the wrong name silently breaks `--agent <role>`.

### Stability

The prompt-file → report-file contract is substrate-independent. Orchestrator down? Run the same prompt file through a Claude Code subagent or a plain terminal — issue → prompt → report → verify → commit does not change, only the spawn mechanism does. Hung worker? Preserve terminal output and diff, terminate, release the lease, respawn the *same* prompt file in a fresh worktree at its base SHA. Never reuse a tree with partial edits.

---

## Verify this template

```sh
./verify.sh
```

Checks shell syntax across every script, runs the init integration tests (blank-binding rejection, atomic render failure, `GRAPHIFY=0`, clean-install surface, no unresolved placeholders), the report-verifier tests, the preflight/lease tests, and the burn-meter tests against fixtures — then the CAG index budget (≤ 40 lines), cross-CLI role parity, roster name declarations, and whitespace errors.

`burn.py` is exercised only against fixtures here; it never reads your logs during verification.

## License

MIT. See [LICENSE](./LICENSE).
