# Claude Opus implementation brief — preflight and writer leases

Implement the next P0 slice from `.orchestration/reports/fused-session-audit.md` on top of the completion-integrity branch.

## Goal

Turn the documented capability and one-writer rules into portable executable checks that fail before a worker starts consuming task context.

## Required outcomes

1. Add `template/.orchestration/preflight.sh` with a clear CLI and structured failures. It must check: repository/worktree, HEAD/base SHA when supplied, required verify command is non-empty and its executable is available, selected CLI availability when supplied, role name when supplied against the local role roster, and lease availability. It must not require network access or invent model APIs.
2. Add `template/.orchestration/lease.sh` using an atomic filesystem operation (`mkdir`) to acquire/release a worktree lease. Store dispatch ID, owner, PID, and acquired time. Reject a second owner without deleting the first lease. Make release owner-aware and safe when no lease exists.
3. Add focused portable tests for successful preflight, missing CLI/verify command, invalid role, first lease acquisition, second-owner rejection, owner-only release, and stale/cleanup behavior. Use stock shell tools.
4. Update `template/.orchestration/README.md`, `template/docs/orchestration/index.md`, `template/docs/orchestration/orca.md`, `template/AGENTS.md`, and `README.md` briefly. Keep indexes ≤40 lines.
5. Update `verify.sh` to syntax-check and run the new tests.

## Scope and constraints

Allowed paths: `.orchestration/prompts/CLAUDE-OPUS-preflight-leases.md`, `.orchestration/reports/**`, `template/.orchestration/**`, `template/docs/orchestration/**`, `template/AGENTS.md`, `README.md`, `tests/**`, `verify.sh`.

- Do not commit, push, create a PR, or mutate trackers.
- Do not edit `init.sh` or role bodies in this slice.
- Do not silently remove an existing lease; stale lease handling must require explicit owner/force semantics and be tested.
- Keep shell portable across macOS BSD and GNU tools.
- Run focused tests, then `./verify.sh`.
- Write `.orchestration/reports/CLAUDE-OPUS-preflight-leases.md` from the report template with outcome, files, commands, failures, deviations, risks, and evidence.
