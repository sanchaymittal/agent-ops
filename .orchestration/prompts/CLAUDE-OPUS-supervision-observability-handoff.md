# Handoff — supervision cost: what is measured, what is still contradictory

- Task ID: task_supervision_observability
- Attempt: 1
- Role: engineering-minimal-change-engineer
- Base SHA: e5263da241ff440f4a1acdf2391c3cf560bc8462
- Risk tier: medium
- Verify command: ./verify.sh
- Acceptance check: run: ./tests/burn.sh

## Why this exists

Two Codex coordinator sessions on 2026-07-26 spent 53 percentage points of a
weekly quota on one PR. The investigation produced two merged changes to
`burn.py` and `supervision.md`, and surfaced five problems that are still open.
Read this before touching either file — several of the obvious fixes were tried
and rejected for reasons recorded here.

## Merged already

- **PR #11** (`4d66e1c`) — `--sessions` labels forked subagent threads with
  their agent path, keyed on `session_meta.thread_source == "subagent"`.
  `supervision.md` gained a rule bounding the re-dispatch loop.
- **PR #12** (`e5263da`) — `burn.py` reads `--timeout-ms` on supervision calls
  and fails any window under 15 minutes. `--min-wait-ms` configures the floor.

Both were reviewed on two axes before merge; both reviews found real defects
that were fixed before merge. Do not assume the merged state is the first draft.

## Measured sessions — these are the fixtures

All under `~/.codex/sessions/2026/07/26/`. `python3
template/.orchestration/burn.py --since 2026-07-26 --sessions` reproduces.

| session | tokens | verdict |
| --- | --- | --- |
| `019f9dfd-f84` | 43.5M | 222 polls / 32 tasks = 6.9; 60 of 68 windows under 15m |
| `019f9ff3-74c` | 31.5M | 120 polls / 4 tasks = 30.0; 8 of 8 windows under 15m |
| `019f9ffc-194` | 10.7M | the worker both coordinators drove |
| `019fa01f-66c`, `019fa01f-7a1`, `019fa004-ead`, `019fa005-094` | 26.1M | four subagent reviewers forked from `019f9ffc-194` |

Two failure modes, same cost:

- `019f9ff3` made **zero** `orca orchestration` calls. It hand-rolled
  `for n in 1..12; do test -f report; done`. It did not know the primitive.
- `019f9dfd` called `orchestration check --wait` correctly and set the window to
  60s on 60 of 68 waits. Median gap between wake-ups: 73 seconds. It knew the
  primitive and used it as a poll loop.

The second is the more important one. Its prompt contained a copyable
`--timeout-ms 60000` (a post-dispatch delivery check) two lines above the prose
"these tasks run 15-60 minutes". The literal beat the rule. It self-corrected
the `check --wait` window partway through and never dropped the 60s
`terminal wait` recipe, because that one came from the prompt.

## Open problem 1 — the two rules are jointly unsatisfiable for a single task

`supervision.md` requires a window >= 15 minutes **and** <= 2 supervision calls
per dispatched task. One 60-minute task waited at the floor times out three
times: 4 supervision calls against 1 dispatched task, which breaches the ratio.
A coordinator following the file exactly fails the meter.

It does not arise with several tasks in flight — one wait covers all of them,
which is what "wait wide" asks for. So the contradiction is specific to a
single long dispatch.

Both rules predate the current work; enforcing the window only made the tension
visible. Deliberately not resolved, because every fix reshapes a documented
budget:

- Exempt a re-wait at a compliant window from the ratio. Matches the file's own
  "a timeout is a checkpoint, not a failure: re-wait", but then a coordinator
  can wake 100 times at 15-minute windows and pass.
- Raise the floor to ~30 minutes so 2 waits cover a 60-minute task. Invents a
  number the file cannot source.
- Scale the budget by task duration. Needs a duration the logs do not record.

**Decide this before writing code.** It is a docs decision, not a meter bug.

## Open problem 2 — `burn.py` cannot see Claude Code sessions at all

