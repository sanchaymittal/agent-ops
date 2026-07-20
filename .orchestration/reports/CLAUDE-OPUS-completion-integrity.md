done

- Task ID: task_c90bc3c964ed
- Attempt: 1
- Role: engineering-minimal-change-engineer
- Base SHA: 6fb6bac0e7335608d385db7d2eaae9c178115845
- Risk tier: medium
- Allowed paths: README.md,init.sh,template/**,tests/**,verify.sh,.orchestration/prompts/CLAUDE-OPUS-completion-integrity.md,.orchestration/reports/CLAUDE-OPUS-completion-integrity.md
- Verify command: ./verify.sh
- Acceptance check: run: ./tests/verify-report.sh
- Acceptance evidence: `./tests/verify-report.sh` exits 0 with `PASS: report verification tests` across 12 cases, including the 7 new acceptance/run-verify cases; each negative case fails the verifier before the fix is applied to the report copy.
- Verify exit: 0
- Verified at: 2026-07-20T09:57:59Z
- Final diff SHA: 3e45a296e7af9eb330cab4cf85bae95b6b0c2e111f0127368c1abb418ed4ae00

## Files changed

- `template/.orchestration/prompts/TEMPLATE.md` — adds the `Acceptance check` field and the one-line rule for how to state it.
- `template/.orchestration/reports/TEMPLATE.md` — adds `Acceptance check` and `Acceptance evidence` fields so evidence is a required field, not prose.
- `template/.orchestration/verify.sh` — acceptance match/format/artifact-existence checks on `done`, plus `--run-verify` re-execution with a byte-bounded transcript and an external-action refusal.
- `tests/verify-report.sh` — 7 new cases and a `create_repo` verify-command parameter; existing helper now substitutes the two new placeholders.
- `template/.orchestration/README.md`, `template/docs/orchestration/index.md`, `template/docs/orchestration/orca.md`, `template/AGENTS.md`, `README.md` — document the acceptance field and `--run-verify`; all indexes stay ≤40 lines.

## Commands run

| Command | Exit | Evidence |
| --- | ---: | --- |
| `./tests/verify-report.sh` | 0 | `PASS: report verification tests` |
| `./verify.sh` | 0 | `PASS: init integration tests` / `PASS: report verification tests` / `PASS: repository verification` |
| `./template/.orchestration/verify.sh --diff-sha` | 0 | `3e45a296e7af9eb330cab4cf85bae95b6b0c2e111f0127368c1abb418ed4ae00` |

## Failures

- `printf '--- ... ---\n'` in the new transcript banner was parsed by bash as an option and exited 2, which surfaced as a false `--run-verify` rejection. Classification: product defect in the new code; fixed by moving the literal into a `%s` argument. Caught by the new success case, which is exactly what it exists for.

## Deviations

- The brief's bare `.orchestration/prompts/TEMPLATE.md`, `.orchestration/reports/TEMPLATE.md`, and `.orchestration/verify.sh` do not exist at the repository root; those files ship from `template/.orchestration/**`, which is also an allowed path. Edited the `template/` copies.
- Acceptance evidence is a field rather than a `## Acceptance evidence` section, so the existing `require_field` placeholder/blank guard covers it without new parsing.

## Scope resolution

- This report was `blocked: decision:` for one cycle. With the brief's original allowed paths, `verify_scope` rejected it: `changed path is outside prompt scope: init.sh`. Three files (`init.sh`, `template/docs/engineering/index.md`, `template/docs/orchestration/tasks.md`) were already modified in this worktree at session start, before this dispatch, and I did not touch them — "preserve existing changes" and the original path list could not both hold here.
- The coordinator ruled: widen the boundary to `README.md,init.sh,template/**,tests/**,verify.sh` plus this dispatch's prompt/report records. That value is now in both the prompt and this report. I did not widen it on my own initiative; making my own evidence pass by editing the scope field is the false-completion move this slice exists to block.
- The widened boundary covers the pre-existing baseline work, so `verify_scope` now passes over the union of that work and mine. It is broader than what this task actually touched — reviewers should read `## Files changed` for the real footprint, not the path list.
- Implementation logic is byte-identical to the pre-block state; only `Allowed paths`, `Task ID`, and this section changed. Final diff SHA is unchanged at `3e45a29…` because prompt/report records are excluded from the hash.

## Remaining risks

- The external-action guard is a denylist (`git push|reset|clean`, `gh`, `curl`, `ssh`, `kubectl`, `rm -r`, …), marked with a `ponytail:` comment. A verify command that reaches the network through an unlisted wrapper still executes under `--run-verify`. Upgrade path is the capability profile from Phase 4 of the audit; owner: whoever picks up the preflight/lease slice.
- `run:` acceptance checks are validated for shape and evidence, not executed. Only the prompt's `Verify command` is re-run, per the brief.
