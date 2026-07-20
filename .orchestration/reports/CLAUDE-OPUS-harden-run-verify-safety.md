done

- Task ID: task_6a4d9e2c7f10
- Attempt: 1
- Role: engineering-minimal-change-engineer
- Base SHA: 1fdcf78851a069b7726493eb46b4c30801dcfaa6
- Risk tier: high
- Allowed paths: template/.orchestration/verify.sh,template/.orchestration/README.md,tests/verify-report.sh
- Verify command: ./verify.sh
- Acceptance check: run: ./tests/verify-report.sh
- Acceptance evidence: `./tests/verify-report.sh` prints `PASS: report verification tests` with 25 refusal cases and 2 permitted-command cases green.
- Verify exit: 0
- Verified at: 2026-07-20T15:31:18Z
- Final diff SHA: d8344f3d02861536010c0073d9f15efd8f8d06fdb1896ef092af545c9ab1ddb0

## Files changed

- `template/.orchestration/verify.sh` — replaced the denylist-plus-`eval` re-run path with a three-rule capability profile and argv execution.
- `tests/verify-report.sh` — added adversarial regression cases and a permitted `./verify.sh` case.
- `template/.orchestration/README.md` — documented the enforced profile in place of the vague "external or destructive effects" wording.

## Exact policy

`require_local_verify_command` now enforces three rules, in order; a command must satisfy all three or the verifier dies before anything executes.

1. **Character profile.** The command string may contain only `[:alnum:]`, whitespace, and `. _ / = : @ + -`. Every shell composition character is therefore absent by construction: `|` pipes, `;`/`&&`/`||` lists, `&` backgrounding, `<`/`>` redirects, `$(...)` and backtick substitution, `~`/`*`/`?` expansion, and both quote styles. Because quotes and backslashes are themselves rejected, nothing can be escaped or quoted back in.
2. **Program shape.** After whitespace splitting, the first word must be either a worktree-relative path (`./verify.sh`, `scripts/run.sh` — never absolute, never containing `..`) or a bare name on `VERIFY_RUNNERS`. `VERIFY_RUNNERS` is now `make npm pnpm yarn cargo go mvn gradle pytest tox rake bundle printf echo true false`. The previous list's interpreters and network fetchers (`python`, `python3`, `node`, `deno`, `ruby`, `bun`, `npx`) were removed: each can execute inline attacker-supplied code or reach the network as its primary function.
3. **Capability deny set.** No word in the command may have a basename in `VERIFY_DENIED`, regardless of path or position: shell/interpreter wrappers (`sh`, `bash`, `zsh`, `perl`, `python3`, `node`, `awk`, `osascript`, …), privilege and exec helpers (`env`, `eval`, `exec`, `xargs`, `sudo`, `nohup`, `timeout`, …), network utilities (`curl`, `wget`, `ssh`, `rsync`, `git`, `docker`, `kubectl`, `aws`, …), and destructive utilities (`rm`, `mv`, `dd`, `shred`, `mkfs`, `chmod`, `kill`, `shutdown`, …). This is what stops `./scripts/sh -c …` and `tools/curl …`, which rule 2's path shape would otherwise accept.

Execution changed from `eval "$command"` to `( cd "$root" && "${VERIFY_ARGV[@]}" )`, where `VERIFY_ARGV` is the whitespace split produced during validation. No shell interprets the recorded string at any point, so rule 1 is the only parser and the validated words are exactly the words executed — the previous `eval` re-parsed the string a second time after checking it.

Unchanged: the 32 KiB bounded transcript, the non-zero-exit failure, the `--run-verify`-only gating, and all static report validation. The documented workflow (`npm run verify`, `./verify.sh`, `make test`) still runs.

## Commands run

| Command | Exit | Evidence |
| --- | ---: | --- |
| `./tests/verify-report.sh` | 0 | `PASS: report verification tests` |
| `./verify.sh` | 0 | `PASS: repository verification` (includes init, report, preflight/lease suites and `bash -n` on all scripts) |

## Tests

`test_run_verify_refuses_external_action` now covers 25 commands (11 pre-existing, 14 added), each of which must be refused with a `refusing to re-run` message before execution. Added this pass:

- Shell wrappers: `npm test && git push origin main`, `npm test; git push origin main` (the pre-existing `sh -c`, `bash -c`, `zsh -c`, `eval`, `env`, `xargs` cases remain).
- Pipes and redirects: `npm test | tee out.txt`, `npm test > out.txt`, `npm test 2>&1`.
- Command substitution: `npm test $(git push origin main)`, and the backtick spelling.
- Backgrounding: `npm test &`.
- Path-shaped wrappers that defeated the old shape check: `./scripts/sh -c git-push`, `tools/curl https://example.com`, `/bin/sh -c true`.
- Interpreters with inline code: `python3 -c import os`, `node -e process.exit`.
- Escape from the worktree: `../outside/verify.sh`.
- Destructive spellings retained: `rm -R somedir`, `rm -fR somedir`, plus `curl https://example.com` and `git push origin main`.

`test_run_verify_runs_repo_verify_script` is new and asserts the positive direction: a repository-local `./verify.sh` is executed and its stdout appears in the bounded transcript. `test_run_verify_runs_project_local_command` (`./.orchestration/verify.sh --diff-sha`) and `test_run_verify_rejects_failing_verify_command` (`false`) still pass, so the profile did not break the permitted path.

## Failures

- None.

## Deviations

- Narrowing `VERIFY_RUNNERS` is a behavior change for template consumers: a project whose `Verify command` starts with `node`, `python`/`python3`, `ruby`, `deno`, `bun`, or `npx` is now refused under `--run-verify` and must move to a project-local script (`./verify.sh`, `scripts/test.sh`) or an allowlisted task runner. The prompt asked for interpreter and network wrappers to be rejected, and these are exactly those; no repository doc or test recorded them as supported.
- Also edited `template/.orchestration/README.md` (one line). The prompt said to preserve the documented supported workflow; leaving the README describing the old denylist behavior would have left the documentation wrong about the enforced boundary.

## Remaining risks

- **Arguments of an allowed runner are not semantically inspected.** `make deploy` or `npm run publish` still runs — the runner is allowlisted and neither word is denied. This is the documented ceiling of the current profile (`ponytail:` comment in the source names it); per-runner argument profiles are the upgrade path. Treat any prompt whose `Verify command` is not a project-local test runner as hostile.
- **A project-local script is trusted once its path passes.** `./verify.sh` can contain anything; the boundary protects against a hostile `Verify command` string, not a hostile committed script. Committed content is covered by review and the diff-SHA scope check, not by this profile.
- **PATH lookup for bare runner names is inherent.** A poisoned `PATH` entry named `make` would run instead of the real one. Out of scope for a string-validation boundary.
- **Deny-set false negatives are possible for unusual local tooling.** A destructive utility not on the list and not path-shaped would still need to be on `VERIFY_RUNNERS` to run, so the allowlist remains the primary gate; the deny set is a second net for path-shaped programs and for denied names appearing as arguments.
- **The deny set is checked on every word, but only argv[0] is executed.** A denied basename in an argument position (`make watch`, `npm test -- --grep open`) refuses a command that would have been inert. Deliberate: fail closed rather than reason about which arguments a runner will pass on. Projects hitting a false positive should move the command into a project-local script.
- **`run:` acceptance checks are still validated for shape only, never executed.** Unchanged from the prior slice and still the documented behavior.
- **Self-validation is now covered.** The coordinator added the prompt's `Allowed paths` field after the initial report, and both static validation and `--run-verify` re-execution now pass for this report.
