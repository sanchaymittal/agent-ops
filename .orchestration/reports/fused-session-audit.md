# Fused Claude/Codex session audit

Date: 2026-07-20
Auditors: Claude Fable 5 and GPT-5.6-Sol
Scope: 290 Claude/Codex JSONL artifacts plus the complete `agent-ops-template` repository.
Source reports: `fable-session-audit.md` and `gpt-5.6-sol-session-audit.md`.

## Executive conclusion

The system does not primarily suffer from weak models. It suffers from weak state, evidence, and lifecycle controls. Agents repeatedly spend intelligence compensating for stale capability information, shared worktrees, oversized context, polling, shell mistakes, and completion rules that trust narrative claims.

The highest-value change is to make completion an executable, hash-bound protocol:

`task manifest → capability preflight → exclusive write lease → bounded evidence → post-final-edit verification → independent review → tracker transition`.

Anything missing remains `Blocked` or `In Review`; it cannot become `Done` because a worker wrote a convincing report.

## Corpus evidence

Both audits independently analyzed the same corpus and agree on the direction of the findings. Counts differ slightly where artifacts, replayed/forked sessions, and lexical classifications are handled differently; they should be treated as directional measurements, not model rankings.

| Signal | Evidence | Meaning |
| --- | ---: | --- |
| Claude/Codex artifacts | 110 / 180 | Large enough to identify recurring patterns. |
| Claude tool calls | 3,429 | 103 explicit tool errors; 16 edits before read; 6 stale-read conflicts. |
| Codex exec calls | 9,608–13,611 | 690 non-zero exits in one audit; 94 failed patches; 1,534 exact repeated execs. |
| Claude polling/sleep artifacts | 19 | About 7.67M cache-read tokens spent waiting in the prior measurement. |
| Long Codex sessions | 34 files over 10M cumulative tokens | Context lifetime is not bounded by task lifetime. |
| Code edits without final-state testing | Claude 81.8%, Codex 47.5% in the conservative detector | “Tests ran” does not prove the final bytes were tested. |
| Interrupts/aborts | 20 Claude interrupts; 89 Codex aborted turns | Repeated user corrections are not being converted into durable policy. |

Important examples include: Wave 2 marked complete while requested behavior was absent; a PR step omitted despite the phase being reported complete; concurrent agents corrupting a test file; binary output creating 246–264K-token dumps; and Claude dispatch failures caused by role names that do not match frontmatter registration.

## Fused systemic findings

### P0 — Completion is not behaviorally trustworthy

The current verifier binds prompt/report metadata and diff state, but still trusts self-attested verification. The reports contain three independent incidents where code-level checks and tracker updates passed while the requested behavior, PR, or end-to-end adapter did not exist.

Required control:

- Add an explicit executable `Acceptance check` or observable artifact to every task.
- Re-run the required verify command in the verifier, after the final edit.
- Bind the result to base SHA, final diff hash, command exit code, and timestamp.
- Require behavior evidence for external actions: URL, tracker state, screenshot, emitted event, or saved artifact.
- Make `Done` impossible without coordinator verification and independent review over the same diff hash.

### P0 — Shared writers invalidate reads and evidence

Concurrent workers in one worktree caused failed patches, whole-file replacement, timeouts, and tests running against changing files. The repository says “one writer per worktree,” but the rule is not enforced.

Required control:

- Create a lease record keyed by worktree and dispatch.
- Reject a second writer before launch.
- Give retries a clean worktree at the immutable base SHA.
- Check for active child processes and file-hash drift before patching or testing.

### P0 — Capability failures are discovered after context is spent

Repeated failures included missing commands, moved skill paths, unavailable runtimes, nonexistent models, session-limit exhaustion, and the Claude role slug defect: documentation advertises `engineering-ai-engineer`, while Claude frontmatter registers `AI Engineer`.

Required control:

- Fix all role frontmatter names to the documented slugs and keep the existing parity test.
- Ship `.orchestration/preflight.sh`.
- Validate CLI/version, model availability, quota, Orca reachability, required tools, credentials/gates, verify command, clean worktree, and lease before loading task context.
- Return structured failure classes: `capability`, `quota`, `gate`, `infra`, or `task`.

### P0 — Context and output budgets are not enforced

Long sessions act as planner, dispatcher, coder, reviewer, and historical database simultaneously. Model context is also consumed by `sleep`, repeated polling, heartbeats, repeated command output, and binary dumps.

