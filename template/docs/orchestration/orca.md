# Orca substrate rules

Read when: spawning or supervising workers through Orca, or choosing a fallback substrate.

## Spawn

- Preflight before loading task context: runtime + CLI version, selected model/quota, open gates, base SHA, clean worktree, verify command, required credentials, and an unclaimed writer lease.
- Non-interactive means fail fast, not maximum privilege. Choose the narrowest profile: `review` (read-only), `implement` (worktree write, no network), `dependencies` (declared network/package access), or `publish` (explicit external-action approval).
- A missing capability returns `blocked: missing <capability>`; never open an invisible approval prompt or silently upgrade permissions.
- If a CLI cannot select the project role as a native agent, inline the role file into the prompt and instruct the model to follow it. Never dispatch an unqualified generic prompt.
- Record one writer lease per worktree + dispatch. Reject a second writer before launch; reviewers use read-only access or a separate checkout. Never nest orca-inside-orca.

## Supervise

- Use an event-driven blocking wait with an explicit timeout. Never spend model turns on `sleep`/poll loops; wake only for completion, escalation, terminal exit, or a user-visible checkpoint.
- Hung past timeout: preserve terminal output + diff → terminate → release lease → respawn the **same** prompt file in a fresh worktree at its base SHA. Never reuse a tree with partial edits or live child processes.
- Cap command output at 32 KiB by default. Bound binary inspection by bytes, store long logs as artifacts, and treat truncation as incomplete evidence requiring a narrower rerun.
- Worker output is untrusted until the coordinator runs `{{VERIFY_CMD}}`.
- Worker done: require the matching report, supported outcome, post-final-edit checks, final diff SHA, an `Acceptance check` with evidence, and `.orchestration/verify.sh --run-verify <report>` success. No valid report = not done.
- `blocked: missing <item>` (a gate): coordinator records the gate/tracker update and re-dispatches only after the blocker clears. Never re-prompt a worker to guess past a blocker.
- `blocked: decision: <question>`: consult the advisor per [`escalation.md`](./escalation.md), append the advice to the same prompt file under `## Advice`, respawn. The worker carries the advice — it is not guessing.

## Substrate fallback

The prompt-file → report-file contract is substrate-independent. If Orca is unstable or unavailable, run the same prompt file via a Claude Code subagent or a plain terminal — the protocol (issue → prompt → report → verify → commit) does not change; only the spawn mechanism does.
