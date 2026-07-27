# Claude Code session audit — where the tokens and the quality went

Date: 2026-07-27
Auditor: Claude Opus 5, session `7b2dc990`
Scope: 48 Claude Code transcripts under
`~/.claude/projects/-Users-sanchaymittal-github-agent-ops-template/`
(2026-07-06 .. 2026-07-27), plus the 24 Codex rollouts of 2026-07-26 for
comparison, plus this repo's 35 commits.

Reproduce with:

```sh
python3 template/.orchestration/burn.py --since 2026-07-01 --sessions \
  --root ~/.claude/projects/-Users-sanchaymittal-github-agent-ops-template
python3 template/.orchestration/burn.py --since 2026-07-26 --sessions --root ~/.codex/sessions
```

## What had to change before the numbers meant anything

`burn.py` could not read Claude Code at all, and the Codex numbers it did
produce were wrong in two ways. All three are fixed in this change; the
existing rules and thresholds are untouched.

1. **Claude Code schema.** Transcripts are one JSON object per line with no
   `payload` wrapper, and usage on the assistant message with the cache
   counted separately from `input_tokens`. Schema is now detected per file.
2. **`requestId` deduplication.** One request whose reply mixes text and tool
   calls is written as several lines, each repeating that request's whole
   usage. Summing per line inflated the first transcript measured by 40%
   (66.1M vs 39.8M).
3. **The meter counted its own authorship as supervision.** A tool call's
   arguments are one blob: a commit message, a PR body, or a heredoc'd
   analysis script sits in the same field as a command. `git commit -m
   'polling (orchestration check)'` classified as a poll. 22 of 48 classified
   polls were mentions, not calls. Patterns now require the `orca` CLI name.

The third fix moves a published number. The handoff recorded `019f9dfd` at
6.9 polls per task; with mentions removed from the *denominator* it is
**12.7** (216 polls / 17 tasks, not 222 / 32). The breach was worse than
reported, because prose about dispatching was being counted as dispatching.

Also removed from the dispatch sets: Claude Code's `TaskCreate`/`TaskUpdate`/
`TaskList`, which are a to-do list the session keeps for itself, not work
handed to anyone. Counting a to-do as a dispatched task lets a session that
writes ten to-dos and polls twenty times pass a budget it doubly breached.

## The numbers

**223.7M tokens** of Claude Code spend produced a repo of **10,877 lines**
(12,747 inserted across its whole history, 486 deleted). Codex added 122.1M on
2026-07-26 alone.

| | share |
| --- | ---: |
| cache read — context re-sent | **96.9%** |
| cache write | 2.5% |
| output — text actually produced | **0.47%** |

Per session, largest first:

| tokens | round-trips | per trip | session |
| ---: | ---: | ---: | --- |
| 116.5M | 333 | **350k** | `03bbf8a4` (2026-07-25) |
| 39.8M | 218 | 182k | `9236e1a6` (2026-07-26) |
| 16.7M | 134 | 124k | `817fcfe2` (2026-07-27, the handoff) |
| 5.8M | 52 | 111k | `016ea712` |
| 3.4M | 49 | 70k | `0db6105a` |

## Finding 1 — the cost is context size, not what the turn did

97% of spend is context re-sent. A turn is charged for the context it carries
regardless of whether it polls, edits, or thinks. `03bbf8a4` paid **5x per
turn** what `0db6105a` paid (350k vs 70k) for turns that are not 5x more
useful.

This reframes the supervision rule. "≤ 2 polls per task" reduces the *number*
of turns; it does nothing about the *rate*. A coordinator at 350k context that
obeys the poll budget perfectly still outspends a sloppy one at 70k. The CAG
read protocol — bounded reads, ≤ 40-line indexes, never bulk-read `docs/` — is
the control for the rate, and until now nothing measured whether it was
working.

`burn.py` now prints `k per trip` on every session line. It is not enforced:
there is no defensible threshold yet, and inventing one would repeat the
mistake open problem 1 in the handoff describes. Watch it for a few sessions
first.

