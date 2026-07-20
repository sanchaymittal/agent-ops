# Claude/Codex session audit: systemic failure modes and anti-slop controls

Date: 2026-07-19
Auditor: GPT-5.6 Sol
Scope: all JSONL artifacts available under `~/.claude/projects/**/*.jsonl` and `~/.codex/sessions/**/*.jsonl`, plus the current `agent-ops-template` repository. Product code was not edited.

## Executive assessment

The operating model has good principles but weak enforcement. Its strongest ideas are small context indexes, explicit gates, one worker per worktree, cross-model review, prompt/report artifacts, and coordinator-side verification. The transcripts show that prose-only rules do not survive long sessions, concurrent workers, tool drift, or repeated recovery: agents still burn context on polling, patch stale files, accept truncated evidence, rerun commands without narrowing hypotheses, verify before their final edit, and occasionally rewrite whole files to escape patch conflicts.

The central recommendation is to turn the contract into an executable evidence pipeline. A task must not become `Done` because a worker says it is done; completion should require a machine-readable task manifest, an isolated writer lease, a post-final-edit verification attestation tied to the final diff hash, and an independent review record. Output budgets, capability preflights, and event-driven orchestration should prevent the recurring waste before a reviewer ever sees it.

Highest-priority controls:

1. Enforce post-final-edit verification and bind its results to the exact diff being accepted.
2. Enforce one writer lease per worktree and respawn failed work in a clean worktree, not a drifting one.
3. Cap command output by bytes, reject truncated evidence, and block accidental binary dumps.
4. Replace model-driven sleep/poll loops with event-driven waits that do not replay the full context.
5. Replace the verbose persona roster with short, testable role contracts generated from one canonical source.

## Method and corpus

I parsed every JSON line in the available corpus; all lines were valid JSON.

| Corpus | Artifacts | Distinct session IDs | Bytes | JSONL events |
| --- | ---: | ---: | ---: | ---: |
| Claude | 110 | 99 | 49,430,516 | 16,437 |
| Codex | 180 | 180 | 265,123,381 | 72,273 |
| Total | 290 | 279 | 314,553,897 | 88,710 |

The Claude artifacts include main sessions and subagent logs. Codex token totals are cumulative per rollout file and can double-count forked or rolled context, so they are used as concentration/context-pressure indicators, not billing figures. Test-command and code-file classifications are lexical and conservative; shell-based edits and unusually named smoke checks can be missed. Rates below therefore support directional controls, not model leaderboard claims.

The repository review covered `README.md`, `init.sh`, the operating contract, all concern indexes and orchestration docs, and all nine role definitions across Claude, Codex, `.agents`, and OpenCode surfaces.

## Quantitative findings

### Tool and recovery churn

| Signal | Claude | Codex | Interpretation |
| --- | ---: | ---: | --- |
| Tool calls | 3,429 | 13,611 | Large enough to separate patterns from single incidents. |
| Shell/exec calls | 1,734 | 9,608 | Shell remains the dominant evidence and mutation channel. |
| Explicit tool errors / non-zero execs | 103 / 55 | 508 | Claude tool errors affect 43/110 artifacts; Codex non-zero exits affect 63/180. |
| Failed patch applications | n/a for native `Edit` | 94/1,424 (6.6%) | Failures occur in 17 Codex artifacts and cluster in long, heavily edited sessions. |
| Exact repeated exec commands beyond first occurrence | 30 | 1,534 | Codex repeats equal 16.0% of all exec calls; some are valid reruns, but the volume is a strong churn signal. |
| Truncated outputs detected | 4 | 43 | Truncated evidence is still allowed to remain in context without a required narrower rerun. |

Codex non-zero exits included 143 test/assertion failures across 33 artifacts, 145 missing-command/file/module failures across 38, 104 empty search misses across 28, and 14 sandbox/permission failures across 10. Empty search misses are often legitimate discovery, which is why non-zero exit count alone must not be treated as quality failure; repeated unexplained failure or completion after the last failed check is the actionable signal.

Claude's 103 explicit tool errors included 16 attempts to edit files that had not been read, six stale-file conflicts, missing paths/capabilities, rejected permissions, timeouts, and invalid model/runtime assumptions. This is consistent with state drift and missing preflight checks, not one bad session.

### Verification does not reliably cover the final state

Code-editing sessions were detected from native `Write`/`Edit` paths and Codex `apply_patch` targets.

