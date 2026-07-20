approve with improvements

- Task ID: task_76d6b890a6b4
- Reviewer: Claude Fable 5 (read-only), terminal term_be5e0311-225d-4cfa-bdaa-12dbf50e042e
- Reviewed diff: 6fb6bac0e7335608d385db7d2eaae9c178115845 → worktree, final diff SHA `3e45a296e7af9eb330cab4cf85bae95b6b0c2e111f0127368c1abb418ed4ae00` (independently recomputed, matches the implementation report)
- Date: 2026-07-20

## Verdict summary

The completion-integrity slice does what the brief and the fused audit's P0 demand: a `done` report now requires a prompt-matching `Acceptance check`, non-empty `Acceptance evidence`, a zero `Verify exit`, a post-final-edit diff SHA that must still match the worktree, and `--run-verify` re-executes the prompt's `Verify command` after the final edit with byte-bounded output and a refusal path for external actions. All 12 verifier tests and the full `./verify.sh` suite pass; the implementation report's claims reproduce exactly, including the diff SHA. Findings below are real but none invalidates the slice: two are documented ceilings of the chosen denylist design, one is an inherent trust boundary the audit already schedules for a later phase.

## Commands and exit codes

| Command | Exit | Evidence |
| --- | ---: | --- |
| `./verify.sh` | 0 | `PASS: init integration tests` / `PASS: report verification tests` / `PASS: repository verification` (18.8s) |
| `./tests/verify-report.sh` | 0 | `PASS: report verification tests` (12 cases) |
| `./tests/init.sh` | 0 | `PASS: init integration tests` (4 cases) |
| `./template/.orchestration/verify.sh --diff-sha` | 0 | `3e45a296…ae00` — matches the report's Final diff SHA |
| `./template/.orchestration/verify.sh .orchestration/reports/CLAUDE-OPUS-completion-integrity.md` | 0 | `valid report` (static) |
| `./template/.orchestration/verify.sh --run-verify .orchestration/reports/CLAUDE-OPUS-completion-integrity.md` | 0 | re-ran `./verify.sh`, transcript bounded, `valid report` |
| Probe 1 (below) | 1 | bypass confirmed — command executed, not refused |
| Probe 2 (below) | 1 | bypass confirmed — command executed, not refused |
| Probe 3 (below) | 0 | prompt-tamper accepted (trusted-input boundary) |
| Probe 4 (below) | 0 | mode change after verification undetected |

## Findings

### F1 — Medium: external-action denylist is bypassed by any quoting or wrapper — the command executes