Required control:

- Move waiting into Orca; wake the coordinator only on completion, escalation, terminal exit, or timeout.
- Cap command output by bytes, default 32 KiB; store full output as an artifact.
- Reject truncated evidence until a narrower query or artifact reference is supplied.
- Detect binary input before search/read operations.
- Rotate coordinator sessions at task boundaries or a fixed context budget.

### P1 — Recovery is churn instead of diagnosis

The corpus shows repeated builds/tests, failed patches, stale reads, shell quoting errors, and increasingly broad patches. Whole-file delete/add is used as an escape hatch and can erase concurrent edits.

Required control:

- Classify every failed command: `expected-probe`, `environment`, `test`, `patch-conflict`, or `product-defect`.
- Do not rerun the same command twice without a changed hypothesis.
- After one patch-context miss, re-read and hash the target.
- After two misses on one file, stop and replan.
- Require a valid control and negative control before probing a CLI flag matrix.
- Prefer saved scripts over nested shell one-liners and cap by bytes, not lines.

### P1 — Human corrections disappear into transcripts

Users repeatedly corrected model selection, tool choice, approval requirements, and scope. The same corrections reappeared because there is no durable policy surface.

Required control:

- Add `docs/engineering/standing-corrections.md` to the CAG router.
- When a user repeats an instruction, record it as a dated policy with scope and examples.
- Add explicit approval gates for posts, PRs, deploys, destructive changes, and external messages.
- Load only relevant standing corrections to avoid turning the file into another transcript dump.

### P1 — Roles are verbose, duplicated, and weakly executable

Nine role bodies total roughly 1,970 lines before replication across four CLI surfaces. They contain persona fiction, emoji, generic tool catalogs, invented metrics, and conflicting heuristics while omitting required evidence and stop conditions.

Required control:

- Replace each role with a 30–60 line contract: allowed decisions, required inputs, role-specific checks, stop conditions, and report fields.
- Store one canonical role source and generate Claude, Codex, `.agents`, and OpenCode adapters.
- Keep parity checks in CI.
- Remove unsupported targets such as “sub-20ms” unless backed by a project baseline.

### P1 — “Cross-model review” is not yet independent attestation

`CODER != REVIEWER` only compares configured strings. It does not prove distinct identity, context, provider, terminal, or diff. Reviewers also lack a mandatory spec-first evidence format.

Required control:

- Record author and reviewer terminal/session/model/provider identities.
- Reject same-author reviews and mismatched diff hashes.
- Give reviewers the manifest, acceptance criteria, final diff, required checks, and report—not merely the worker narrative.
- Require findings with file/line evidence, severity, user impact, and reproduction or explicit static inference.

### P1 — Non-interactive currently means over-privileged

The current spawn guidance relies on approval bypass and danger-full-access modes. That prevents hidden prompts but makes a hallucinated command, prompt injection, or stale instruction more damaging.

Required control:

- Define capability profiles: read-only review; worktree-write/no-network; dependency-install/network; external-publish.
- Require manifest flags for network, secrets, package installation, destructive commands, and external mutations.
- Block push, reset/clean, writes outside the worktree, and secret reads by default.
- Fail fast with `blocked: capability` instead of opening an invisible approval prompt.

### P2 — Hook and harness noise is a measurable tax

The stop-hook “AUTO-SAVE checkpoint” appeared 79 times. Persona/mode banners and image-heavy ideation sessions add context without helping implementation. Operational coding sessions should not carry unrelated memory workflows or use an exec harness for visual ideation.

Required control:

- Use a minimal hook profile for dispatched workers.
- Move memory writes to session boundaries.
- Route ideation/image-heavy work to a suitable chat surface or extracted artifact.
- Track polling, hooks, compactions, repeated commands, and context rotations separately from productive work.

## What the current template already does well

Keep the compact CAG indexes, explicit external gates, smallest-verifiable-change bias, root-cause guidance, worker/no-commit separation, immutable prompt/report intent, bounded advisor loop, and cross-surface parity checks. The problem is not the principles; it is that most state-machine rules remain prose.

## Implementation roadmap

### Phase 1 — completion integrity

