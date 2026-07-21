done

# Claude Fable review: case-insensitive verify deny set

- Task ID: task_FABLE_CASE_INSENSITIVE_VERIFY_DENY
- Attempt: 1
- Role: engineering-code-reviewer
- Base SHA: 7fa26117c649fa18b07f6b8a6b8885f6ad05abd7
- Risk tier: medium
- Allowed paths: template/.orchestration/verify.sh,tests/verify-report.sh
- Verify command: ./verify.sh
- Acceptance check: run: ./tests/verify-report.sh
- Acceptance evidence: Fable review APPROVE; all requested checks and 24 Bash 3.2 probes passed
- Verify exit: 0
- Verified at: 2026-07-21T13:16:03Z
- Final diff SHA: d3277095c024159c436a42b804301c768d54d0deaf5e5d0d530029c0b2dd25c7
- Verdict: APPROVE

## Files changed

- `template/.orchestration/verify.sh`
- `tests/verify-report.sh`

## Summary

The diff folds each argv word's basename to lowercase (`LC_ALL=C tr '[:upper:]' '[:lower:]'`) before the `VERIFY_DENIED` lookup in `require_local_verify_command`, closing the case-insensitive-filesystem bypass where `tools/CURL` resolved to the same binary as `tools/curl` but missed the lowercase deny set. Four mixed-case path-shaped regression tests were added to `test_run_verify_refuses_external_action`. The change is minimal, correct, Bash 3.2-compatible, and does not touch the runner allowlist or the character/shape rules.

## Findings (severity-ordered)

No blocking findings.

1. **Info — ASCII-only fold is complete, not a gap.** `tr '[:upper:]' '[:lower:]'` under `LC_ALL=C` folds only ASCII, but rule 1 (`grep '[^[:alnum:][:space:]._/=:@+-]'` under `LC_ALL=C`) rejects every non-ASCII byte first, so no Unicode uppercase (e.g. Turkish `İ`) can reach the deny lookup. Verified by probe: `tools/İRM x` → refused as metacharacters. `template/.orchestration/verify.sh:160-163,171`.
2. **Info — allowlist deliberately stays case-sensitive.** `MAKE test` / `Npm test` are still refused (bare name not in `VERIFY_RUNNERS`), which is the fail-closed direction; the diff changes only the deny-side fold. `template/.orchestration/verify.sh:184-186`.
3. **Info (pre-existing, unchanged) — empty basename words.** A word ending in `/` (e.g. `tools/`) yields an empty basename and skips the deny match; shape rule then accepts it and exec fails at run time (a trailing-slash path cannot be executed). Inert, predates this diff, not a blocker.

## Commands run

- `./tests/verify-report.sh`
- `./verify.sh`
- `git diff --check`
- `./template/.orchestration/verify.sh --diff-sha`
- Bash 3.2 adversarial probe harness

## Commands run and results

| Command | Result |
|---|---|
| `./tests/verify-report.sh` | PASS: report verification tests (includes the 4 new mixed-case cases) |
| `./verify.sh` | PASS (init integration, report verification, preflight/leases, repository verification), exit 0 |
| `git diff --check 7fa2611` | clean, no whitespace errors |
| `./template/.orchestration/verify.sh --diff-sha` | `d3277095c024159c436a42b804301c768d54d0deaf5e5d0d530029c0b2dd25c7`, exit 0 |
| Bash 3.2 probe harness (24 cases, `/bin/bash` 3.2.57) | 24/24 PASS |
| Non-ASCII probe `tools/İRM x` | refused (metacharacter rule), exit 1 |

Probe harness sourced the function block of `template/.orchestration/verify.sh` under system `/bin/bash` 3.2.57 and asserted deny/allow per case:

- Denied (all refused before any execution): `tools/curl`, `./rm -rf`, `tools/CURL`, `tools/CuRl`, `./RM -R`, `tools/Git push`, `./scripts/SSH`, `dir/BASH`, `./PYTHON3 -c`, `make WATCH`, `npm run CURL`, `MAKE test`, `Npm test`, `/bin/anything`, `../outside/x.sh`, `a/../b`, empty command, `make test; RM -rf /`, ``echo `CURL x` ``.
- Allowed (unchanged): `./verify.sh`, `make test`, `npm test`, `./scripts/run-tests.sh --fast`, `cargo build --release`.

The test suite itself exercises refusal end-to-end (`--run-verify` on a real repo per command, asserting the `refusing to re-run` message and non-zero exit), so the new cases prove refusal happens before execution, not just string matching.

## Scope assessment

Diff vs base `7fa2611` touches exactly the two allowed paths: a 1-line functional change plus a 4-line comment in `template/.orchestration/verify.sh:168-172`, and 4 new test commands in `tests/verify-report.sh:217-220`. No changes to `VERIFY_RUNNERS`, the character profile, the shape rules, or execution ordering (`require_local_verify_command` still runs before exec in `run_verify_command`, `template/.orchestration/verify.sh:194`).

## Failures

None.

## Deviations

None. Read-only review; no implementation files edited, nothing committed or pushed.

## Remaining risks

- Arguments of an allowed runner remain semantically uninspected (`make deploy` still runs) — pre-existing, documented in the file's `ponytail:` note.
- Empty-basename words skip the deny lookup (finding 3) — pre-existing and inert.

## Blockers

None.
