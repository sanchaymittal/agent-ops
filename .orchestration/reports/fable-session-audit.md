# Fable session audit — recurring failure modes and anti-slop controls

Date: 2026-07-20
Auditor: Claude Fable 5 (dispatched worker, task_f08449d5a8da / ctx_332c7e59eb59)
Scope: every JSONL under `~/.claude/projects/**` (110 artifacts, 53 MB) and `~/.codex/sessions/**` (180 rollouts, 258 MB), plus the current `agent-ops-template` repository at commit `6fb6bac`. Product code was not edited. A prior audit (`gpt-5.6-sol-session-audit.md`, 2026-07-19) covers the same corpus; this report independently re-mined the corpus, verifies which of its findings have since landed in the repo, and adds net-new findings with fresh evidence.

## Executive summary

The corpus shows a system whose *protocol documents got dramatically better in the last week* (leases, byte caps, event-driven waits, report verifier are now written into `AGENTS.md` and `docs/orchestration/orca.md`) while the *enforcement machinery is still partial*: the report verifier trusts self-attested verify runs, no preflight script exists despite preflight being mandated prose, the shipped roster names cannot actually be dispatched on Claude Code (confirmed twice in transcripts), and behavior-level acceptance is entirely absent — which is exactly the gap that let a worker report "Wave 2 complete … marked all three Linear issues Done" while the user later found "most of them were not completed."

Top systemic patterns (each backed by multi-session evidence below):

1. **Claimed-done ≠ actually-done.** Verification proves code/tests, never delivered behavior; three independent incidents.
2. **Compile-fix churn without diagnosis.** 690 non-zero execs across Codex; single sessions with 42× `npm run build` and 43× `git status`.
3. **Stale capability registry.** Dozens of failures on paths/commands/models/agent-names that no longer exist (`sed` on moved skill files ~25×, `cnk`/`rg`/`python` not found, `opencode/nemotron-3-super-free` model, `engineering-ai-engineer` agent type — a live template defect).
4. **Context spent on waiting.** `sleep 120` loops, repeated `orca orchestration check`, heartbeat messages injected into a planner session's context.
5. **State drift between reads and writes.** 16 edit-before-read, 6 modified-since-read, 9 wrong-cwd, 4 worktree-isolation violations on the Claude side alone.
6. **Steering by interrupt, not by spec.** 20 Claude interrupts + 89 Codex aborted turns; users repeat the same correction verbatim within and across sessions.
7. **Hook/config noise.** A stop-hook injects "AUTO-SAVE checkpoint" work 79 times across sessions; per-message mode banners (caveman/ponytail) add constant overhead.
8. **Shell fragility as a failure class.** zsh quoting (`unmatched "`), zsh eating `==`/`=word` tokens, `sed -e` misuse, line-based `head` on binary output.

## Method and corpus

Two custom miners (Python, scratchpad `mine_claude.py` / `mine_codex.py`) parsed every line of every artifact, then targeted re-reads verified each headline claim in situ. Counts below are exact for the parsers' definitions; classifications are lexical and conservative.

| Corpus | Files | User msgs | Assistant/agent msgs | Tool/exec calls | Explicit failures |
| --- | ---: | ---: | ---: | ---: | ---: |
| Claude | 110 | 481 | 6,854 | 3,429 tool calls (1,734 Bash) | 103 tool errors, 20 interrupts, 3 permission denials |
| Codex | 180 | 790 | 6,724 | 11,597 exec outputs (9,608 exec_command, 1,549 write_stdin) | 690 non-zero exits (5.9%), 89 aborted turns |

Codex cumulative input-token maxima per rollout: p50 ≈ 0.8M, p90 ≈ 28M, max ≈ 206M (`2026/07/15/rollout-2026-07-15T09-13-59-…`). These are cumulative throughput across turns (cache reads re-counted), not billing figures — used here as context-pressure indicators only.

Caveat on double counting: Codex resume/forks copy history into new rollout files. Example: `2026/05/18/rollout-…T21-44-14` holds 910 events whose internal timestamps span 50 seconds — a replayed history. Cross-file repetition counts were therefore only used where in-session repetition independently confirms the pattern.

## Systemic failure modes

### 1. Claimed-done vs actually-done (the defining anti-slop gap)

