# Escalation — advisor consults

Read when: verify failed twice on one prompt file, a worker reports a decision-shaped block, or dispatch triage says hard.

The coordinator runs the loop (executor); {{PLANNER}} is the on-demand advisor. Consult at defined triggers only.

**Triggers** — any one fires a consult:
- `{{VERIFY_CMD}}` fails twice on the same prompt file.
- A worker report opens `blocked: decision: <question>`.
- Dispatch triage marks the task hard (cross-concern, architectural choice, or unknown-heavy) — consult before the first spawn.

**Consult mechanic**: coordinator makes a one-shot, non-interactive call to {{PLANNER}} with the specific question plus minimal context — relevant file excerpts, exact error output, the two options if a tie-break. Never a full transcript or bulk file dump. Advice returns as text; coordinator appends it to the task's prompt file under a `## Advice` section, then respawns the same prompt file. The prompt file stays the idempotent dispatch unit — respawned workers carry the advice.

**Boundaries**: the advisor answers the question only. It never edits files, implements, spawns workers, or runs the loop. Advice is input to the coordinator, not a command.

**Budget**: max 2 consults per issue. Still stuck → stop, record in the tracker ({{TASK_TRACKER_UPDATE}}), escalate to a human. Misc/cheap work never consults the advisor.

**Audit**: every consult is named in the worker report and visible as the `## Advice` section in the prompt file.
