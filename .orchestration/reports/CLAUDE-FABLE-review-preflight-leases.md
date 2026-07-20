request changes

# Claude Fable review — preflight and writer leases

- Branch: `claude/opus-preflight-leases`, base `1a85d0fc5665ccc854bbc42d99839d57470a4517`
- Reviewed read-only: fused brief, `.orchestration/reports/CLAUDE-OPUS-preflight-leases.md`, full diff, all new files
- Verdict: core mutual exclusion is correct and race-safe, but two real defects sit exactly on the axes this slice exists for — stale-lease signaling and `--force` recovery. Both are small, local fixes in `lease.sh` plus one test each.

## Commands and exit codes

| Command | Exit | Result |
| --- | ---: | --- |
| `./tests/preflight-lease.sh` | 0 | `PASS: preflight and writer leases` |
| `./verify.sh` | 0 | all four PASS lines |
| `./template/.orchestration/verify.sh --diff-sha` | 0 | `c43a23d6d09b…` — matches the implementation report's Final diff SHA |
| 10 concurrent `lease.sh acquire` (scaffolded repo) | — | exactly one winner, meta intact (atomicity holds) |
| `preflight.sh` under macOS `/bin/bash` 3.2.57 | 0 | portable |
| adversarial probes below | — | two defects, four minor findings |

## Findings

### F1 — every held lease reports `[stale: pid not running]`; stale signal is inverted (severity: high)

`template/.orchestration/lease.sh:51` records `pid=$$` — the PID of the `lease.sh acquire` process itself, which exits milliseconds later. So the recorded PID is dead for **every** legitimately held lease, and `status` marks it stale immediately.

Reproduction (any repo scaffolded by `init.sh`):

```
$ ./.orchestration/lease.sh acquire --dispatch D10 --owner alive-worker
lease: acquired by alive-worker (dispatch D10)
$ ./.orchestration/lease.sh status
lease: held by alive-worker (dispatch D10, pid 42326, since …) [stale: pid not running]
```

User impact: the stale note exists to tell an operator when `--force` is justified. Because it fires on every lease, it trains coordinators to `--force`-break leases held by live workers — the exact owner-safety failure the design comment ("a live worker is never evicted by a wrong guess") promises to prevent. The implementation report's risk section discusses recycled PIDs making a stale lease look live; the dominant failure is the opposite and unconditional.

Test gap: `tests/preflight-lease.sh:115` only tests the stale path with a hand-patched PID and never asserts a freshly acquired lease is *not* stale — which is why this passed.

Fix direction: record `$PPID` (the invoking worker/coordinator shell) or accept `--pid`, and add the missing "fresh lease is not stale" assertion.

### F2 — a lease dir without `meta` bricks `release`, including `--force` (severity: medium)

`template/.orchestration/lease.sh:63` — `held=$(meta_field owner)`. When `$LEASE/meta` does not exist (acquirer killed between `mkdir` at line 43 and the meta write at line 48, disk-full on the write, or manual `mkdir`), `sed` fails on the missing file; under `set -euo pipefail` the pipeline is non-zero, the assignment aborts the script **before** `rm -rf`, silently, exit 1.

Reproduction:

```
$ mkdir .orchestration/.lease          # crash-window state
$ ./.orchestration/lease.sh release --force
$ echo $?
1                                       # no output at all
$ ls -d .orchestration/.lease
.orchestration/.lease                   # still stuck
```

User impact: `--force` is the documented escape hatch for broken lease states, and it fails silently in precisely the broken state it exists for. Recovery requires knowing to hand-run `rm -rf`, contradicting `README.md`'s "release … needs `--force` to break someone else's or a stale one." Note an *empty* meta file releases fine (sed exits 0) — only the missing file dies, which is why `status`/`acquire` (whose `meta_field` calls sit inside command substitutions in printf arguments, where errexit does not propagate) degrade gracefully while `release` aborts.

Fix direction: `held=$(meta_field owner || true)` or guard `[ -f "$META" ]`; add a crash-window test (`mkdir` the lease dir, assert `release --force` clears it).

### F3 — preflight lease failure double-prefixes (severity: cosmetic)

`template/.orchestration/preflight.sh:70-71` wraps `lease.sh` output (already `lease: …` or `blocked: lease: …`) in `fail lease`, producing `blocked: lease: lease: held by …`. It also runs `lease.sh status` twice, so a release between the two calls yields the nonsensical `blocked: lease: lease: available`. Strip the inner prefix or capture once.

### F4 — newline in `--owner`/`--dispatch` corrupts meta (severity: low)

`lease.sh:49-52` printf-writes caller strings unescaped. `--owner "$(printf 'evil\npid=1')"` produces a meta with two `pid=` lines; `meta_field` takes the first, so status reports the forged `pid 1`. Callers are trusted dispatch tooling, and the lock itself is unaffected, so low — but a one-line sanitization (reject values containing newlines) closes it.

### F5 — `kill -0` EPERM mislabels a live other-user process as stale (severity: low)

`lease.sh:34` — `kill -0` on a live PID owned by another user fails with EPERM, adding the stale note for a genuinely live worker. Same failure direction as F1; the F1 fix should treat "kill failed" as "unknown", or check `ps -p` as fallback. Never auto-reaped either way, so impact is limited to the misleading label.

### F6 — verify command with leading whitespace yields an empty program name (severity: cosmetic)

`preflight.sh:46` — `--verify-cmd "  printf x"` resolves `program=''` and fails with `blocked: capability: verify command not on PATH: ` (empty name). Correct direction (it blocks), confusing message. Trim first or report the raw command.

## What checked out

- **Atomicity/races:** 10 simultaneous acquirers → exactly one winner, meta written only by the winner; loser never touches the record. `mkdir` lock is sound.
- **Owner safety (modulo F1's signal):** second owner rejected with the first record intact; non-owner release blocked; owner release, no-op release, and post-`--force` reacquisition all behave (test cases 6–8 and my re-runs).
- **Preflight negatives:** wrong base SHA, HEAD≠base, missing CLI, missing/empty verify command, unknown role, role path traversal (`../agents/x`, `.hidden`) all produce structured `blocked: <class>:` lines, exit 1.
- **Portability:** clean runs under macOS `/bin/bash` 3.2.57 and the default bash; only stock tools (`sed`, `date -u`, `perl -pi` in tests) used.
- **Scope:** diff touches only allowed paths; no commits/pushes; `verify.sh` gains syntax checks + the new test; all indexes ≤40 lines (orchestration index 32).
- **Diff-SHA hygiene:** shipped `.gitignore` keeps a held lease invisible to `--diff-sha` (test 5 passes; recomputed SHA matches the report).
- **Report honesty:** commands/exits in the Opus report reproduce, and the deviations section is accurate — except the acceptance-evidence claim that "stale-lease `--force` semantics" are verified, which F1/F2 show is only true for the hand-patched-PID path.

## Remaining risks (post-fix)

- Lease stays advisory and worktree-local — anything that writes without calling `lease.sh` is unpoliced (already named in the Opus report; Phase 4 capability profiles are the upgrade path).
- PID recycling can still make a truly stale lease look live after the F1 fix; `--force` remains the escape and the direction is conservative.
- Preflight resolves only the verify command's first word; a wrapper with broken dependencies passes preflight and is caught later by `--run-verify` (acceptable, documented).