`burn.py` reads `~/.codex/sessions/**/*.jsonl` and says so in its scope limits.
Claude Code sessions live at
`~/.claude/projects/<slug>/<session-uuid>.jsonl` in a different schema: one JSON
object per line, `type` in `{user, assistant, system, ...}`, and per-message
`message.usage` carrying `input_tokens`, `output_tokens`,
`cache_read_input_tokens`, `cache_creation_input_tokens`. Tool calls appear as
`message.content[].type == "tool_use"` with a `name`.

This matters because the coordinators being measured were told to dispatch
Claude workers, and because any coordinator that runs on Claude Code is
currently invisible to the rule it is subject to. This is the single most
useful next change.

Note before starting: `classify()` keys off Codex tool names (`exec_command`,
`write_stdin`, `apply_patch`) and raw command text. Claude Code tool names are
different (`Bash`, `Edit`, `Read`, `Agent`). The command-text patterns (`POLL`,
`DISPATCH`, `TASK_START`) are substrate-independent and should port; the
tool-name sets are not.

## Open problem 3 — tool-level yields are counted as polls but their window is invisible

`POLL_TOOLS = {"wait", "wait_agent"}` and an empty `write_stdin` are classified
as supervision, so they count against the ratio. Their declared window is
deliberately **not** read (PR #12): `yield_time_ms` on those tools is the same
field, with the same meaning, that `exec_command` carries on every ordinary
shell call — how long the call parks before returning output so far. Reading it
from some tools and not others splits on tool name while claiming to split on
meaning.

Consequence: a coordinator that polls exclusively with 30s `wait` yields trips
the ratio but never the window rule. If that gap needs closing, the fix is to
find a field that actually distinguishes a supervision wait from a shell park —
not to re-add the reading that was removed. `wait_agent` declares `timeout_ms`
as a JSON key (not the CLI flag) and carries a `targets` array; neither is read
today. `targets` is also the only available signal for "one wait covering every
outstanding worker", which nothing currently enforces.

## Open problem 4 — subagent tokens are labelled but not attributable

Forked threads are labelled, and that is all. Their tokens stay in every total,
and a fork that dispatches is still judged as a coordinator. Their round-trips
land ~90% in `<none>` because inter-agent messages drive them rather than tool
calls. Do not "fix" this by attributing `patch_apply_end` to EDIT: a fork's log
replays the parent's patches within milliseconds of the fork, so that would
count one worker's edits once per fork. Verified on `019fa01f-66c`: 24 patches,
all inside a 2ms window at fork time.

## Open problem 5 — the prompt is where the cost is set

The most effective change found is not in the meter. `019f9dfd` inherited its
60s window from an example in its own prompt. Any prompt template that shows a
`--timeout-ms` literal will have that literal generalized to every wait,
regardless of surrounding prose. Consider whether
`template/.orchestration/prompts/TEMPLATE.md` should carry a supervision
section, and whether any example window in any shipped prompt should be
below the floor the rules enforce.

## Unrelated, do not carry it forward

The working tree at handoff time has an uncommitted `README.md` rewrite (110
insertions) and an untracked `ADOPT.md`, both written 2026-07-27 10:41 by
something other than the supervision work. Neither is in PR #11 or #12 — those
commits staged explicit paths. Confirm provenance before committing or
discarding.

## Dogfooding note

The session that produced this handoff spent **26.6M tokens over 231 turns**
(81 Bash, 40 Edit, 4 Agent) to investigate ~75M tokens of other sessions. Its
output was 177k tokens — 0.67% of spend, against 0.13% for the coordinator it
was criticising. Better, not good. If a session is going to audit supervision
cost, its own cost belongs in the report.

## Suggested order

1. Decide open problem 1. Docs only, unblocks how the meter should behave.
2. Open problem 2 — teach `burn.py` the Claude Code schema. Largest coverage
   gain, no rule changes needed.
3. Open problem 5 — audit shipped prompts for sub-floor window literals.
4. Open problems 3 and 4 only if a real session demonstrates the gap. Both are
   currently theoretical, and both have a rejected obvious fix recorded above.

Write the report to `.orchestration/reports/<this-file's-name>.md`. Run
`./verify.sh` and `./tests/burn.sh` after any change to the meter.
