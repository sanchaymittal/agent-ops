# Engineering

Read when: adding code, tests, CI config, or anything the verify pipeline touches.

Code entrypoint: `{{VERIFY_CMD}}` — the aggregate check CI runs after the final edit.
Evidence entrypoint: the repository's configured verify command, plus `git diff --check` — both must be green for a code change.

| File | What | Read when |
| --- | --- | --- |
| _TODO(project): harness plan, smoke tiers, schema-as-contract docs as they appear._ | | |
