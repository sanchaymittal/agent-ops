# Claude Opus implementation: case-insensitive verify deny set

- Task ID: task_CASE_INSENSITIVE_VERIFY_DENY
- Attempt: 1
- Role: engineering-minimal-change-engineer
- Base SHA: 7fa26117c649fa18b07f6b8a6b8885f6ad05abd7
- Risk tier: medium
- Allowed paths: template/.orchestration/verify.sh,tests/verify-report.sh
- Verify command: ./verify.sh
- Acceptance check: run: ./tests/verify-report.sh

Implement the next hardening slice from the Claude Fable review of the recorded `--run-verify` capability profile. Make deny-set basename matching case-insensitive for path-shaped commands, preserving Bash 3.2 compatibility and the fail-closed behavior.

Add focused tests proving `tools/CURL`, `tools/CuRl`, and equivalent mixed-case path-shaped denied utilities are refused before execution, while permitted local `./verify.sh` still runs. Keep the change minimal; do not broaden the runner allowlist, change argument profiles, or address unrelated prompt provenance. Update the matching implementation report with exact commands/results. Do not commit, push, or create a PR.