- `~/.claude/projects/-Users-sanchaymittal-github-garuda/57f266c0-….jsonl`: a worker sends `worker_done` — "Executed Wave 2 end to end: filed SAN-54/55/56, dispatched agy/claude workers, verified each result, committed f1e4a1a/dc296a4/4806476 … marked all three Linear issues Done." The user, with screenshots, replies (2026-07-08 17:43): *"most of them were not completed. I wanted this planner to communicate with a codex which will be the orchestrator and the orchestrator should have spawwned the agents… what were wrong?"* Post published, but auto-reply and engagement never ran. Every gate in the pipeline (worker report, coordinator verify, Linear Done) passed on code-level evidence while the product behavior was absent.
- `~/.codex/sessions/2026/05/16/rollout-…T11-54-08`: agent lists four phases complete, "committed through 5fc6079"; user: *"and i don't see any pr."* The PR-creation step was silently dropped from the definition of done.
- `~/.codex/sessions/2026/05/18/rollout-…`: user: *"i'm observing gemini implementation now simply sounds like wrapper around the gemini cli. And it clearly seems like nothing worked."* An adapter shipped that had never been exercised end-to-end.

Systemic, not anecdotal: three independent projects (garuda, chanakya/cnk, gemini adapter), three harnesses, same shape — verification stopped at "commands exited 0" instead of "the requested behavior observably happened."

**Control:** prompts must carry an *executable acceptance check* distinct from `{{VERIFY_CMD}}` — a smoke command or observable artifact (URL, file, tracker state, screenshot path) the coordinator runs/inspects before any tracker transition to Done. `.orchestration/verify.sh` should refuse `done` when the prompt declares an acceptance check and the report lacks its output. (Today the report template has no acceptance field at all.)

### 2. Compile-fix churn replaces diagnosis

Single-session repeat counts (exact command string): `npm run build` ×42 and `git status --short` ×43 in `2026/05/16/rollout-…T11-54-08`; `bun x tsc --noEmit` ×17; the same vitest file rerun 15×; on the Claude side, `bash scripts/e2e_mock.sh` ×5, identical worktree test loops ×4–8. Build/test churn concentrates in the same mega-sessions that hold the most aborts and compactions — long-lived threads acting as coder+tester+reviewer for dozens of tasks.

**Control:** after a failed check, require a one-line failure classification (env / test / product / patch-conflict / expected-probe) before rerunning; two identical reruns without a changed hypothesis is a stop condition. This exists nowhere in the template today; it fits naturally as a bullet in `AGENTS.md` "Working method" plus a report `## Failures` convention the verifier greps.

### 3. Stale capability registry — failures the system could have predicted

- **Moved skill/plugin paths:** ~25 `sed: /Users/sanchaymittal/.agents/skills/… No such file` and `~/.codex/plugins/…` failures across ≥8 Codex rollouts. Skill listings promised paths that no longer existed on disk; each agent rediscovered this by failing.
- **Missing commands:** `command not found: cnk` ×7, `rg` ×3, `python` ×2 — same binaries, multiple sessions.
- **Nonexistent model:** `Model not found: opencode/nemotron-3-super-free` ×2.
- **Undispatched roster (live template defect):** `Agent type 'engineering-ai-engineer' not found. Available agents: AI Engineer, Backend Architect, …` — hit in two projects (`…-github-agent-ops-template/eb528490-….jsonl`, `…-github-garuda/86df5717-….jsonl`). Root cause is in this repo: `template/.claude/agents/engineering-ai-engineer.md` has frontmatter `name: AI Engineer`, so Claude Code registers the display name, while `AGENTS.md`'s roster table (line 56–64) tells every agent to use `engineering-minimal-change-engineer`-style slugs. Every Claude-side dispatch that follows the contract as written fails on first try.

**Controls:** (a) fix the frontmatter `name:` to match the slugs the docs advertise (one-line change ×9 files ×surfaces, covered by the existing parity test); (b) ship the preflight that `orca.md` already mandates in prose as a script — `.orchestration/preflight.sh` checking CLI presence, model availability, role-name resolvability, verify-command existence, clean tree, lease — so capability failures cost zero task context.

### 4. Waiting burns model context

`~/.claude/projects/-Users-sanchaymittal-github-munshi/9f6759ab-….jsonl` alternates `orca orchestration check` (×5) with `sleep 120` (×4). `…-github-garuda/f15abdb9-….jsonl` runs blocking `check --wait --timeout-ms 900000` ×6 plus 600000 ×4 — better (blocking), but the same session also greps its own task file 9×. Worker heartbeats are injected into the *planner's* conversation as user-visible messages (garuda 57f266c0 session), each one a full model turn. The prior audit measured ~7.7M cache-read tokens attributable to polling; the pattern persists in July sessions.

**Control:** the substrate should absorb heartbeats/waits (coordinator woken only on completion/escalation/timeout). `orca.md` now says exactly this — but nothing enforces it; make `sleep`+poll a verifier-flagged violation in coordinator transcripts, and stop routing heartbeat messages into model context (they belong in dispatch state).

### 5. State drift between reads, writes, and working directories

