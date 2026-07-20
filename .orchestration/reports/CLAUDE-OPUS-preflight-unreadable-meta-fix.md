done

- Task ID: task_9d4e7f2a6c31
- Attempt: 1
- Role: engineering-minimal-change-engineer
- Base SHA: 1a85d0fc5665ccc854bbc42d99839d57470a4517
- Risk tier: medium
- Allowed paths: .orchestration/reports/**,template/.orchestration/**,tests/**
- Verify command: ./verify.sh
- Acceptance check: run: ./tests/preflight-lease.sh
- Acceptance evidence: `./tests/preflight-lease.sh` exits 0 with `PASS: preflight and writer leases` across 12 cases — the 11 from the previous fix slice plus `test_force_release_clears_a_lease_with_unreadable_meta`, which acquires a lease, `chmod 000`s its `meta`, asserts an unforced `release --owner eve` is refused with the directory intact, then asserts `release --owner eve --force` exits 0 and removes the directory.
- Verify exit: 0
- Verified at: 2026-07-20T15:08:09Z
- Final diff SHA: 80450e26beaa00f3b4687a5fd44a42fc2f70888e959854f6a55f9a02ca90ad01

## Fix

Fable F-1: the crash-window guard `[ -f "$META" ]` accepted a `meta` that exists but cannot be read. `sed … | head` then failed, `pipefail` made the pipeline non-zero, and the direct assignment `held=$(meta_field owner)` in `release` aborted the script under `set -e` — silently, before `rm -rf`, so `--force` could not clear the very state it exists for.

`template/.orchestration/lease.sh:26` — `[ -f "$META" ]` → `[ -r "$META" ]`. `-r` subsumes `-f` (an absent file is unreadable), so the missing-meta path is unchanged and one guard now covers both halves of the original requirement. The comment names the realistic trigger: an acquirer under `umask 077` writes mode-600 `meta`, and a different-UID coordinator cannot read it.

Normal reads are untouched — a readable `meta` takes the same `sed` path as before, proven by the 11 pre-existing cases (owner-aware release, second-owner rejection, stale detection, fresh-lease liveness) all still passing.

## Files changed

- `template/.orchestration/lease.sh` — one character in the `meta_field` guard, plus its comment.
- `tests/preflight-lease.sh` — `test_force_release_clears_a_lease_with_unreadable_meta`, registered after the missing-meta case. 11 → 12 cases.

## Commands run

| Command | Exit | Evidence |
| --- | ---: | --- |
| `./tests/preflight-lease.sh` | 0 | `PASS: preflight and writer leases` (12 cases) |
| `./verify.sh` | 0 | `PASS: init integration tests` / `PASS: report verification tests` / `PASS: preflight and writer leases` / `PASS: repository verification` |
| `/bin/bash ./tests/preflight-lease.sh` | 0 | portable to the macOS floor, GNU bash 3.2.57 |
| `./template/.orchestration/verify.sh --diff-sha` | 0 | `80450e26beaa…` |
| Mutation check: revert `-r` → `-f`, rerun suite | non-zero | `FAIL: --force could not clear a lease whose meta is unreadable` — the new regression reproduces Fable's exact signature. Restored; suite green again. |

## Failures

None. The mutation check is the only intentional failure and it behaved as designed.

## Deviations

- The new test skips (printing `SKIP: unreadable-meta case is meaningless as root`) when `id -u` is 0, as Fable's fix direction suggested: root reads regardless of mode, so the case would assert nothing. On a root-only CI runner this case silently provides no coverage — the skip line is the signal.
- The test `chmod 600`s the file back on each failure path before calling `fail`, so the `EXIT` trap's `rm -rf "$TMP_ROOT"` is never the thing that has to cope with a mode-000 file. On the success path the directory is already gone.
- Fable's F-2 (garbage `LEASE_PID` rejected even for `status`/`release`, which never use it) is not addressed — it is marked non-blocking and outside this prompt's scope. Fail-fast on a malformed environment variable remains defensible.
- No documentation change. The `template/.orchestration/README.md` lease bullet describes the contract in behavioral terms ("release … needs `--force` to break someone else's or a stale one"), which was already the promise; this fix makes the implementation match it in one more state rather than changing what is promised.

## Remaining risks

- Widening the guard to `-r` means a genuinely corrupt-but-readable `meta` (garbage bytes, truncated write) still parses to empty fields rather than being flagged. It degrades to "held by unknown" and `--force` clears it, so no state is unrecoverable, but there is no integrity check on the record's contents.
- The test simulates the unreadable state with `chmod 000` as the same UID, not with a genuinely foreign-UID mode-600 file. It exercises the identical code path (`[ -r ]` false), but a multi-UID topology is not directly covered by any test in this repository.
- Everything carried over from the previous slice stands: the lease remains advisory and worktree-local, PID recycling can still make a stale lease look live, `$PPID` depends on the caller outliving the dispatch (hence `LEASE_PID`), and F6 (leading whitespace in `--verify-cmd`) is still open by scope.
