# Orca substrate rules

Read when: spawning or supervising workers through Orca, or choosing a fallback substrate.

## Spawn

- Always yolo/non-interactive — a worker that can block on an approval prompt is a defect:
  - `codex exec --sandbox danger-full-access --dangerously-bypass-approvals-and-sandbox`
  - `claude --dangerously-skip-permissions`
  - `agy --dangerously-skip-permissions`
  - Any other CLI (e.g. `hermes`, `grok`): use its own yolo/non-interactive flag. No yolo mode → not usable as a worker; coordinator duty is still fine (that's the interactive session).
- If a CLI cannot select the project role as a native agent, inline the role file into the prompt and instruct the model to follow it. Never dispatch an unqualified generic prompt.
- One worker per worktree. Never two writers in one tree. Never nest orca-inside-orca.

## Supervise

- Always `wait` with an explicit timeout, then `read`. Never assume terminal state.
- Hung past timeout: kill → read partial output → respawn with the **same** prompt file. Prompt files are the idempotent unit of dispatch; a respawn is never a rewrite.
- Worker output is untrusted until the coordinator runs `{{VERIFY_CMD}}`.
- Worker done: require the report file to exist and open with outcome — `done`, `blocked: missing <item>`, or `blocked: decision: <question>` — then role, files changed, commands run, failures quoted verbatim. No report = not done.
- `blocked: missing <item>` (a gate): coordinator records the gate/tracker update and re-dispatches only after the blocker clears. Never re-prompt a worker to guess past a blocker.
- `blocked: decision: <question>`: consult the advisor per [`escalation.md`](./escalation.md), append the advice to the same prompt file under `## Advice`, respawn. The worker carries the advice — it is not guessing.

## Substrate fallback

The prompt-file → report-file contract is substrate-independent. If Orca is unstable or unavailable, run the same prompt file via a Claude Code subagent or a plain terminal — the protocol (issue → prompt → report → verify → commit) does not change; only the spawn mechanism does.