## Finding 2 — polling is a Codex problem, not a Claude Code problem

| | Codex 07-26 | Claude Code, all |
| --- | ---: | ---: |
| POLL share of calls | 47% of tokens | **3.4%** |
| worst polls/task | 30.0 | 1.0 |
| coordinator pooled | 9.8 | 0.3 |

Claude Code sessions here are not coordinators — they do the work themselves
(1,225 WORK calls against 73 DISPATCH). The supervision budget is real and
Codex breaches it badly, but applying it to Claude Code as the primary
efficiency lever would be measuring the wrong substrate. On Claude Code the
levers are context size (finding 1) and rework (finding 3).

## Finding 3 — review rounds are the quality signal, and they are expensive

17 review subagents, **6.6M tokens**, on three PRs:

| rounds | PR |
| ---: | --- |
| 6 standards + 6 spec | the burn-meter PR |
| 2 + 2 | PR #11 |
| 1 + 1 | PR #12 |

Six rounds means the first draft was not close, and each round found real
defects — the handoff records that both merged PRs were materially changed
before merge. The cost is not the review; it is the redraft. Edits per file
tell the same story:

| edits | file |
| ---: | --- |
| 47 | `template/.orchestration/burn.py` |
| 29 | `tests/burn.sh` |
| 17 | `template/.orchestration/verify.sh` |
| 15 | `template/AGENTS.md` |

`burn.py` is 330 lines and was edited 47 times across 14 commits. Two of the
three defects fixed at the top of this report were in code that had already
passed six rounds of review — reviewers checked the logic against the rules
and never checked the classifier against a real log. **Nothing in this repo's
gates requires a change to be run against real data before it is reviewed.**
The acceptance check is `run: ./tests/burn.sh`, and the tests use synthetic
fixtures the author also wrote.

Tool error rate is 2.1% (33 of 1,592). Mechanical failure is not the problem.
Rework is.

## Finding 4 — the repo broke its own writer lease while writing about supervision

This resolves the README anomaly the handoff flagged as unknown provenance.

| time (UTC) | session | action |
| --- | --- | --- |
| 05:11:44 | `9a270b9e` | `Write README.md` — the 131-line rewrite |
| 05:12:27 | `9a270b9e` | `Write ADOPT.md` |
| 05:17:39 | `817fcfe2` | spawns two review agents |
| 05:39:25 | `9a270b9e` | `rm ADOPT.md` |
| 05:39:32–54 | `9a270b9e` | three `Edit README.md` — folds ADOPT into README |
| 05:40:17 | `817fcfe2` | writes the supervision handoff prompt |

Two sessions held the same worktree for 29 minutes. `lease.sh` exists to make
this impossible and neither session acquired one. The handoff's author could
not identify the README's provenance because a concurrent writer produced it.
Nothing corrupted this time — they touched disjoint files by luck.

The uncommitted README rewrite is legitimate work by `9a270b9e`, not an
artifact. ADOPT.md was written and deleted 28 minutes later, its content
folded into the README's "Three ways in" section. Nothing is lost.

Also: no issue, no prompt file, no report exists for that README work. The
contract's first non-negotiable is "no work without an issue, including
meta/process work," and the repo's own README was rewritten outside it.

## Finding 5 — the Codex fix, with its arithmetic

Codex is where orchestration runs, so it is where the recoverable money is.
2026-07-26: **122.1M tokens, 43.1% of it polling** (52.6M across 404 calls).

A poll costs what a turn costs, because it re-sends the whole context to
return a few KB. The unit price is stable across both coordinators:

| session | POLL tokens | polls | per poll |
| --- | ---: | ---: | ---: |
| `019f9dfd` | 31.1M (71.3% of session) | 216 | **144k** |
| `019f9ff3` | 17.4M (55.3% of session) | 120 | **145k** |

Two coordinators, two different reasons, one price:

- `019f9dfd` used the right primitive at the wrong window. 60 of 68 declared
  windows under 15 minutes, shortest 10s, median gap between wake-ups 73s. Its
  216 polls cover roughly 4.4 hours of waiting. At a 15-minute window the same
  wait is ~18 calls. **Saves ~198 × 144k ≈ 28.5M.**
