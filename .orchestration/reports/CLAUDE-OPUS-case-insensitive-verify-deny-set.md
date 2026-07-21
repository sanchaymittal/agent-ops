done

- Task ID: task_CASE_INSENSITIVE_VERIFY_DENY
- Attempt: 1
- Role: engineering-minimal-change-engineer
- Base SHA: 7fa26117c649fa18b07f6b8a6b8885f6ad05abd7
- Risk tier: medium
- Allowed paths: template/.orchestration/verify.sh,tests/verify-report.sh
- Verify command: ./verify.sh
- Acceptance check: run: ./tests/verify-report.sh
- Acceptance evidence: `./tests/verify-report.sh` prints `PASS: report verification tests`; `test_run_verify_refuses_external_action` now covers 29 refusal cases (4 mixed-case path-shaped ones added) and the permitted `./verify.sh` / `./.orchestration/verify.sh --diff-sha` cases stay green.
- Verify exit: 0
- Verified at: 2026-07-21T13:07:41Z
- Final diff SHA: d3277095c024159c436a42b804301c768d54d0deaf5e5d0d530029c0b2dd25c7

## Files changed

- `template/.orchestration/verify.sh` — fold each word's basename to lower case (via `tr`) before the deny-set lookup, so path-shaped denied utilities are refused regardless of case.
- `tests/verify-report.sh` — added four mixed-case path-shaped refusal cases.

## Exact change

In `require_local_verify_command`, the per-word basename was

```sh
base=${word##*/}
```

and is now folded to lower case before the deny-set `case` lookup:

```sh
base=$(printf '%s' "${word##*/}" | LC_ALL=C tr '[:upper:]' '[:lower:]')
```

`VERIFY_DENIED` is written entirely in lower case. On a case-insensitive
filesystem (macOS default), `tools/CURL` resolves to the same binary as
`tools/curl`, so a mixed-case spelling was a straightforward bypass of the
deny set. Folding the basename closes it. `tr` is used rather than `${var,,}`
because the target is Bash 3.2 (macOS system Bash), which has no lower-case
parameter expansion. `LC_ALL=C` keeps the transliteration to ASCII A–Z, so
locale collation can't change which characters fold.

The metacharacter gate (rule 1) already permits `[:alnum:]`, so uppercase
letters pass it unchanged and reach this lookup. Rule 2 (program shape) and
the runner allowlist are untouched: the change only affects which basenames
rule 3 recognizes as denied. Fail-closed behavior is preserved — a folded
basename that matches `VERIFY_DENIED` still `die`s before any execution.

## Commands run

| Command | Exit | Evidence |
| --- | ---: | --- |
| `./tests/verify-report.sh` | 0 | `PASS: report verification tests` |
| `./verify.sh` | 0 | `PASS: repository verification` (init, report, preflight/lease suites plus `bash -n` on all scripts) |
| `bash template/.orchestration/verify.sh --diff-sha` | 0 | `d3277095c024159c436a42b804301c768d54d0deaf5e5d0d530029c0b2dd25c7` |

## Tests

Added to `test_run_verify_refuses_external_action`, each expected to be
refused with `refusing to re-run` before execution:

- `tools/CURL https://example.com` — basename `CURL` → `curl` (denied).
- `tools/CuRl https://example.com` — mixed case, same fold.
- `./RM -R somedir` — basename `RM` → `rm` (denied).
- `tools/Git push origin main` — basename `Git` → `git` (denied).

The pre-existing lower-case path-shaped case `tools/curl …` and the positive
cases (`test_run_verify_runs_project_local_command` runs
`./.orchestration/verify.sh --diff-sha`; `test_run_verify_runs_repo_verify_script`
runs `./verify.sh`) still pass, confirming the fold did not broaden or narrow
anything but the case sensitivity of the deny-set lookup.

## Failures

- None.

## Deviations

- None. No runner allowlist change, no argument-profile change, no prompt
  provenance work — scope held to the case-folding slice.

## Remaining risks

- The deny set remains a second net behind the runner allowlist; a
  destructive utility that is neither listed nor path-shaped still relies on
  the allowlist to be refused. Unchanged by this slice.
- Case folding is ASCII-only (`LC_ALL=C tr A–Z`). A Unicode-cased homoglyph
  of a denied name would not fold, but such a byte would first have to pass
  the rule-1 metacharacter gate, which only permits `[:alnum:]` and a fixed
  ASCII punctuation set — so this is not reachable through the recorded
  command string today.