| Verification signal | Claude | Codex |
| --- | ---: | ---: |
| Code-editing artifacts | 22 | 40 |
| No detected test command anywhere | 12/22 (54.5%) | 1/40 (2.5%) |
| No detected test command after the final edit | 18/22 (81.8%) | 19/40 (47.5%) |
| No `git status`/`diff` inspection after the final edit | 16/22 (72.7%) | 10/40 (25.0%) |
| Artifacts that edited tests | 7 | 35 |

The most important number is not “tests run somewhere”; it is whether a successful check covers the final bytes. Nearly half of Codex code-editing artifacts and more than four fifths of the detected Claude code-editing artifacts lack a recognized test command after the last edit. The Claude rate is partly inflated by non-code tasks and Bash mutations that are harder to classify, but even the conservative Codex result is too high for a system whose definition of done is verification.

The template currently says `{{VERIFY_CMD}}` is the definition of done, but it does not record when it ran, its exit code, the tested commit/diff hash, or whether a worker edited afterward. A green command followed by a one-line “cleanup” is currently indistinguishable from a verified final state.

### Long sessions concentrate waste and reduce reliability

Codex recorded 713 task starts, 594 task-complete events, 89 turn aborts, 57 context compactions, and 26 thread rollbacks. Thirty-nine of 180 artifacts contain at least one abort; 26 contain at least one compaction. Abort is not always failure, but the combination of aborts, compactions, repeated commands, and multi-task rollouts shows context lifetime is not bounded by a task.

- The five largest Codex rollout files account for 34.6% of summed cumulative token maxima and 41.3% of all exec calls.
- Thirty-four rollout files exceed 10 million cumulative tokens; eight exceed 50 million.
- The largest artifact, `2026/05/16/rollout-2026-05-16T11-54-08-019e2f74-dca9-7f23-a5b1-a79b23dda5cf.jsonl`, contains 79 task starts, 69 task completions, 14 compactions, 10 aborts, 1,820 exec calls, 282 patches, 34 failed patches, and 119 non-zero execs.

This is a lifecycle defect. A single conversational thread is acting as planner, dispatcher, coder, test runner, reviewer, and historical database across dozens of tasks. Context compaction can preserve a narrative, but it cannot preserve exact file state, test provenance, ownership, and failed-hypothesis history as reliably as external task state.

### Polling spends model context on inactivity

Across Claude logs, 82 `sleep` or `orca orchestration check` tool calls appear in 19 artifacts. Those calls collectively carried about 7.67 million cache-read input tokens plus 81,686 cache-creation tokens. One orchestration artifact spent 1.71 million cache-read tokens across 16 polling calls.

Representative evidence: `~/.claude/projects/-Users-sanchaymittal-github-munshi/9f6759ab-41f4-4356-a055-51a066585389.jsonl` alternates `orca orchestration check` and background `sleep 120` at lines 105, 108, 117, 119, 128, 130, 143, 145, and 155. Cache-read context grows from roughly 71K to 75K tokens while the model is merely waiting. The orchestration substrate should hold this wait outside inference and wake the model only on a relevant event or a human-visible checkpoint.

## Representative failure modes

### 1. Concurrent writers corrupt the evidence surface

In `~/.codex/sessions/2026/05/18/rollout-2026-05-18T21-50-02-019e3be3-24c8-7162-a763-429017f77aac.jsonl`:

- Lines 1068-1078 show two failed patches against `ChatView.test.tsx` after a subagent left a malformed structure.
- Lines 1092-1095 delete and re-add the whole test file as a recovery.
- Lines 1099-1119 run focused tests; the suite times out and exits non-zero.
- Lines 1122-1130 discover the file is still being mutated by running child sessions.
- Line 1131 kills processes, and lines 1143-1165 perform another full-file replacement before a focused test finally passes.

This is not primarily a patch-tool problem. Multiple writers and live child processes shared one worktree, invalidating reads and tests. The template says “never two writers in one worktree,” but no lease, filesystem guard, or dispatch-time rejection enforces it.

### 2. Line-based caps fail on binary output

In `~/.codex/sessions/2026/06/15/rollout-2026-06-15T23-54-30-019ecc87-271e-7011-b73b-fb04f2c3923d.jsonl`, the agent runs `strings ... | ... | head -200` at line 199. Because binary strings can form enormous logical lines, line-based `head` does not bound bytes. Line 203 reports an original token count of 262,144. Related binary greps at lines 223-228 produce two more outputs with original token counts around 264K and 246K.

The follow-on reasoning also demonstrates weak probe design: lines 209-216 run four safety flags with `--help`, all exit zero because help bypasses normal argument validation. Only after a negative-control probe at lines 219-236 does the agent learn those flags are invalid in real print mode. A byte budget and a “negative control first” probe rule would have saved both context and time.

### 3. Patch churn replaces diagnosis