1. Fix role frontmatter slugs.
2. Add acceptance-check fields to prompt/report templates.
3. Add `--run-verify` or equivalent to re-execute verification.
4. Add task/report schemas with task ID, attempt, role, author, base SHA, allowed paths, risk tier, acceptance checks, permissions, commands, exit codes, failures, deviations, and final diff hash.
5. Gate tracker transitions on schema-valid reports, post-final-edit verification, and review attestation.

### Phase 2 — isolation and preflight

1. Implement worktree leases and clean retry worktrees.
2. Implement `.orchestration/preflight.sh` with structured capability checks.
3. Add active-process and file-hash checks before patch/test operations.
4. Add event-driven wait handling and stop model-visible polling.

### Phase 3 — bounded reasoning and recovery

1. Enforce byte-bounded evidence and artifact references.
2. Add failure classification and repeated-command detection.
3. Add re-read/replan rules after patch conflicts.
4. Rotate coordinator sessions by task and context budget.
5. Add standing corrections and explicit external-action approval gates.

### Phase 4 — template quality and safety

1. Compress roles and generate all CLI adapters from one canonical source.
2. Add init/install tests and CI.
3. Replace maximum privilege with capability profiles.
4. Add reviewer identity and diff-hash attestations.
5. Wire `Risk tier` to behavior: high risk requires acceptance evidence, independent review, stronger checks, and smaller diff limits.

## Additional improvements beyond both audits

### 1. Build a golden-task evaluation suite

Create 20–30 small tasks that deliberately exercise false completion, two writers, stale paths, binary output, failed patches, external gates, secret access, and post-edit verification. Run every template release across Claude/Codex. Score correctness, evidence quality, token use, retries, and unsafe actions—not just whether the model eventually finishes.

### 2. Add mutation testing for the protocol

Automatically mutate reports and manifests: change the diff hash, remove a command, alter an allowed path, fake exit code 0, append an edit after verification, or remove acceptance evidence. The verifier must reject every mutation.

### 3. Add provenance and replay

Persist immutable prompt hash, manifest hash, report hash, base SHA, final diff hash, command logs, model configuration, and tool permissions. Provide a replay command that reconstructs exactly what the coordinator accepted.

### 4. Add a cost-aware task router

Classify work by blast radius, uncertainty, external dependencies, file count, and expected verification depth. Route cheap deterministic work to cheap models, planning/architecture to the planner, implementation to the coder, and high-risk work to stronger models with mandatory review. Enforce the route instead of merely documenting it.

### 5. Add a learning loop from escaped defects

For every defect found after `Done`, record: missed acceptance criterion, missing preflight, bad routing, verifier gap, reviewer miss, or environment failure. Convert repeated categories into a new test or policy rule. Do not respond only by adding more prompt prose.

### 6. Add security and secret-boundary tests

Test that default workers cannot read outside the worktree, access credential directories, use network, push, reset, or send external messages. Include prompt-injection fixtures in repository files and issue text.

### 7. Add template versioning and migration

Stamp generated repos with template version and schema version. Provide `agent-ops upgrade` that reports drift, previews changes, preserves user-owned files, and runs migration tests. Refusal-only installation makes improvements hard to propagate.

### 8. Add a human decision budget

Make unresolved decisions explicit and bounded. A worker may ask one focused question with options; the coordinator records the answer in the manifest. Repeated questions become standing corrections or a domain decision record.

## Machine-verifiable completion gate

A code task is complete only when all are true:

1. Manifest and gate approval existed before the first edit.
2. Exactly one dispatch held the write lease.
3. Every changed path is allowed or explicitly approved.
4. All command exit codes and long-output artifact references are recorded.
5. Required checks succeeded after the final edit.
6. Diff check, untracked-file inspection, secret scan, and size check succeeded after the final edit.
7. Report diff hash equals the coordinator's current diff hash.
8. Independent reviewer attested to that same hash and acceptance criteria.
9. No truncated evidence, unresolved failure, unclassified retry, or active writer remains.
10. Tracker transition and commit reference immutable task/prompt/report artifacts.

Otherwise the state is `Blocked` or `In Review`, never `Done`.

## Final recommendation

Do not add more general-purpose prompt instructions first. Implement the smallest enforcement slice that closes the two largest gaps: behavioral acceptance evidence and post-final-edit verification. Then add preflight and leases, because they prevent the most expensive classes of wasted reasoning. Use golden tasks and mutation testing to prove the controls work; otherwise the new rules will become another layer of well-written AI slop.