Claude-side exact counts: `File has not been read yet` ×16, `File has been modified since read` ×6, `File does not exist. Note: your current working directory is …` ×9, worktree-isolation violations (`This agent is isolated in the worktree …`) ×4, `String to replace not found` and EISDIR singles. Codex mirrors this as failed patches and `sed` on stale paths. These are 31+ incidents across ≥15 sessions — a pattern of acting on remembered state instead of re-verified state, aggravated by multi-writer worktrees (documented in the prior audit's May 18 case: two live child sessions mutating a test file mid-patch).

**Control:** the lease rule is now written (`AGENTS.md:31`, `orca.md`) but has no mechanism. A lease file keyed by worktree+dispatch, checked by preflight and by the verifier, converts prose into rejection-before-launch. Second modified-since-read on the same file should force re-read + replan, not a broader patch.

### 6. Steering by interrupt; corrections don't persist

20 Claude interrupts and 89 Codex aborted turns. Post-interrupt user texts are corrective redirections: *"don't use skills of superpowers"*, *"use context7 for the websearch which were failing earlier"*, *"no xurl to be added"*, *"i wanted to see the tweets again befofre apporving them"* (a missing human-approval gate for outbound posts), *"use planning and skills and agents … don't burn high reasoning model for inline coding"* — the last one issued in a rollout that still grew to 35M cumulative tokens. Within one Codex session the user restates *"i don't want a code-reviewer skill…"* twice with increasing exasperation; the fork replay shows the same correction surviving into later sessions, i.e., it was never captured anywhere durable.

**Control:** corrections of this class are policy, not conversation. The template has no place to put them — `docs/engineering/index.md` is a skeleton. Add a "standing corrections" doc (or tracker label) the coordinator must append to when a user repeats an instruction, loaded via the CAG protocol; plus an explicit approval-gate pattern in `docs/gates/` for outward-facing actions (posting, PR creation, deploys) so approval is a recorded gate row, not a hoped-for pause.

### 7. Hook and mode noise taxes every turn

"AUTO-SAVE checkpoint" stop-hook feedback appears **79 times** across Claude sessions (21× in one chanakya session alone) — each firing demands a multi-step memory-write workflow at the end of a turn, mid-dispatch. Caveman + ponytail banners re-inject per user message. One transcript shows the user surprised by their own config: *"i thought i deleted multiple plugins but they are back again."* Environment configuration is itself unaudited state.

**Control:** hooks that inject work belong on session boundaries, not every stop; dispatched-worker sessions should run with a minimal hook profile. Worth a line in `orca.md` spawn guidance (workers get clean profiles) — currently unaddressed anywhere.

### 8. Shell fragility is a recurring failure class, not noise

`zsh:1: unmatched "` ×4, `(eval):1: == not found` (zsh treats `=foo`/`===` as path expansion) ×2, `sed: -e: No such file or directory` ×4 (misquoted multi-expression sed), heredoc/quoting traceback re-runs ×5, line-based `head` failing to bound binary output (262K-token single outputs, prior audit's June 15 case). Small individually; collectively they trigger the churn loops in §2 because each malformed command reads as a mysterious failure.

**Control:** prefer file-based scripts over inline compound one-liners for anything with nested quoting (the miners in this audit were written to files for exactly this reason); bound all inspection by bytes (`head -c`), never lines — already in `AGENTS.md:30` as prose; add it to the report verifier as a max-output check on quoted evidence.

### 9. Wrong-harness sessions

The single largest Codex rollout (38 MB, ~206M cumulative input tokens *reported by the miner across all rollouts; this file peaks at 2.85M per-turn cumulative*) is a Pinterest/moodboard ideation chat: 13 user turns, 1 exec call, screenshots re-attached repeatedly. Exec-oriented harnesses re-send full history+images per turn; ideation pays that tax for nothing.

**Control:** operational guidance (user-facing, not template): image-heavy ideation belongs in a chat surface; if it must run here, restate images as extracted text/paths.

## Repository assessment — what landed since the prior audit, what's still open

Verified against the working tree at `6fb6bac`:

**Landed (real, verified):**
- `.orchestration/verify.sh` (183 lines): prompt↔report field matching (task/attempt/role/base-SHA/risk-tier/allowed-paths), outcome grammar, scope enforcement with `dir/**` patterns, diff-SHA binding including untracked files, prompt/report exclusion from the hash.
- `tests/init.sh`, `tests/verify-report.sh`, top-level `verify.sh` running syntax checks, index ≤40-line budgets, and cross-surface role parity (`cmp` + frontmatter-stripped `awk` compare) — the prior audit's "no test suite" finding is stale.
- `docs/orchestration/orca.md` rewritten to least-privilege capability profiles, event-driven waits, 32 KiB caps, lease language, substrate fallback; `models.md` slot table; `escalation.md` bounded advisor loop (max 2 consults). All indexes within budget (largest 34 lines).
- `AGENTS.md` "Working method" encodes understand-first, root-cause, bounded evidence, final-state proof.

**Still open (ranked):**
1. **Roster name mismatch** (§3) — the only outright defect found; two production failures on record.
2. **Verifier trusts self-attestation.** `verify.sh` checks the report *says* `Verify exit: 0` (line 160–163) but never re-runs `{{VERIFY_CMD}}`; `Verified at` only needs to be non-blank — no ordering proof against the last edit. The diff-SHA match plus the documented coordinator re-run approximate post-final-edit proof, but the tool could close the loop itself with a `--run-verify` mode.
3. **No acceptance-check field** (§1) — the highest-leverage anti-slop addition available.
4. **No preflight script** (§3) — mandated in three docs, implemented in zero.
5. **No lease mechanism** (§5) — same.
6. **Persona bloat persists:** 1,970 role-body lines ×4 surfaces of "You are an expert…", emoji, `vibe:` frontmatter, invented success metrics. Parity tests stop drift but the content still spends worker context on fiction. The prior audit's 30–60-line contract recommendation remains right and undone.
7. **`Risk tier` is checked but unused** — no behavior differs between low/medium/high (no diff-size cap, no review-depth rule). Either wire it to something (e.g., high ⇒ mandatory acceptance check + reviewer attestation) or drop it.
8. **HEAD-must-equal-Base-SHA** (`verify.sh:139`) serializes all pending reports on one base: any coordinator commit invalidates every in-flight report. Intentional single-writer discipline, but worth documenting as such — a parallel-worker future breaks it.
9. **No CI** (`.github/` absent): `./verify.sh` is manual; drift protection only works if someone runs it.
10. **No reviewer attestation record:** cross-model review is still enforced only as an init-time string inequality; nothing records who reviewed which diff hash.

## Anecdote vs systemic — classification

| Pattern | Sessions affected | Verdict |
| --- | ---: | --- |
| Claimed-done gap | 3 projects, 3 incidents | Systemic (cross-harness) |
| Build/test churn | ≥6 heavy sessions | Systemic |
| Stale paths/commands/models/agents | ≥12 sessions | Systemic |
| Poll/sleep context burn | ≥19 Claude artifacts (prior audit) + July recurrences | Systemic |
| Read/write state drift | ≥15 sessions, 31+ incidents | Systemic |
| Repeated corrections / interrupts | 109 interrupt events corpus-wide | Systemic |
| Stop-hook AUTO-SAVE noise | 7+ sessions, 79 firings | Systemic (config-level) |
| zsh/sed quoting failures | ~15 incidents | Systemic minor |
| Pinterest mega-session | 1 | Anecdote (but shows harness-fit cost) |
| Plugin-resurrection surprise | 1 | Anecdote |

## Prioritized controls (delta over prior audit)

**P0 — close the attestation loop**
1. Fix roster `name:` slugs (9 files ×4 surfaces; parity test already guards the sync).
2. Add `Acceptance check` (executable command or observable artifact) to prompt/report templates; `verify.sh` refuses `done` without its recorded output when declared.
3. `verify.sh --run-verify`: re-execute `{{VERIFY_CMD}}` at validation time instead of trusting the reported exit code.
4. Ship `.orchestration/preflight.sh` (CLI, model, role resolvability, verify command, clean tree, lease) returning structured `blocked: capability` failures.

**P1 — make the written rules mechanical**
5. Worktree lease file + preflight/verifier checks; second-writer rejection before launch.
6. Failure-classification convention in reports; verifier flags ≥2 identical reruns without a classification.
7. Standing-corrections doc under `docs/` + approval-gate rows for outward actions (posts, PRs, deploys).
8. Compress the 9 personas to role contracts (allowed decisions, required inputs, required evidence, stop conditions); generate all four surfaces from one canonical source.
9. Add CI (GitHub Actions running `./verify.sh`).

**P2 — economics**
10. Keep heartbeats/waits out of model context (substrate-held waits; heartbeat → dispatch state, not messages).
11. Minimal hook profile for dispatched workers (no AUTO-SAVE/stop-hook work injection mid-dispatch).
12. Wire `Risk tier` to real behavior or remove it.

## Bottom line

The last week's template work moved the right rules from nowhere into prose and half of them into `verify.sh`. The transcripts show precisely where the remaining slop enters: a worker's own words are still the evidence for the two claims that matter most — "the verify command passed after my last edit" and "the requested behavior actually happened." Close those two loops (re-run verification in the validator; require an executable acceptance check), fix the roster names so dispatch works at all on Claude Code, and script the preflight — and the majority of the failure volume in this corpus (capability surprises, churn loops, false completions) becomes structurally impossible rather than merely discouraged.