The 94 Codex patch failures include repeated “failed to find expected lines,” missing files, and stale contexts. One early artifact has nine failures across several files; the largest mega-session has 34. The failure sequence above shows a common escalation path: stale patch → larger patch → delete/add whole file. Whole-file replacement destroys review locality and can silently discard concurrent edits.

Claude shows the same underlying state problem through native tools: 16 “file has not been read yet” errors and six “file has been modified since read” errors. A patch should carry the hash of the read version, and the second mismatch should force a re-read/replan rather than a broader patch.

### 4. Capability assumptions are discovered late

Representative Claude errors include a nonexistent model (`opencode/nemotron-3-super-free`), unavailable runtime state (`not running`), missing generated directories/config, and session-limit exhaustion. The earlier Fable audit of this same task stopped at `~/.claude/projects/-Users-sanchaymittal-github-agent-ops-template/eb528490-a21b-4813-978a-6ae455594af7.jsonl:52-62` because the model hit its session limit before producing the report.

The system needs a dispatch preflight for CLI presence/version, selected model availability, quota/session health, required credentials, repository cleanliness, verify-command existence, and orchestration reachability. A worker should fail before consuming task context when any prerequisite is false.

### 5. Human corrections reveal orchestration and selection drift

In `~/.codex/sessions/2026/05/15/rollout-2026-05-15T22-46-52-019e2ca4-189c-7f92-848a-34c0e76c607e.jsonl:80`, the user explicitly asks to use planning/skills/agents and avoid burning a high-reasoning model on inline coding. The same rollout ultimately contains 35 million cumulative tokens, 365 tool calls, 120 patches, multiple build/test reruns, aborts, and a compaction. The instruction was understandable, but there was no resource policy that could enforce it.

Selection needs a deterministic task classifier and budget, not only a model binding table. “Hard” is currently described qualitatively; there is no executable decision based on blast radius, uncertainty, external dependencies, file count, migration risk, or required review depth.

## Repository and template quality gaps

### The role roster is prompt-heavy and control-light

The nine canonical Markdown role bodies span 1,970 lines before being replicated across four CLI surfaces. Much of this is persona material rather than executable guidance: invented “Memory” and “Experience,” emoji-heavy identities, generic tool catalogs, large example blocks, and unmeasurable success claims. Examples include:

- `engineering-backend-architect.md:25` mandates “sub-20ms query times” without a workload or baseline.
- `engineering-minimal-change-engineer.md:43` says not to open files outside the task, conflicting with `AGENTS.md:27-28`, which requires tracing touched flows and callers before editing.
- The same role uses rigid heuristics such as extracting only at the fourth occurrence and suggests “delete this and see what breaks” (`:203`), neither of which is safe as a universal rule.
- `engineering-code-reviewer.md:33` says “suggest, don't demand” even though its own blocker findings must be mandatory; it does not require the originating spec, base revision, actual test execution, or final diff hash.
- `engineering-devops-automator.md` defaults to monitoring, alerting, rollback, security scanning, compliance, and large cloud templates even when the minimal requested change may need none of them.

This content increases prompt load while leaving the important controls elsewhere as prose. Replace each role with a 30-60 line contract: allowed decisions, required inputs, required evidence, role-specific checks, stop conditions, and exact report fields. Persona and fictional experience should be deleted.

### Four copies can drift

Claude and `.agents` role files are byte-identical today, while OpenCode differs mainly through frontmatter conversion and Codex embeds the body in TOML. There is no canonical generator or symmetry test. A future edit can update one surface and silently leave three stale. Store one canonical role body and generate/validate all adapters in CI.

### “Cross-model review” is not independent review

`init.sh:39-43` only rejects identical `CODER` and `REVIEWER` strings. It does not prove that the reviewer is a distinct agent identity, provider family, context, or author. It also cannot stop a coordinator or reviewer from editing before reviewing. Record author terminal/session/model/provider and reject review attestations from the same author identity; use provider diversity for high-risk changes when available.

### The prompt/report protocol has no schema

`.orchestration/README.md` defines naming conventions, not required structured fields. There is no shipped prompt template, report template, JSON schema, attempt ID, base SHA, allowed-path list, diff hash, command exit-code table, failure ledger, or reviewer verdict schema. “Files changed and commands run” remains free-form and easy to omit or invent.

### Verification is a string, not an attestation

`docs/engineering/index.md` exposes a single `{{VERIFY_CMD}}`, but the template does not check that the command exists, define targeted versus full checks, preserve output, handle flaky reruns, or prove it ran after the final edit. No test ensures the generated repository has replaced placeholders, resolved mandatory TODOs, or kept indexes within budget.

