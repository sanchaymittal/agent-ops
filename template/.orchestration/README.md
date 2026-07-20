# .orchestration/ — dispatch evidence

Working records of multi-agent dispatches. Protocol: `docs/orchestration/index.md`.

- `prompts/TEMPLATE.md` — copy to `{{ISSUE_PREFIX_LOWER}}-xx-<role>-<slug>.md` and fill every field before dispatch. The prompt is immutable intent: a failed/hung worker is respawned from the same file in a fresh worktree.
- `reports/TEMPLATE.md` — copy to the same basename as its prompt. The worker records exact outcome, commands/exits, failures, deviations, final verification time, and diff SHA.
- `verify.sh --diff-sha` — hashes tracked + untracked worktree changes while excluding prompt/report records, avoiding a self-referential report hash.
- `verify.sh reports/<file>.md` — rejects identity/scope mismatches, out-of-scope paths, non-zero verification, unresolved placeholders, edits made after the recorded hash, and a `done` report whose `Acceptance check` disagrees with its prompt or carries no evidence. The check is `run: <command>` or `artifact: <path>`; an artifact must exist in the worktree.
- `verify.sh --run-verify reports/<file>.md` — everything above, then re-runs the recorded `Verify command` at the repository root after the final edit, prints at most 32 KiB of output, and fails on a non-zero exit. Commands with external or destructive effects are refused, not executed.
- Files here are immutable history once a dispatch completes. Do not retro-edit; stale doc paths inside old prompts are expected.
