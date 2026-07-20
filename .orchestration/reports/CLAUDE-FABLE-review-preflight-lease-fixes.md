request changes

# Claude Fable review — preflight/lease fix slice

- Task ID: task_5b7e4a1c9d22 · Attempt 1 · Role engineering-software-architect
- Base SHA `1a85d0fc5665ccc854bbc42d99839d57470a4517`, reviewed read-only: diff + uncommitted files, fix prompt, fix report
- Verdict: four of the five required fixes (F1, F3, F4, F5) are correct, tested, and portable. Fix 2 covers only half its requirement — the fix brief says `release --force` must work "even when `.lease/meta` is missing **or unreadable**", and the unreadable case still bricks `--force` silently, the exact failure signature that drove the first request-changes. The remaining fix is one character plus one test line, so this is a narrow re-spin, not a redesign.

## Commands and results

| Command | Exit | Result |
| --- | ---: | --- |
| `./tests/preflight-lease.sh` | 0 | `PASS: preflight and writer leases` (11 cases) |
| `./verify.sh` | 0 | all four PASS lines |
| `./template/.orchestration/verify.sh --diff-sha` | 0 | `bea3caef8985…` — matches the fix report's Final diff SHA |
| `/bin/bash ./tests/preflight-lease.sh` (bash 3.2.57) | 0 | portable to the macOS floor |
| fresh-lease probe (acquire → sleep → status) | — | no stale note; recorded pid = invoking shell, live |
| `LEASE_PID=$$` wrapped acquire | — | recorded pid honors the override |
| preflight over a held lease | 1 | single `blocked: lease: held by …` prefix |
| 10 concurrent acquirers | — | exactly one winner, meta intact |
| missing-meta dir: unforced release / `--force` | 1 / 0 | unforced blocked with dir intact; `--force` clears it |
| **unreadable meta (`chmod 000`): `release --owner eve --force`** | **1** | **silent, no output, lease dir survives — F-1 below** |
| newline in `--owner` / `--dispatch` | 1 | rejected before `mkdir`; no lease dir created |
| `ps -p 1` / `ps -p 2147483647` | 0 / 1 | confirms the `pid_live` `ps` fallback semantics on this host |

## Findings

### F-1 — unreadable `meta` still bricks `release`, including `--force` (severity: medium) — reopens half of required fix 2

`template/.orchestration/lease.sh:25` — the crash-window guard is `[ -f "$META" ] || return 0`. A meta that **exists but cannot be read** passes the `-f` test, then `sed … | head` fails, `pipefail` makes the pipeline non-zero, and the direct assignment `held=$(meta_field owner)` at `lease.sh:79` aborts the script under `set -e` — silently, before `rm -rf`, with no diagnostic (violating the script's own `die` convention).

Reproduction:

```
$ ./.orchestration/lease.sh acquire --dispatch D5 --owner eve
$ chmod 000 .orchestration/.lease/meta
$ ./.orchestration/lease.sh release --owner eve --force ; echo $?
1                                   # no output at all
$ ls -d .orchestration/.lease
.orchestration/.lease               # stuck; only manual rm -rf recovers
```

User impact: same class as the original F2 — the documented escape hatch fails silently in a broken state it exists to clear. Reachable without tampering: an acquirer running with `umask 077` writes `meta` mode 600, and any different-UID coordinator (a real multi-user dispatch topology) then cannot read it — its `status` degrades gracefully to "held by unknown" (substitution-in-argument path), but its `release --force` dies. The fix prompt's requirement 2 names this case explicitly ("missing or unreadable"); the fix report's own wording (`[ -f "$META" ]`) records the narrower guard, and its acceptance evidence claims only the missing-meta case.

Fix direction: `[ -r "$META" ] || return 0` (subsumes missing), plus a `chmod 000` regression case next to `test_force_release_clears_a_lease_with_no_meta`. Note the test needs a non-root runner to be meaningful — guard or skip under `EUID 0`.

### F-2 — garbage `LEASE_PID` in the environment fails even read-only commands (severity: low)

`lease.sh:126-127` validates `LEASE_PID` before command dispatch, so `LEASE_PID=abc lease.sh status` dies with `LEASE_PID must be a numeric process id` even though `status`/`release` never use the value. Fail-fast is defensible; moving the validation into the `acquire` arm would be slightly friendlier. Not blocking.

## Verified fixes

- **F1 (stale-on-every-lease) — fixed.** `lease.sh:126` records `$PPID` (validated numeric), `LEASE_PID` overrides for transient wrappers. Probes: fresh lease shows no stale note after a 1s delay under both default bash and 3.2; the recorded pid is the invoking shell; the `LEASE_PID=$$` override lands in `meta`. Regression test `test_a_fresh_lease_is_not_stale` asserts via a separate `status` call with a comment explaining the command-substitution trap, and the fix report's mutation check (`$PPID`→`$$` fails the suite) shows it bites.
- **F2, missing-meta half — fixed.** `mkdir`-only lease dir: `status` exits 1 reporting "held by unknown", unforced release blocks with the dir intact, `--force` clears it. Test `test_force_release_clears_a_lease_with_no_meta` covers exactly this.
- **F3 (double prefix) — fixed.** `preflight.sh:72-73` captures `lease.sh status` once and strips the inner `lease: ` prefix; output is a single `blocked: lease: held by …`. The single capture also removes the two-call TOCTOU that could report a freed lease as blocked. Test asserts the exact prefix.
- **F4 (newline injection) — fixed.** `lease.sh:120-121` rejects newlines in `--owner`/`--dispatch` after parsing, before `mkdir`; probe confirms no lease dir is created on rejection. Test covers both flags.
- **F5 (EPERM mislabel) — fixed.** `pid_live` (`lease.sh:32-40`): non-numeric → live, `kill -0` success → live, `ps -p` success → live, only `ps` exit exactly 1 proves death, anything else (ps missing, exit ≥2) → live. Conservative in every indeterminate branch; `ps -p` semantics confirmed on this host for a root-owned live PID (exit 0) and an impossible PID (exit 1). Only invoked in condition context, so `set -e` is inert inside it.
- **Everything carried over holds:** atomic acquisition (10-way race, one winner, meta written only by the winner), owner-aware release, second-owner rejection with record intact, diff-SHA invisibility of the held lease, preflight negative paths, all indexes ≤40 lines, scope limited to the fix brief's named files (`lease.sh`, `preflight.sh`, the test, one README bullet whose new PID-contract wording is accurate).

## Remaining risks (accepting the fix report's list, with checks)

- PID recycling and the wider "indeterminate = live" rule can make a truly dead lease look live; direction is deliberate and `--force` remains the escape.
- A transient wrapper that doesn't set `LEASE_PID` reintroduces a weaker F1; my counterfactual (`bash -c` wrapper) didn't even trigger it because bash exec-optimizes single commands, which narrows the practical exposure further. Documented in the README bullet.
- The lease stays advisory and worktree-local (unchanged; Phase 4 capability profiles are the upgrade path).
- F6 (leading-whitespace verify command → empty program name in the message) remains open by scope; it still blocks correctly.
- The crash-window test simulates the state (`mkdir` without meta), not the race producing it — acceptable, the observable state is what release must handle.