### Safety depends on maximum privilege

`docs/orchestration/orca.md:7-11` requires workers to run with approval bypass/danger-full-access modes. This avoids interactive hangs but maximizes the blast radius of a hallucinated command, compromised dependency, prompt injection, or stale coordinator instruction. Non-interactive should mean pre-authorized least privilege, not unrestricted privilege. Default workers should have worktree-only writes, no secret directories, no network unless declared, and explicit external-action gates.

### State-machine rules are not executable

The template says workers never commit, histories are immutable, blocked gates stop work, tasks follow a status sequence, one writer owns a worktree, and review is cross-model. None has a hook or validator. The transcripts demonstrate that high-quality prose is routinely bypassed under pressure.

### `init.sh` lacks a maintained test suite and atomic install

The repository has no test directory or CI workflow for `init.sh`. Important behavior exists only in shell code and historical manual smoke runs. Additional gaps:

- Whitespace-only model values are accepted; explicitly empty environment values fall back to defaults.
- Any non-empty `GRAPHIFY` value, including `0`, enables the feature.
- Copy, substitution, and symlink creation are not transactional; a late failure can leave a partially stamped target.
- The script cannot update an existing installation or report template-version drift; it only refuses managed-path conflicts.
- It does not validate the generated role surfaces for symmetry or the generated `{{VERIFY_CMD}}` for existence.

## Prioritized improvement plan

### P0: completion integrity

1. Add `.orchestration/task.schema.json` and require a task manifest containing `taskId`, `dispatchId`, issue, role, author identity, base SHA, allowed paths, risk tier, acceptance criteria, verify commands, tool/network permissions, and attempt number.
2. Add `.orchestration/report.schema.json` with outcome, files, final diff hash, command, start/end time, exit code, summarized output/artifact path, failures, deviations, and unresolved risks.
3. Implement `agent-ops verify-report <manifest> <report>` (or a portable script) that rejects missing fields, changed paths outside scope, a dirty diff after verification, no successful post-final-edit check for code, untracked files, or a report whose diff hash differs from the current tree.
4. Make the coordinator status transition conditional: `In Review` requires a schema-valid report; `Done` requires coordinator verification and independent review attestations over the same diff hash.

Acceptance signal: it must be impossible to mark a code task done after editing any tracked file later than the last successful required check.

### P0: writer isolation and clean retry

1. Create a worktree lease file/state record keyed by worktree and dispatch. Reject a second writer dispatch before launch.
2. Give each writer its own clean worktree at the manifest base SHA. Reviewers get read-only access or a separate checkout.
3. On hang/failure, preserve logs and diff as artifacts, then respawn the same immutable prompt into a fresh worktree. Do not reuse a tree with unknown child processes or partial edits.
4. Check for live processes holding the worktree and for file-hash drift before every patch/test run.

Acceptance signal: a deliberate two-writer test must reject the second writer before either can mutate shared files.

### P0: bounded evidence

1. Enforce a default 32 KiB stdout/stderr cap per command, with an explicit override recorded in the manifest.
2. Detect binary files before `read`, `strings`, or recursive search; require byte-based bounds (`head -c`, bounded readers), never only line-based `head`.
3. Treat any truncated output as incomplete evidence. The next allowed action must be a narrower query, saved artifact plus targeted extraction, or an explicit stop.
4. Prevent command output from being pasted repeatedly into prompts/reports; store full logs as artifacts and reference hashes/paths.

Acceptance signal: the binary-output reproducer from the June 15 session must remain below the byte limit without injecting hundreds of thousands of tokens.

### P0: event-driven orchestration and preflight

1. Move waiting to the orchestration runtime. A worker completion, escalation, terminal exit, or bounded timeout should wake the coordinator; `sleep` and repeated non-blocking `check` should be policy violations.
2. Run a dispatch preflight before loading task context: CLI/version, model availability, quota, runtime reachability, required tools, credentials/gates, verify command, base SHA, clean worktree, and write lease.
3. Return structured failure classes (`capability`, `quota`, `gate`, `infra`, `task`) so only task failures consume retry/advisor budgets.

Acceptance signal: a ten-minute idle wait should consume no additional model turn and an invalid model should fail before the worker reads repository files.

### P1: session and reasoning discipline

