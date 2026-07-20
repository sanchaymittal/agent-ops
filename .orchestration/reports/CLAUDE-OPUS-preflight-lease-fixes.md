done

- Task ID: task_8f1c2f7b6d21
- Attempt: 1
- Role: engineering-minimal-change-engineer
- Base SHA: 1a85d0fc5665ccc854bbc42d99839d57470a4517
- Risk tier: medium
- Allowed paths: .orchestration/reports/**,template/.orchestration/**,tests/**
- Verify command: ./verify.sh
- Acceptance check: run: ./tests/preflight-lease.sh
- Acceptance evidence: `./tests/preflight-lease.sh` exits 0 with `PASS: preflight and writer leases` across 11 cases — the original 8 plus three new regressions: a freshly acquired lease is *not* marked stale and preflight reports it with a single `blocked: lease:` prefix; `release --force` clears a lease directory with no `meta`, while an unforced release leaves it alone; newlines in `--owner`/`--dispatch` are rejected before the lock is taken.
- Verify exit: 0
- Verified at: 2026-07-20T14:58:09Z
- Final diff SHA: bea3caef89859afcc00d85436cf04be0c122cb9ac742f47b2f75f40afaa4acad

## Fixes

| Finding | Fix |
| --- | --- |
| F1 — every held lease reported `[stale: pid not running]` | `acquire` records `LEASE_PID`, defaulting to `$PPID` (the invoking worker/coordinator shell) instead of `$$` (the `lease.sh` process, dead milliseconds later). `LEASE_PID` is the explicit override for callers behind a transient wrapper, and is validated numeric. |
| F2 — a lease dir without `meta` bricked `release --force` | Guarded in `meta_field`, not at the `release` callsite: `[ -f "$META" ] \|\| return 0`. Root cause was the `sed \| head` pipeline failing under `pipefail`; fixing the shared reader protects `status` and `acquire` too, which previously survived only because errexit does not propagate through command substitution in `printf` arguments. |
| F3 — `blocked: lease: lease: …` double prefix | `preflight.sh` captures `lease.sh status` **once** and strips the inner `lease: ` prefix. The single capture also removes the second half of the finding: two calls could report a lease released in between as `blocked: lease: lease: available`. |
| F4 — newline in `--owner`/`--dispatch` forged meta fields | Both values are rejected outright (`lease: --owner must not contain a newline`) after parsing and before `mkdir`, so a rejected call never creates a lease directory. |
| F5 — `kill -0` EPERM mislabelled a live other-user process | New `pid_live` ladder: numeric guard → `kill -0` → `ps -p` fallback → default live. Only `ps` exiting exactly 1 ("no such process") proves death; an unusable `ps` or a non-numeric field is indeterminate and reported as live. Verified on this host that `ps -p 1` (root-owned) exits 0 and `ps -p 2147483647` exits 1. |

Not touched: F6 (leading whitespace in `--verify-cmd` yielding an empty program name) is outside the five required fixes and remains open — it blocks correctly, only the message is confusing.

## Files changed

- `template/.orchestration/lease.sh` — `meta_field` missing-file guard; new `pid_live` helper replacing the bare `kill -0`; `pid=` records `LEASE_PID` (default `$PPID`); newline rejection for `--owner`/`--dispatch`. Atomic `mkdir` acquisition and owner-aware release are unchanged.
- `template/.orchestration/preflight.sh` — single `lease.sh status` capture with the inner prefix stripped.
- `tests/preflight-lease.sh` — three new cases (`test_a_fresh_lease_is_not_stale`, `test_force_release_clears_a_lease_with_no_meta`, `test_newlines_in_caller_values_are_rejected`), 8 → 11.
- `template/.orchestration/README.md` — the lease bullet now states the PID contract (`$PPID`, `LEASE_PID` override), the conservative liveness rule, and the newline rejection. This is the only behavior-contract change that reached the docs; the existing "reported as stale, never auto-reaped" promise still holds.

## Commands run

| Command | Exit | Evidence |
| --- | ---: | --- |
| `./tests/preflight-lease.sh` | 0 | `PASS: preflight and writer leases` |
| `./verify.sh` | 0 | `PASS: init integration tests` / `PASS: report verification tests` / `PASS: preflight and writer leases` / `PASS: repository verification` |
| `./template/.orchestration/verify.sh --diff-sha` | 0 | `bea3caef8985…` |
| `ps -p 1` / `ps -p 2147483647` | 0 / 1 | Confirms the F5 fallback sees other users' processes on macOS `ps`. |
| Mutation check: revert `LEASE_PID` → `$$`, rerun suite | 1 | `FAIL: a freshly acquired lease was reported stale: … [stale: pid not running]` — the F1 regression genuinely catches F1. |
| Mutation check: drop the `meta_field` file guard, rerun suite | 1 | Suite fails at the crash-window case — the F2 regression genuinely catches F2. File restored; suite green after both. |

Environment: macOS, GNU bash 3.2.57 (the repository's supported floor). Only stock tools (`sed`, `ps`, `kill`, `date -u`, `mkdir`).

## Failures

- The fresh-lease regression is sensitive to how it invokes `acquire`. Written as `output=$("$LEASE" acquire …)`, `$PPID` is the command-substitution subshell, which exits immediately — the fresh lease then *is* stale and the test fails against a correct implementation. The test calls `acquire` directly and asserts via a separate `status` capture; a comment on the test records why. Caught during design, never committed in the broken form.
- Two mutation checks initially no-op'd because `perl -pi -e` interpolated `$LEASE_PID` inside the pattern, silently matching nothing and reporting a false pass. Re-run with `sed`; both mutations then failed the suite as expected. Classification: harness mistake in my own verification, not a product defect.

## Deviations

- The prompt's brief is a plain task file without an `Allowed paths` field; the value in the header is my own scoping (the files the brief names), not a match against the prompt. `.orchestration/verify.sh <report>` therefore does not apply to this record — `./verify.sh` and the acceptance check carry the evidence.
- F4 is enforced as rejection rather than escaping. Escaping would keep exotic owner names working; rejection is one line, cannot round-trip wrong, and no caller in this repository uses multi-line identifiers.
- One doc line changed (`template/.orchestration/README.md`) because the PID contract is now caller-visible via `LEASE_PID`. No other doc claims became false.

## Remaining risks

- PID recycling still makes a truly stale lease look live, and the F5 change widens that slightly by treating indeterminate answers as live. The direction is deliberate — refusing to break a possibly-live lease — and `--force` remains the explicit escape.
- `$PPID` is only as good as the caller's process lifetime. A coordinator that invokes `lease.sh` from a short-lived wrapper and does not set `LEASE_PID` reintroduces a weaker form of F1 (stale note on a live dispatch). Documented; not detectable from inside `lease.sh`.
- The lease remains advisory and worktree-local: anything writing without calling `lease.sh` is unpoliced. Unchanged by this slice; Phase 4 capability profiles are the upgrade path.
- F6 is still open, by scope.
- The crash-window test creates the lease directory with `mkdir` rather than by killing a real acquirer mid-write. It covers the observable state (`.lease/` with no `meta`), not the race that produces it.