- `019f9ff3` made zero `orca orchestration` calls. It hand-rolled
  `for n in 1..12; do test -f report; done` — it did not know the primitive
  existed. Same wait at a 15-minute window is ~8 calls.
  **Saves ~110 × 145k ≈ 16M.**

**≈ 44.5M of 122.1M — 36% of a day's Codex spend.** The estimate holds total
waiting time constant and only changes how often the coordinator wakes inside
it; it does not assume the workers get faster.

Both rules were already written in `supervision.md` before either session ran.
They failed for the same structural reason: **the file states the floor and
then refuses to name the command** — *"Take exact flags from the substrate's
own guide, never from this file."* The substrate's guide optimizes for an
example that returns quickly, so the only copyable literal in reach was 60s.
`019f9dfd` inherited it from its own prompt, two lines below prose saying the
tasks run 15–60 minutes. The literal beat the prose. `019f9ff3` had no
copyable literal at all and invented a shell loop.

A rule stated where it cannot be copied does not survive contact with a
coordinator. Fixed in this change:

- `prompts/TEMPLATE.md` gains a Supervision section carrying the invocation
  **written at the floor**, plus `<SUPERVISION_WINDOW>` and
  `<REDISPATCH_CAP>` as placeholders — and `verify.sh` already rejects a
  report whose prompt has unresolved placeholders, so the window cannot be
  left unset.
- `supervision.md`'s deferral clause now says to check every window literal in
  the substrate guide against the floor before copying it.
- `verify.sh` fails any shipped file under `template/` writing a
  `--timeout-ms` below 900000. Scoped to the payload: this repo's own
  `prompts/` and `reports/` are immutable history, and the handoff that
  diagnosed this quotes the 60s literal as evidence.

### Correction — the window was never the binding constraint

