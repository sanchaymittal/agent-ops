# Claude Opus review-fix brief — completion integrity

Apply only the actionable Fable findings F1, F2, and F5 from `.orchestration/reports/CLAUDE-FABLE-review-completion-integrity.md`.

Required fixes:

1. Harden `template/.orchestration/verify.sh` so `--run-verify` refuses shell wrappers and quoted/escaped forms of external or destructive commands, including `sh -c`, `bash -c`, `zsh -c`, `eval`, `env`, `xargs`, quoted `git push`, and recursive `rm -R`/mixed-case variants. Prefer a clear fail-closed rule over an increasingly fragile denylist. Keep safe local test commands working.
2. Add focused tests proving these bypasses are refused and ordinary `./verify.sh` still runs.
3. Replace the `rg` dependency in `tests/init.sh` with a stock portable tool.
4. Update the implementation report's commands/evidence and write `.orchestration/reports/CLAUDE-OPUS-fable-fixes-completion-integrity.md`.

Do not address F3 prompt provenance or F4 file modes in this slice; record them as remaining risks for the next preflight/provenance slice.

Do not commit, push, create a PR, or mutate trackers. Run focused tests and `./verify.sh`. First report line must be `done` or a precise `blocked:` outcome.
