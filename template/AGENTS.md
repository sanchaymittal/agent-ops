# {{PROJECT_NAME}} — Agent Guide

`CLAUDE.md` symlinks here so agent CLIs share one short contract.

## What this repo is

TODO(project): 2–3 lines — what this product is. When scope exists, freeze it in `docs/product/positioning.md` and state here.

## Read protocol

1. Always load this file, then `docs/index.md`.
2. Read a concern index only when the task touches it; read leaf docs only when routed there.
3. Read `docs/gates/index.md` before real-data, integration, infrastructure, deployment, credential, or owner-decision work.
4. Never bulk-read `docs/`; indexes stay ≤ 40 lines.

## Non-negotiables

- Never invent product requirements, integrations, credentials, identifiers, metrics, user data, or test results. Missing data → name exactly what is missing and stop.
- Never assume human-provisioned infrastructure. A gate opens only when its row in `docs/gates/index.md` records a real value.
- Never commit secrets or private user data. `{{VERIFY_CMD}}` is the definition of done for code changes.
- Make the smallest verifiable change. Report exact files changed and commands run.

## Working method

- Read every file the change touches and trace callers before changing shared code.
- Fix the root cause at the narrowest convergence point.
- Prefer deletion and reuse over addition. No speculative abstraction, config, or scaffolding.
- Run the relevant check and read its result before making a claim.
- After the last edit, run `{{VERIFY_CMD}}` for code changes plus `git diff --check`, then inspect diff/status.
- Report the outcome, files changed, commands run, failures, and any deviation from the request.

## Optional delegation

- Direct work is the default. Delegate only when the user explicitly requests workers or parallel agent work; then read `docs/orchestration/index.md`.
- Use built-in specialist roles when helpful. Repository-local copies of generic role personas are intentionally not maintained.

## Task management

Use a tracker when the user requests it or the work already has an issue. Rules: `docs/orchestration/tasks.md`.

## Layout

TODO(project): keep one line per path.

| Path | What |
| --- | --- |
| `docs/` | Concern-indexed documentation — start at `docs/index.md` |
| `.orchestration/` | Optional worker safeguards and diagnostics |
