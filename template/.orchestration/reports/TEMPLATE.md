<OUTCOME>

- Task ID: <TASK_ID>
- Attempt: <ATTEMPT>
- Role: <ROLE>
- Base SHA: <BASE_SHA>
- Risk tier: <RISK_TIER>
- Allowed paths: <ALLOWED_PATHS>
- Verify command: {{VERIFY_CMD}}
- Acceptance check: <ACCEPTANCE_CHECK>
- Canonical prompt SHA: <PROMPT_SHA>
- Acceptance evidence: <ACCEPTANCE_EVIDENCE>
- Verify exit: <VERIFY_EXIT>
- Verify transcript SHA: <VERIFY_TRANSCRIPT_SHA>
- Failure reason: <FAILURE_REASON>
- Verified at: <VERIFIED_AT>
- Final diff SHA: <FINAL_DIFF_SHA>

For `done`, `Verify transcript SHA` is the SHA-256 of the first 32768 bytes of
the verify transcript. The coordinator must run `verify.sh --run-verify`; the
rerun prints and checks that bounded hash when the field is populated.

## Files changed

- `path` — why this file was required.

## Commands run

| Command | Exit | Evidence |
| --- | ---: | --- |
| `command` | 0 | concise output or artifact path + hash |

## Failures

- None, or quote each failure and classify it as probe, environment, test, patch conflict, or product defect.

## Deviations

- None, or name every approved deviation from the prompt.

## Remaining risks

- None, or state the unresolved risk and owner.
