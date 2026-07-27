# Supervision rules

Read when: spawning, supervising, or recovering workers on any substrate. States what this project requires around a dispatch; exact commands and flags come from the substrate's own guide, never from here.

## Spawn

- One Claude session must issue tool calls serially. Do not launch concurrent tool calls from one session; parallel work means separate worker sessions/worktrees. If a 400 tool-use-concurrency error occurs, stop issuing calls in that turn, preserve the prompt file, and recover by starting a fresh session from the same prompt file.
- Preflight before loading task context: runtime + CLI version, selected model/quota, open gates, base SHA, clean worktree, verify command, required credentials, and an unclaimed writer lease. `.orchestration/preflight.sh` executes the locally checkable subset (worktree, base SHA vs HEAD, verify command, CLI, role roster, lease) and returns `blocked: <capability|task|lease>: <detail>`; quota, gates, and credentials stay manual.
- Non-interactive means fail fast, not maximum privilege. Choose the narrowest profile: `review` (read-only), `implement` (worktree write, no network), `dependencies` (declared network/package access), or `publish` (explicit external-action approval).
- A missing capability returns `blocked: missing <capability>`; never open an invisible approval prompt or silently upgrade permissions.
- If a CLI cannot select the project role as a native agent, inline the role file into the prompt and instruct the model to follow it. Never dispatch an unqualified generic prompt.
- Record one writer lease per worktree + dispatch with `.orchestration/lease.sh acquire --dispatch <id>`; release it on completion or after terminating a hung worker. A second writer is rejected before launch and the held lease is never overwritten; breaking someone else's or a stale lease requires `--force`. Reviewers use read-only access or a separate checkout. Never nest one orchestrator inside another.

## Supervise

- **Wait wide, not often.** Wake only for completion, escalation, terminal exit, or a user-visible checkpoint — never a `sleep`/poll loop. One blocking wait covering every outstanding worker, window ≥ 15 minutes — real coding tasks run 15–60 min, so a shorter window buys round-trips and nothing else. Take exact flags from the substrate's own guide, never from this file. Never a 30s yield, never one wait per worker, never a poll loop between waits. A timeout is a checkpoint, not a failure: re-wait — which is why the window is the rule and not the intent behind it: with a short window, re-waiting on every timeout is a poll loop no matter which primitive declared it. `.orchestration/burn.py` reads the declared window and fails on any wait under 15 minutes. Each poll re-sends the coordinator's whole context to return a few KB — measured on a real run, polling was 47% of all tokens burned; the calls that applied patches were 2%, and that 2% is a floor, since a patch applied through a shell counts as work.
- **Polling budget: ≤ 2 supervision calls per dispatched task.** A supervision call is any call that only asks how a worker is doing — a wait, a message check, a terminal read. Sending, replying, and dispatching are not supervision. Past the budget the workers are slower than assumed: block on the next `worker_done` with a longer timeout, or tell the user, instead of watching. `.orchestration/burn.py` measures this against the session logs, per session as well as pooled.
- **Bound the re-dispatch loop.** "Until it passes" is not a stop condition. Fix the number of review → fix rounds before the first dispatch and write it into the prompt file. At the cap, stop and escalate per [`escalation.md`](./escalation.md) instead of dispatching again — a rejected review is the same dead end as a verify that keeps failing, and that file already ends in a human rather than another round. An unbounded loop re-sends the coordinator's whole context on every round, so its cost grows with each rejection while nothing in it halts before the quota funding it does.
- **Coordinator holds prompts and reports, not the codebase.** No source reads, greps, builds, or test runs in the coordinator session; dispatch them to a worker and read the report. Everything the coordinator loads is re-sent on every later turn, so supervision cost scales with what it has read.
- **Hand off at the first compaction.** A compacted coordinator pays full-window context for every remaining call. Write the handoff (open dispatches, leases held, next gate, tracker state) and continue in a fresh session.
- Hung past timeout: preserve terminal output + diff → terminate → release lease → respawn the **same** prompt file in a fresh worktree at its base SHA. Never reuse a tree with partial edits or live child processes.
- Cap command output at 32 KiB by default. Bound binary inspection by bytes, store long logs as artifacts, and treat truncation as incomplete evidence requiring a narrower rerun.
- Worker output is untrusted until the coordinator runs `{{VERIFY_CMD}}`.
- Worker done: require the matching report, supported outcome, post-final-edit checks, final diff SHA, an `Acceptance check` with evidence, and `.orchestration/verify.sh --run-verify <report>` success. No valid report = not done.
- `blocked: missing <item>` (a gate): coordinator records the gate/tracker update and re-dispatches only after the blocker clears. Never re-prompt a worker to guess past a blocker.
- `blocked: decision: <question>`: consult the advisor per [`escalation.md`](./escalation.md), append the advice to the same prompt file under `## Advice`, respawn. The worker carries the advice — it is not guessing.

## Substrate fallback

The prompt-file → report-file contract is substrate-independent. If Orca is unstable or unavailable, run the same prompt file via a Claude Code subagent or a plain terminal — the protocol (issue → prompt → report → verify → commit) does not change; only the spawn mechanism does.