- File: `template/.orchestration/verify.sh:123-128` (`reject_external_action`)
- The regex requires a separator (`^`, space, `;`, `&`, `|`) immediately before the banned token. A quote character is not a separator, so a verify command of `sh -c 'git push origin main'` sails past the guard and **is executed** under `--run-verify`.
- Reproduction (fresh init'd repo, verify command `sh -c 'git push origin main'`): `verify.sh --run-verify <report>` printed `verify command failed with exit 128: sh -c 'git push origin main'` — exit 128 is git failing on a missing remote, i.e. the push was attempted. With a configured remote this publishes.
- User impact: a malicious or confused prompt whose `Verify command` wraps an external action in `sh -c`, `bash -c`, `env`, `xargs`, or plain quotes gets that action executed on the coordinator's machine during validation.
- The code comment and the implementation report both declare this a denylist with a capability-profile upgrade path, so it is a documented ceiling, not a hidden defect. But given the guard exists specifically to stop re-execution of external actions, consider at minimum also matching after `'`/`"`/`=` or refusing shell-wrapper prefixes (`sh -c`, `bash -c`, `eval`, `env`, `xargs`) until capability profiles land.

### F2 — Low: `rm -R` (uppercase) escapes the denylist

- File: `template/.orchestration/verify.sh:125`
- `rm[[:space:]]+-[a-z]*r` matches `-r`/`-rf` but not `-R`/`-fR`, which are equally recursive on BSD and GNU rm.
- Reproduction: verify command `rm -R somedir` under `--run-verify` was executed (exit 1 only because the dir was absent), not refused.
- One-character fix: `-[a-zA-Z]*[rR]`.

### F3 — Medium: prompt files are trusted input — a worker can widen its own scope by editing the prompt

- File: `template/.orchestration/verify.sh:15-32` (diff SHA exclusions), `:192-195` (scope check)
- Prompts and reports are excluded from the diff SHA and from `changed_paths`, so nothing detects a worker rewriting its own prompt's `Allowed paths` (or `Acceptance check`) to make its report validate.
- Reproduction: in a fresh repo I wrote `secret.txt` outside the intended scope, set `Allowed paths: result.txt,secret.txt` in **both** the prompt and report copies, and the verifier printed `valid report` (exit 0).
- User impact: the verifier proves prompt/report consistency and worktree state, not that the prompt is the one the coordinator dispatched. The false-completion move shifts from "lie in the report" to "edit the prompt".
- This is an inherent boundary of the slice — the fused audit's provenance item (immutable prompt hash, Phase 4 / addition 3) is the designed fix, and the implementation report's Scope-resolution section shows the author understood exactly this hazard. Acceptable now; the coordinator must treat prompt files as coordinator-owned (e.g., hash or commit them at dispatch). Worth a one-line warning in `.orchestration/README.md` until provenance lands.

### F4 — Low: permission-bit change after verification is undetected for untracked files

- File: `template/.orchestration/verify.sh:23-30`
- Untracked files contribute `name + content sha` to the diff SHA; mode is not hashed (tracked files are covered by `git diff --binary`).
- Reproduction: after computing the diff SHA, `chmod +x result.txt` (untracked) — verifier still printed `valid report` (exit 0). A file becoming executable after final verification is a real state change (e.g. a hook or script) that "edit-after-verification" is meant to catch.
- Fix if wanted: append the mode from `ls -l`/`stat` or `git ls-files -s` semantics to the untracked hash lines.

### F5 — Low: `tests/init.sh` depends on ripgrep

- File: `tests/init.sh:54` — `rg -n '\{\{[A-Z_]+\}\}' "$target"` makes `./verify.sh` fail on machines without `rg` installed, which contradicts the repo's BSD/GNU-portable stance. `grep -rEn` does the same job with stock tools.

### F6 — Info: `run:` acceptance checks are shape-validated, never executed

- File: `template/.orchestration/verify.sh:103-118`
- Only the prompt's `Verify command` is re-executed; a `run:` acceptance check relies on self-attested evidence. This matches the brief (item 3 only requires re-running the verify command) and is declared in the implementation report's Remaining risks — recorded here so the next slice owner sees it.

### F7 — Info: full verify transcript is deleted, not stored as an artifact

- File: `template/.orchestration/verify.sh:135-141` — the audit's bounded-evidence control says "store full output as an artifact"; `run_verify_command` prints the first 32 KiB and deletes the log. Fine at this scale; keep the mktemp path (don't delete) or move it under `.orchestration/` if long verify output ever matters.

## Scope, baseline, and backward compatibility

- Scope: every changed path is inside the coordinator-widened `Allowed paths`; the report's Scope-resolution section correctly documents that the widening was a coordinator ruling covering pre-existing baseline work (`init.sh`, `template/docs/engineering/index.md`, `template/docs/orchestration/tasks.md`), and the worker's actual footprint matches its `## Files changed`.
- Baseline preserved: the pre-existing staging/atomic-install work in `init.sh`, the GRAPHIFY 0/1 validation, blank-binding refusal, and both test suites are intact and green. The GRAPHIFY change (any non-empty value → must be exactly `0`/`1`, else refuse) is a behavior change from the baseline flag, but it fails fast with a clear message and predates this dispatch.
- Docs: all `template/docs/**/index.md` files stay ≤40 lines (enforced by `verify.sh`, which passed); README, AGENTS.md, orchestration docs, and `.orchestration/README.md` accurately describe the new fields and `--run-verify`, including the external-action refusal.
- Shell portability: `bash` shebangs throughout, `shasum -a 256` (ships with macOS and with perl on Linux), `head -c`, portable `mktemp` templates, perl for in-place edits. No BSD/GNU divergence found beyond F5.
- No commits, pushes, PRs, or tracker mutations were made by the implementation or by this review; this report is my only write.

## Remaining risks

- F1/F2: the denylist is the enforcement boundary for `--run-verify` until capability profiles (audit Phase 4) exist; treat any prompt whose `Verify command` is not a project-local test runner as hostile.
- F3: prompt integrity is unenforced; coordinator must own prompt files (commit or hash them at dispatch) until provenance lands.
- `run:` acceptance checks (F6) still trust the worker's evidence text — the behavioral-acceptance gap is narrowed, not closed.
- The verifier requires worktree HEAD to equal the prompt's Base SHA, so it cannot validate historical reports after a commit lands; that is by design (reports are immutable history) but worth knowing before wiring it into CI.
