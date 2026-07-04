# Gates — live dependency status

Read when: **always**, before picking or dispatching any task. A task touching a `blocked` row must not start.
Update when: the owner records a real identifier/URL/status — edit the row here AND the matching § in [`blockers.md`](./blockers.md).

| Gate | Status | Recorded value | Unblocks | Detail |
| --- | --- | --- | --- | --- |
| _add one row per human-provisioned dependency (infra, credentials, external data, owner decisions)_ | `blocked` | `TBD` | _what work it unblocks_ | _§ link into blockers.md, runbook link if one exists_ |

Rules:

- A gate opens **only** when its row records a real value — never assume human-provisioned infra.
- Keep a "what agents CAN do while blocked" section at the end of [`blockers.md`](./blockers.md) so blocked ≠ idle.