The section above was written against `--timeout-ms`, and the logs say that
flag decided nothing. Every one of `019f9dfd`'s 36 `orca orchestration check
--wait --timeout-ms 60000` calls returned at **exactly 30.00 seconds**
carrying `Process running`: `orca` was still blocking and the shell harness
had yielded out from under it at `yield_time_ms: 30000`.

So "raise the window to 15 minutes, save 28.5M" was wrong in mechanism.
Raising the window alone changes nothing, and raising it while the yield stays
at 30s makes it **worse** — a 15-minute window then costs 30 keepalive
round-trips instead of 2. The first version of the `TEMPLATE.md` example in
this change would have caused exactly that; it now states both numbers and
says the smaller one is the rule.

What a supervision cycle actually is: one `exec_command` wait (yields at 30s),
~2 empty `write_stdin` keepalives to finish the park, ~1.4 per-worker `orca
terminal read`.

| | `019f9dfd` | `019f9ff3` |
| --- | ---: | ---: |
| session span | 1.6h | 2.8h |
| **wall clock held open inside tool calls** | **0.9h (56%)** | **2.4h (86%)** |
| orca `--wait` calls | 36 | **0** |
| keepalive `write_stdin` | 73 | 66 |
| per-worker `terminal read` | 51 | 32 |
| tokens per second waited | ~9,600 | ~2,000 |

**Wall clock is not the cost. Wall clock held open inside a tool call is.**
Waiting longer is free; waking is what bills. The three levers, corrected and
ordered by size:

1. **The yield, not the window.** Largest yield anywhere in the corpus:
   300,000 ms, used 21 times, against 1,469 calls at 30,000. Both numbers must
   move together.
2. **Drop the per-worker `terminal read`.** 83 calls across the two sessions
   for information the completion event already carries. Already forbidden by
   "wait wide". No substrate constraint, no rule change, no tradeoff — the
   cleanest win available.
3. **Wait off the model loop.** `019f9ff3` held 2.4h of its 2.8h open inside
   tool calls, all of it billable context re-sends. A coordinator that ends
   its turn and is re-invoked on the completion event pays nothing for the
   waiting and one round-trip for the wake.

`burn.py` now reads the **effective** window — the smallest of
`--timeout-ms`, `"timeout_ms"`, and `"yield_time_ms"` — but only on a call
that *parks* (a `--wait`, a blocking-wait tool, or the empty `write_stdin`
that keeps one alive). On a `terminal read` the yield still means what the
earlier rejection said it means and is still not a window. This closes handoff
open problem 3, whose reasoning was right and whose conclusion was wrong.

Visibility gained: 92 → 239 declared windows across the corpus, 209 of them
under the floor. `019f9ff3` — the session that made zero `orca orchestration`
calls and was therefore invisible to the window rule entirely — now shows 45
of 66 windows under 5 minutes, shortest 1s.

The enforced floor is **5 minutes, not 15**: the effective window is capped by
the harness yield, and 300s is the longest yield the substrate was observed to
honour. A 15-minute floor here would fail every session unconditionally and
stop being a signal. 15 minutes remains the rule for the off-loop path, where
nothing caps it.

### Tested: the off-loop primitive does not work here

The largest projected saving assumed Orca's runtime coordinator loop worked.
It was tried directly on 2026-07-27 and it does not.

| | result |
| --- | --- |
| `orca orchestration run` returns immediately | yes — 0.31s, `run_b3ecf0b7c5d2` |
| run registers and stops cleanly | yes — `run-stop` → `stopped: true` |
| tasks created | **0**, over 5 minutes at a 30s poll interval |
| messages sent | **0** — latest inbox entry was from the previous day |
| worker dispatched | **no** — a healthy idle codex sat at its prompt |

Retried with an explicit `--from <coordinator handle>`, since this project runs
outside Orca and has no `ORCA_TERMINAL_HANDLE`. Same result: zero tasks over
five polls at a 15s interval.

So the number "most of the 52.6M POLL" is **unsupported**, and the two
remaining levers — per-worker reads and the harness yield — are the only ones
with evidence behind them.

This may also explain the corpus. `orchestration run` was invoked twice ever,
both times as `--help`. The reading that a coordinator "read what it did and
hand-rolled the loop anyway" assumed the primitive worked. It is at least as
likely that whoever read the help tried it, got the same silence, and went
back to what dispatches.

The rule text was corrected before merge: prefer a runtime loop, **but prove it
dispatches** — require a task reaching `completed` through it before adopting
it. A runtime loop that does nothing is worse than a poll loop that works.

### The second-order lever: a late poll costs twice an early one

`019f9dfd`, cost per round-trip by quartile of session life:

| Q1 | Q2 | Q3 | Q4 |
| ---: | ---: | ---: | ---: |
| 94k | 155k | 109k | 192k |

Not monotonic — Codex compacts, and the rate resets — but Q4 costs **2x** Q1.
`supervision.md` already forbids source reads, greps, builds and test runs in
the coordinator session, and already requires a hand-off at the first
compaction. Neither is enforced by anything. This multiplies with the fix
above rather than adding to it: the ~18 surviving polls are worth 94k each
instead of 192k.

### Not worth spending on

Ranked by measured size, these are noise: Claude Code polling (3.4%), tool
errors (2.1%), and handoff open problems 3 and 4 (subagent window visibility
and token attribution) — both still theoretical, both with a rejected obvious
fix already on record.

## What to change, cheapest first

Done in this change (finding 5): compliant window literal in
`prompts/TEMPLATE.md`, the deferral clause in `supervision.md`, and the
`verify.sh` floor gate. Worth ~36% of a day's Codex spend.

Still open, cheapest first:

1. **Enforce coordinator context discipline.** Worth 2x on every poll that
   survives the window fix, and the rule is already written. A coordinator
   that greps source is measurable — `burn.py` already separates WORK from
   POLL per session. The gap is that nothing fails.
2. **Take the lease.** The lease exists and is not used by the sessions
   working on this repo. Either sessions acquire it or the rule is fiction.
   One line in `AGENTS.md`'s working method, or a `SessionStart` hook.
3. **Require one real-data run before review.** The prompt template's
   acceptance check should distinguish "tests pass" from "ran against real
   input." Six review rounds did not catch a classifier that never saw a log.
4. **Watch `k per trip`.** It is now printed. Collect a few sessions before
   proposing a threshold.
5. **Record review rounds in the report template.** Round count per PR is the
   cheapest available proxy for first-draft quality, and it is currently only
   recoverable by reading subagent metadata.
6. Open problems 1, 3 and 4 from
   `.orchestration/prompts/CLAUDE-OPUS-supervision-observability-handoff.md`
   remain open and unchanged. Problem 2 (Claude Code schema) and problem 5
   (sub-floor literals in shipped prompts) are closed by this change.
   Problem 1 — the ≥15-minute window and the ≤2-calls-per-task ratio are
   jointly unsatisfiable for one 60-minute task — dissolves on the off-loop
   path rather than needing the docs decision it was filed as. The
   contradiction only exists because a blocking wait *times out*: a
   60-minute task at a 15-minute window wakes three times for nothing, and
   those three wake-ups breach the ratio. A coordinator re-invoked on the
   completion event does not time out. One wake, one supervision call, both
   rules satisfied, and no number in either rule has to change. That is the
   strongest argument for the off-loop path and it was not visible until the
   window was measured as an effective window.

## Cross-model review (REVIEWER slot: Codex, gpt-5.6-sol)

Requested changes, seven findings. Five fixed, two refused with reasons.

**The one that mattered.** `parks()` keyed on the `--wait` flag, so `orca
terminal wait --for tui-idle --timeout-ms 60000` — which blocks, and says so
in the subcommand rather than a flag — declared no window and passed. Not an
edge case: **177 occurrences of that one recipe** in the corpus, and the
handoff records that the worst coordinator kept using `terminal wait` after
it had corrected its `check --wait` window. The gap swallowed the largest
real evasion available. Fixed, with a test.

Coverage after: **239 → 288** declared windows, 209 → 258 under floor,
`019f9dfd` 118 → **148**.

Also fixed:

- `verify.sh`: `|| true` collapsed grep's "no matches" (exit 1) with a real
  error (exit 2+), so an unreadable directory would have reported a clean
  gate — a pass produced by reading nothing.
- `verify.sh`: `[= ]+` missed a tab between flag and value, which is valid
  shell. Now `[=[:space:]]+`.
- `scan_claude()`: dedupe now keys on `requestId or message.id or uuid`.
  `message.id` is what split lines actually share, present on 3,249 of 3,249
  assistant lines; `requestId` is missing on 13.
- `scan_claude()`: a first assistant line without a timestamp set
  `started=""`, which compares below every `--since` and silently discarded
  the whole transcript. A malformed first line did the same at the `scan()`
  level; it now routes to the reader that skips bad lines.

Refused, both recorded in the code:

- **Shell indirection** (`cli=orca; "$cli" orchestration dispatch`) evades the
  CLI-name anchor and deflates the denominator. Real mechanism, but it
  appears **zero** times in the corpus, while dropping the anchor
  reintroduces 22 false polls out of 48. Measured harm beats hypothetical
  harm.
- **A request whose usage lands only on a later split line** reports zero.
  Every assistant line in the corpus carries usage, and charging the first
  line is what keeps tokens attributed to the call that drove them. A proper
  fix needs the driver remembered per key — more state than an unobserved
  case earns.

Worth noting against finding 3 of this report: an independent model found a
177-occurrence evasion that six rounds of review on the original meter did
not. The difference is that this review was pointed at the dangerous
*direction* — false negatives that deflate the budget's denominator — rather
than asked to look at the diff.

## Dogfooding

This audit session (`7b2dc990`) spent 3.0M tokens over 36 round-trips at
**84k per trip** — the lowest per-trip rate of any session over 2M in the
corpus, and a fifth of the rate of the session it was auditing. It read no
source files it did not need and spawned no subagents. That is the finding in
section 1 applied to itself, and it is the only reason the number is small.
