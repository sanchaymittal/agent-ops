# .orchestration/ — dispatch artifacts

Working records of multi-agent dispatches. Protocol: `docs/orchestration/index.md`.

- `prompts/` — one file per dispatch: `{{ISSUE_PREFIX}}-xx-<role>-<slug>.md` (lowercase prefix). The idempotent unit of dispatch: a failed/hung worker is respawned from the same file, never rewritten mid-flight.
- `reports/` — worker output, same basename as its prompt. Written by the worker, verified by the coordinator before commit.
- Files here are immutable history once a dispatch completes. Do not retro-edit; stale doc paths inside old prompts are expected.
