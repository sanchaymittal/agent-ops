done

- Task ID: CLAUDE-OPUS-preflight-leases
- Attempt: 1
- Role: engineering-minimal-change-engineer
- Base SHA: 1a85d0fc5665ccc854bbc42d99839d57470a4517
- Risk tier: medium
- Allowed paths: .orchestration/prompts/CLAUDE-OPUS-preflight-leases.md,.orchestration/reports/**,template/.orchestration/**,template/docs/orchestration/**,template/AGENTS.md,README.md,tests/**,verify.sh
- Verify command: ./verify.sh
- Acceptance check: run: ./tests/preflight-lease.sh
- Acceptance evidence: `./tests/preflight-lease.sh` exits 0 with `PASS: preflight and writer leases` across 8 cases — valid preflight, missing CLI, unavailable/empty verify command, unknown role, first acquisition, lease invisibility to the diff SHA, second-owner rejection with the first record intact, owner-only release, no-op release, and stale-lease `--force` semantics.
- Verify exit: 0
- Verified at: 2026-07-20T10:37:07Z
- Final diff SHA: c43a23d6d09b84636a15bb7f6809ac6c3b8d71bea6ed3f64b17585f53f82c125

## Files changed

- `template/.orchestration/preflight.sh` (new) — `--verify-cmd CMD [--base-sha SHA] [--cli NAME] [--role NAME]`. Checks worktree/repository, base SHA is a commit and equals HEAD, verify command non-empty with a resolvable program, CLI on PATH, role against `.claude/agents/<role>.md`, and lease availability via `lease.sh status`. Failures are `blocked: <capability|task|lease>: <detail>` with exit 1. No network, no model APIs.
- `template/.orchestration/lease.sh` (new) — `acquire --dispatch ID [--owner NAME]` / `release [--owner NAME] [--force]` / `status`. Atomic `mkdir` of `.orchestration/.lease/` is the lock; `meta` records dispatch, owner, PID, and UTC acquire time.
- `template/.orchestration/.gitignore` (new) — ignores `.lease/` so a held lease never perturbs `verify.sh --diff-sha` or its scope check. Ships via the existing `tar` payload in `init.sh`; no `init.sh` edit needed.
- `tests/preflight-lease.sh` (new) — 8 portable cases over an `init.sh`-scaffolded temp repo, stock shell tools only.
- `verify.sh` — both new scripts and the new test added to the `bash -n` list; the new test invoked alongside the existing two.
- `template/.orchestration/README.md`, `template/docs/orchestration/index.md`, `template/docs/orchestration/orca.md`, `template/AGENTS.md`, `README.md` — document both scripts; all indexes stay ≤40 lines (orchestration index: 32).

## Commands run

| Command | Exit | Evidence |
| --- | ---: | --- |
| `./tests/preflight-lease.sh` | 0 | `PASS: preflight and writer leases` |
| `./verify.sh` | 0 | `PASS: init integration tests` / `PASS: report verification tests` / `PASS: preflight and writer leases` / `PASS: repository verification` |
| `./template/.orchestration/verify.sh --diff-sha` | 0 | `c43a23d6d09b84636a15bb7f6809ac6c3b8d71bea6ed3f64b17585f53f82c125` |

## Failures

- First draft of `tests/preflight-lease.sh` used `output=$(cmd) && fail "..."` and `[ -d dir ] && fail "..."` for negative assertions. Under `set -e` a false `&&` chain is itself a non-zero statement, so every expected-failure case would have aborted the run silently instead of asserting. Classification: product defect in the new test. Fixed by rewriting all of them as `if ... ; then fail; fi` before the first run. No test has ever passed in the broken form.

## Deviations

- The dispatch prompt is a plain brief without `Task ID`/`Attempt`/`Risk tier` fields, so those header values here are this report's own, not a match against the prompt. `.orchestration/verify.sh <report>` therefore does not apply to this record (it requires a field-for-field matching prompt); the acceptance check and `./verify.sh` carry the evidence instead.
- The audit's five failure classes (`capability`, `quota`, `gate`, `infra`, `task`) are not all emitted. Preflight uses the three it can actually determine locally — `capability`, `task`, `lease`. Quota, gates, and credentials need network or human-provisioned state and are explicitly out of scope per the brief's "no network, no invented model APIs"; `orca.md` now says they stay manual.
- Lease exclusion is a shipped `.gitignore` rather than new exclude arguments in `verify.sh`. Fewer moving parts, and it keeps `diff_sha` and `changed_paths` correct by construction rather than by two matching edits.

## Remaining risks

- The lease is advisory and worktree-local. It stops a second dispatch that calls `lease.sh`; nothing stops a process that writes to the worktree without asking. Upgrade path is the capability profile from Phase 4 of the audit.
- PID liveness uses `kill -0`, which cannot distinguish a recycled PID from the original worker. A recycled PID makes a stale lease look live — the failure direction is conservative (refuses to break a lease that is actually dead), and `--force` remains the explicit escape.
- `preflight.sh` resolves only the first word of the verify command. A wrapper that exists but whose own dependencies are missing still passes preflight; the verifier's `--run-verify` is what catches that, later.
- The role roster check reads `.claude/agents/` only. Cross-CLI parity is already enforced by `verify.sh`, so this is not a second source of truth — but a repo that drops the parity check would need this path revisited.
