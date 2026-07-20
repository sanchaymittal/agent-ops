approve

# Claude Fable final review — preflight/lease slice after the unreadable-meta fix

- Task ID: task_7c8e2d4f1a30 · Attempt 1 · Role engineering-software-architect
- Base SHA `1a85d0fc5665ccc854bbc42d99839d57470a4517`, reviewed read-only: uncommitted diff, fix report `CLAUDE-OPUS-preflight-unreadable-meta-fix.md`, prior review chain
- Verdict: the last blocker is fixed exactly as prescribed — `template/.orchestration/lease.sh:26` guard is now `[ -r "$META" ]` (subsumes missing), with a root-skipping regression test. All prior findings are closed or explicitly accepted as non-blocking. No new findings. Approve.

## Commands and results

| Command | Exit | Result |
| --- | ---: | --- |
| `./tests/preflight-lease.sh` | 0 | `PASS: preflight and writer leases` (12 cases) |
| `./verify.sh` | 0 | all four PASS lines |
| `./template/.orchestration/verify.sh --diff-sha` | 0 | `80450e26beaa…` — matches the fix report's Final diff SHA |
| `/bin/bash ./tests/preflight-lease.sh` (bash 3.2.57) | 0 | portable to the macOS floor |
| unreadable meta (`chmod 000`): unforced release | 1 | blocked with `held by unknown …; --force required`, directory intact |
| unreadable meta: `release --force` | 0 | `lease: released (owner unknown)`, directory removed — previous blocker's exact repro now passes |
| missing meta: `release --force` | 0 | cleared |
| fresh lease after 1s: `status` | 1 | held, **no stale note**, recorded pid = invoking shell |
| 10 concurrent acquirers | — | exactly one winner, meta intact |
| normal owner acquire/release | 0 | unchanged |

## Findings

None blocking.

- **Prior F-1 (unreadable meta bricks `--force`) — closed.** One-character guard change at `lease.sh:26`, comment names the realistic trigger (mode-600 meta under another UID). Regression `test_force_release_clears_a_lease_with_unreadable_meta` (`tests/preflight-lease.sh:170`) asserts both halves: unforced refusal with the directory intact, forced clear. Root skip (`tests/preflight-lease.sh:171-174`) is correct — root reads mode-000 files, the assertion would be vacuous — and prints an explicit `SKIP` line. The `chmod 600` restore on each failure path keeps the EXIT-trap cleanup safe. The fix report's mutation check (revert `-r`→`-f` fails the suite on the exact prior signature) shows the test bites.
- **Prior F-2 (garbage `LEASE_PID` env fails `status`/`release`) — accepted as non-blocking**, per the previous review and the fix report's deviation note. Fail-fast on a malformed environment variable is defensible.
- **All earlier fixes still hold under re-probe:** fresh-lease liveness (`$PPID` + `LEASE_PID` contract), single `blocked: lease:` preflight prefix, newline rejection before `mkdir`, conservative `pid_live` ladder, atomic acquisition (10-way race, one winner), owner-aware release, diff-SHA invisibility, indexes ≤40 lines.
- **Scope discipline:** this slice touched only `lease.sh` (guard + comment) and the test file, exactly what the fix prompt allowed; no doc change was needed because the README bullet's behavioral promise was already correct and the implementation now matches it in one more state.

## Remaining risks (all documented, none blocking)

- A corrupt-but-readable `meta` parses to empty fields and degrades to "held by unknown"; `--force` clears it, so nothing is unrecoverable, but the record's contents carry no integrity check.
- The unreadable-state test simulates via same-UID `chmod 000`, not a foreign-UID mode-600 file — identical code path (`[ -r ]` false), but multi-UID topologies stay untested in this repository. On a root-only CI runner the case skips with an explicit line rather than silently asserting nothing.
- Carried from earlier slices, unchanged: the lease is advisory and worktree-local (Phase 4 capability profiles are the upgrade path); PID recycling can make a truly stale lease look live, with `--force` as the explicit escape; a transient wrapper that doesn't set `LEASE_PID` weakens the staleness signal; F6 (leading-whitespace verify command yields an empty program name in preflight's message) remains open by scope and still blocks correctly.