1. Limit workers to one manifest/task. Rotate coordinator sessions at task boundaries after a fixed dispatch count or when context exceeds 50% of the model window.
2. Externalize a compact state ledger: current task DAG, decisions, evidence paths, failed hypotheses, worktree leases, and attestations. Do not rely on transcript compaction as state storage.
3. Require a hypothesis/reproducer before the first behavioral edit. After each failed command, label the failure as expected probe, environment, test, patch conflict, or product defect.
4. After one patch-context miss, re-read and hash the target. After a second miss on the same file, stop and replan. Whole-file delete/add requires explicit justification and diff-size review.
5. For CLI/config probes, run one valid control and one deliberately invalid negative control before testing a matrix of proposed flags.

Acceptance signal: repeated identical commands without a recorded reason, and more than two patch misses on one file, fail the report validator.

### P1: independent, spec-driven review

1. Reviewer input must include the task manifest, base SHA, final diff, worker report, and required checks; it must not include the worker's persuasive narrative as the primary evidence.
2. Review correctness against acceptance criteria first, then security, data loss, concurrency, compatibility, tests, maintainability, and performance as relevant.
3. Require exact file/line evidence for findings, severity with user impact, and an executable reproduction or clearly marked static inference.
4. Track false positives and escaped defects by reviewer/model to improve routing with evidence rather than reputation.

Acceptance signal: same-author or mismatched-diff review attestations are rejected automatically.

### P1: compress and generate the template

1. Replace nine persona essays with short role contracts and a shared base engineering contract. Keep only role-specific deltas in each role.
2. Generate Claude, Codex, `.agents`, and OpenCode role adapters from canonical sources; add a checksum/symmetry test.
3. Add prompt/report templates and risk-tier examples to `.orchestration/`.
4. Add `tests/init.bats` (or equivalent) covering clean install, conflicts, atomic failure, empty/invalid model values, coder/reviewer independence, Linear pairs, `GRAPHIFY=0/1`, special characters, symlink creation, placeholder removal, index budgets, and role symmetry.
5. Add `bash -n`, ShellCheck, the init tests, template schema validation, and generated-fixture verification to CI.

Acceptance signal: one canonical role edit updates every CLI surface deterministically and CI fails on any drift.

### P1: least-privilege non-interactive workers

1. Replace unconditional yolo guidance with capability profiles: read-only review, worktree-write/no-network implementation, dependency-install/network-enabled, and external-publish.
2. Require explicit manifest flags for network, secret access, package installation, destructive commands, PR/issue mutation, and deployment.
3. Add command deny/approval hooks for push, reset/clean, writes outside the worktree, secret reads, and external actions.
4. Preserve non-interactive execution by failing fast with `blocked: capability` instead of opening an invisible prompt.

Acceptance signal: a default worker cannot read user secrets, mutate outside its worktree, push, or access the network.

### P2: measurable operations

Track per task, model, role, and repository:

- time to first useful edit and time to verified completion;
- tool calls, repeated commands, patch misses, output truncations, and context compactions;
- percentage of code tasks with post-final-edit verification;
- worker report rejection reasons;
- review findings confirmed, dismissed, and escaped;
- retries by failure class and clean-retry success rate;
- diff size, files touched, out-of-scope paths, and whole-file rewrites;
- token/cache use attributable to polling versus productive work.

Set budgets from observed baselines, then ratchet them down. Do not put invented goals such as “sub-20ms queries” or “near-zero regression rate” into role prompts without a project measurement source.

## Recommended anti-slop completion gate

A code task is complete only if all statements are machine-verifiable:

1. The task manifest existed before the first edit and the gate table allowed the work.
2. One dispatch held the only write lease for the worktree.
3. Every changed path is allowed by the manifest or recorded as an approved deviation.
4. The report lists every command with exit code and an artifact reference for long output.
5. Required tests and the aggregate verify command succeeded after the final edit.
6. `git diff --check`, status/untracked-file inspection, secret scan, and diff-size check succeeded after the final edit.
7. The report's diff hash matches the coordinator's current diff hash.
8. An independent reviewer attested to that same hash against the same acceptance criteria.
9. No truncated evidence, unresolved failed check, unclassified retry, or active writer remains.
10. The tracker transition and commit reference the task and the immutable prompt/report artifacts.

Anything else is `blocked` or `In Review`, not `Done`.

## What to keep

The template should preserve its compact CAG routing, explicit external gates, root-cause language, smallest-verifiable-change bias, worker/no-commit separation, immutable dispatch intent, and coordinator verification. These are sound. The next version should make them executable and delete the persona-heavy material that competes with them for attention.

## Bottom line

The corpus does not show a lack of intelligence; it shows that intelligence is repeatedly spent compensating for missing controls. Agents usually recover, but recovery is expensive and sometimes verifies the wrong state. Move correctness from narrative compliance to stateful, hash-bound, least-privilege enforcement, and the system will reduce both AI slop and token burn while making failures faster, safer, and auditable.
