#!/usr/bin/env python3
"""Supervision-cost meter: what a coordinator spent watching vs doing.

Reads Codex rollout logs (~/.codex/sessions/**/*.jsonl) and Claude Code
transcripts (~/.claude/projects/**/*.jsonl), and attributes every API
round-trip to the tool call that drove it -- a round-trip with no preceding
call lands in <none>. Enforces two rules from
docs/orchestration/supervision.md: at most 2 supervision calls per dispatched
task, and no supervision wait shorter than the floor. The token shares it also
prints are context, not the budget.

The second rule is not implied by the first. A coordinator can call the right
blocking primitive and still poll with it: a one-minute wait against a worker
that runs 15-60 minutes wakes the coordinator ~30 times and re-sends its whole
context each time. Counted per call the two are indistinguishable, so the
window is read separately -- and read as the *effective* window, the smallest
of every bound the call declares, since the coordinator wakes when the first
one expires. See the comment on `wait_window`: a measured coordinator asked
for 60s and got 30s, because the harness yield outranked the flag.

Wall-clock time is not the cost. Wall-clock time held open inside a tool call
is: every wake re-sends the whole context. A coordinator that waits an hour in
one call is cheaper than one that waits a minute sixty times, and a
coordinator that waits off the model loop entirely -- ending its turn and
being re-invoked on the completion event -- pays nothing at all for the
waiting.

    python3 .orchestration/burn.py                # last 7 days
    python3 .orchestration/burn.py --since 2026-07-22 --sessions

Scope limits, so the numbers are not read for more than they are:
  - Two schemas, detected per file: Codex rollout logs and Claude Code
    transcripts. A coordinator on any other CLI is invisible here; point --root
    at that CLI's logs only if they share one of these schemas.
  - EDIT counts the tool that edits (`apply_patch`, `Edit`/`Write`). A patch
    applied through a shell command lands in WORK, so EDIT is a floor on real
    editing, not a measurement of it.
  - A Codex subagent thread forks its parent, so its log opens with the
    parent's history replayed. `--sessions` labels those threads with their
    agent path, which is a label and nothing more: their tokens are real spend
    and stay in every total, and a fork that dispatches is still judged as a
    coordinator. Claude Code subagents write their own transcript under
    `<session>/subagents/` with no replay, so their tokens are already
    separate; they are labelled from the sibling `.meta.json`.
"""
import argparse, collections, datetime, glob, json, os, re, sys

# These match raw command text, so all three ends need anchoring. A bare
# `spawn` counts `grep -rn spawn docs/` as dispatched work; a trailing \b
# counts the read-only `dispatch-show` as a dispatch, because \b matches
# before a hyphen. Either one inflates the denominator the budget divides by
# and turns a violation into a pass, so subcommands are listed exactly and
# (?![\w-]) stops a prefix from matching its own longer siblings.
#
# The leading `orca` is the third anchor, and it is the load-bearing one for
# any session that works *on* orchestration rather than *doing* it. A tool
# call's arguments are one blob: a commit message, a PR body, a heredoc'd
# analysis script, or a grep pattern all sit in the same field as the command.
# Without the CLI name, `git commit -m "...polling (orchestration check)..."`
# is a supervision call. Measured on the sessions that built this meter, that
# was 22 of 48 classified polls -- the meter reported its own authorship as
# supervision. Every real supervision call names the CLI, so requiring it
# costs nothing.
#
# ponytail: text-level, so prose that quotes a whole command ("run `orca
# terminal read ...`") still counts. Nothing in the log distinguishes a command
# from a quotation of one; closing that needs a field the log does not carry.
#
# The same literal requirement misses shell indirection -- `cli=orca; "$cli"
# orchestration dispatch ...` scores as WORK, which deflates the denominator
# and can turn a breach into a pass. Left as-is deliberately: indirection
# appears zero times in the measured corpus, while dropping the anchor
# reintroduces 22 false polls out of 48. Measured harm beats hypothetical
# harm. Revisit if a coordinator ever invokes the CLI through a variable.
def _subcommands(group, *names):
    return rf"\borca\s+{group}\s+(?:{'|'.join(names)})(?![\w-])"


# Subcommand lists come from `orca orchestration --help` and `orca terminal
# --help`, not from grepping logs: a log can contain a command that never
# existed. `orca status` is deliberately absent -- it reports whether the app is
# up, which is a preflight check, not a question about a worker.
POLL = re.compile("|".join((
    _subcommands("orchestration", "check", "inbox", "task-list", "dispatch-show", "gate-list"),
    _subcommands("terminal", "list", "show", "read", "wait"),
)), re.I)
# Moving work forward. `ask` is the worker blocking on an answer from the
# coordinator, not the coordinator checking on the worker.
DISPATCH = re.compile("|".join((
    _subcommands("orchestration", "send", "reply", "task-create", "task-update", "dispatch",
                 "ask", "run", "run-stop", "gate-create", "gate-resolve", "reset"),
    _subcommands("terminal", "send", "stop", "create", "switch", "close", "rename", "split"),
)), re.I)
# A dispatch that starts work, as opposed to replying to or messaging a worker
# already running. This is the denominator of the supervision budget.
TASK_START = re.compile("|".join((
    _subcommands("orchestration", "dispatch", "task-create"),
    _subcommands("terminal", "create"),
)), re.I)
# Tool names from both CLIs in one set each: the two vocabularies do not
# collide, and the command-text patterns above are substrate-independent -- a
# coordinator shells out to the same `orca` either way. Claude Code's
# BashOutput/TaskOutput/Monitor are the same act as a `wait`: asking a worker
# that is already running whether it is done yet.
POLL_TOOLS = {"wait", "wait_agent",
              "BashOutput", "TaskOutput", "Monitor"}
DISPATCH_TOOLS = {"send_message", "spawn_agent", "followup_task",
                  "Agent", "SendMessage", "TaskStop"}
# Claude Code's TaskCreate/TaskUpdate/TaskGet/TaskList are a to-do list the
# session keeps for itself, not work handed to anyone, so they are in no set
# here. Counting a to-do item as a dispatched task is the same denominator
# inflation the comment above rejects, and a bigger one: a session that writes
# ten to-dos and polls twenty times passes a budget it doubly breached.
TASK_START_TOOLS = {"spawn_agent", "Agent"}
EDIT_TOOLS = {"apply_patch", "Edit", "Write", "NotebookEdit"}

DISPATCH_ID = re.compile(
    r"(?:--(?:dispatch-id|dispatch|task|id)(?:=|\s+)([A-Za-z0-9_.:/-]+))",
    re.I,
)
EVENT_DELIVERY = re.compile(
    r"(?:worker_done|escalation|decision[_ -]?gate|terminal[_ -]?exit|user[_ -]?cancel|"
    r"(?:^|[\s{,])count\s*[:=]\s*[1-9])",
    re.I,
)
EMPTY_RESUMPTION = re.compile(r"(?:count\s*[:=]\s*0|no events?|empty inbox|nothing unread)", re.I)
HARNESS_YIELD = re.compile(
    r"(?:process|command|script)\s+(?:is\s+)?still\s+running|still running|"
    r"script running",
    re.I,
)
ORCA_TIMEOUT = re.compile(r"(?:orca.*timeout|timed out|\btimeout\b|count\s*[:=]\s*0)", re.I)


def decoded_args(args):
    """Decode a tool argument blob without making the scanner fragile."""
    try:
        value = json.loads(args)
    except (TypeError, ValueError):
        return {}
    return value if isinstance(value, dict) else {}


def command_text(name, args):
    value = decoded_args(args)
    for key in ("cmd", "command", "input", "script"):
        candidate = value.get(key)
        if isinstance(candidate, str):
            return candidate
    return args


def dispatch_identity(name, args, ordinal):
    """Return a stable dispatch identity, or a call-local fallback.

    A task ID is the identity when the CLI exposes one.  A dispatch without an
    ID is still counted once, but its call ordinal prevents a retry from being
    mistaken for the same operation.  The denominator is resolved later after
    tool results tell us which attempts actually succeeded.
    """
    if name in EDIT_TOOLS:
        return None
    value = decoded_args(args)
    for key in ("dispatch_id", "dispatchId", "task_id", "taskId"):
        if value.get(key):
            return str(value[key])
    match = DISPATCH_ID.search(command_text(name, args))
    return match.group(1) if match else f"call-{ordinal}"


def result_text(payload):
    """Extract tool-result text from the several rollout result shapes."""
    if not isinstance(payload, dict):
        return ""
    values = []
    for key in ("output", "result", "content", "message", "error"):
        value = payload.get(key)
        if isinstance(value, str):
            values.append(value)
        elif isinstance(value, (dict, list)):
            values.append(json.dumps(value, sort_keys=True))
    return " ".join(values)


def result_success(payload, text):
    """Resolve explicit failures; absence of a result remains legacy-success.

    Older rollout exports contain calls and token counts but omit tool output.
    Treating those calls as successful preserves historical measurement.  Newer
    exports with an exit/status/error field are fail-closed.
    """
    if not isinstance(payload, dict):
        return True
    if payload.get("is_error") is True or payload.get("error"):
        return False
    if isinstance(payload.get("exit_code"), int):
        return payload["exit_code"] == 0
    status = str(payload.get("status", "")).lower()
    if status in {"error", "failed", "failure", "timeout", "timed_out"}:
        return False
    if re.search(r"(?:^|\b)(?:exit(?:ed)?|status)\s*[:=]\s*[1-9]\d*\b", text, re.I):
        return False
    return not bool(re.search(r"\bdispatch\s+(?:failed|error)\b", text, re.I))


def wake_kind(text):
    """Classify a returned wait without confusing harness yields and Orca."""
    if not text:
        return ""
    if HARNESS_YIELD.search(text):
        return "harness_yield"
    if EVENT_DELIVERY.search(text):
        return "event_delivery"
    if EMPTY_RESUMPTION.search(text):
        return "empty_resumption"
    if ORCA_TIMEOUT.search(text):
        return "orca_timeout"
    return ""

# A supervision call declares its window in up to three places, and the
# *smallest* one is what actually decides how often the coordinator wakes.
#
# An earlier version read only orca's `--timeout-ms` and deliberately ignored
# the tool-level `yield_time_ms`, on the grounds that the yield is the same
# field, with the same meaning, that every ordinary shell call carries: how
# long the call parks before returning output so far. That reasoning is right
# and the conclusion was wrong. Measured on a real coordinator: 36 calls of
# `orca orchestration check --wait --timeout-ms 60000` issued through
# `exec_command` with `yield_time_ms: 30000` returned at 30.00s every time,
# carrying "Process running" -- orca was still blocking, and the harness had
# yielded out from under it. The declared window never bound anything. The
# yield was the poll interval.
#
# So the yield is read, but only on a call that *parks*: a `--wait`, a
# blocking-wait tool, or the empty `write_stdin` that keeps such a call alive.
# On a `terminal read` or a `task-list` the yield still means what the rejected
# reading said it means -- a cap on waiting for output that already exists --
# and is still not a window.
TIMEOUT_FLAG = re.compile(r"--timeout-ms[=\s]+(\d+)")
# `wait_agent` and Claude Code's `Monitor` declare theirs as a JSON key rather
# than a CLI flag.
TIMEOUT_JSON = re.compile(r'"timeout_ms"\s*:\s*(\d+)')
YIELD_JSON = re.compile(r'"yield_time_ms"\s*:\s*(\d+)')
WAIT_FLAG = re.compile(r"--wait(?![\w-])")
# `terminal wait` parks by definition and says so in the subcommand rather than
# in a flag, so a --wait-only test misses it. It is not a rare shape: it is the
# most common blocking call in the measured corpus (177 occurrences of one
# 60-second recipe), and the handoff records that the worst coordinator kept
# using it after it had corrected its `check --wait` window. Keying parking on
# the flag alone let the single largest real evasion through.
PARK = re.compile(_subcommands("terminal", "wait"), re.I)


def parks(name, args):
    """Does this supervision call block, or does it return what already exists?"""
    return (name in POLL_TOOLS or name == "write_stdin"
            or bool(WAIT_FLAG.search(args)) or bool(PARK.search(args)))


def wait_window(name, args):
    """-> the effective ms a parking supervision call sleeps for, or None.

    The minimum across every declared bound, because the coordinator wakes as
    soon as the first of them expires."""
    if not parks(name, args):
        return None
    declared = [int(m.group(1)) for pattern in (TIMEOUT_FLAG, TIMEOUT_JSON, YIELD_JSON)
                for m in pattern.finditer(args)]
    return min(declared) if declared else None


def classify(name, args):
    """Bucket a call. The tool name is authoritative; only fall back to reading
    the arguments when the name alone does not say what the call is."""
    if name in EDIT_TOOLS:
        return "EDIT"
    if name == "write_stdin":
        # A write with nothing in it is a nudge to see what a worker is doing;
        # a write that carries input is sending it work. Control characters
        # (^C and friends) are input, not a question.
        try:
            chars = json.loads(args).get("chars", "")
        except (ValueError, AttributeError):
            chars = args
        return "POLL" if not chars.strip() else "DISPATCH"
    if name in POLL_TOOLS:
        return "POLL"
    if name in DISPATCH_TOOLS:
        return "DISPATCH"
    if POLL.search(args):
        return "POLL"
    return "DISPATCH" if DISPATCH.search(args) else "WORK"


def starts_task(name, args):
    if name in EDIT_TOOLS:  # edited text is content, never a dispatch
        return False
    return name in TASK_START_TOOLS or bool(TASK_START.search(args))


def ratio_text(per_task):
    return "n/a" if per_task == float("inf") else f"{per_task:.1f}"


def agent_path(meta):
    """The forked thread's agent path, or None for a session a user started.

    Read `thread_source`, which says what the thread is, rather than the shape
    of `source`, which only correlates: a top-level session records the string
    `"cli"`/`"exec"`/`"vscode"` there today, but an object-shaped `source` is
    not by itself proof of a fork, and treating it as proof labels whatever
    object shape a later CLI version introduces as a subagent. A spawned thread
    that carries no `thread_spawn` -- a guardian is one -- is still a subagent,
    so it keeps the label and loses only the path."""
    if meta.get("thread_source") != "subagent":
        return None
    source = meta.get("source") if isinstance(meta.get("source"), dict) else {}
    spawn = (source.get("subagent") or {}).get("thread_spawn") or {}
    return spawn.get("agent_path") or "unnamed"


def claude_agent(path):
    """The agent type of a Claude Code subagent transcript, or None.

    Subagents live at `<session>/subagents/agent-<id>.jsonl` with a sibling
    `.meta.json`. A missing or unreadable meta still means a subagent -- the
    directory says so -- so it keeps the label and loses only the type."""
    if os.path.basename(os.path.dirname(path)) != "subagents":
        return None
    try:
        with open(path[: -len(".jsonl")] + ".meta.json", encoding="utf-8") as fh:
            return json.load(fh).get("agentType") or "unnamed"
    except (OSError, ValueError, AttributeError):
        return "unnamed"


def scan_claude(path, lines, since):
    """Claude Code transcript -> the same tuple `scan` returns.

    Tokens are read off the assistant message and deduplicated by requestId:
    one request is written as several lines when its reply mixes text and tool
    calls, each line repeating the whole request's usage. Summing per line
    inflates a session by roughly the share of its replies that used a tool --
    40% on the transcript this was written against.

    Unlike Codex, input_tokens here excludes the cache, so a cache read is
    counted explicitly. It is most of a poll's cost and the whole reason
    polling is expensive: the wait returns, nothing has finished, and the
    entire context is re-sent to wait again."""
    buckets = collections.defaultdict(lambda: [0, 0])
    started, round_trips = "", 0
    driver, windows, seen = "<none>", [], set()
    calls, results, wake_kinds = [], {}, collections.Counter()
    call_commands = {}
    call_ordinal = 0
    for line in lines:
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        if ev.get("type") != "assistant":
            continue
        if not started:
            # Only a line that carries one can date the session. Treating a
            # missing timestamp as the empty string would compare below every
            # --since and silently discard the whole transcript.
            started = (ev.get("timestamp") or "")[:10]
            if started and started < since:
                return None
        message = ev.get("message") if isinstance(ev.get("message"), dict) else {}
        usage = message.get("usage") or {}
        # `message.id` is the identity that split lines actually share; it is
        # present on every assistant line in the measured corpus, while
        # requestId is missing on some. Keying on the line's own uuid alone
        # would give each half of a split reply a different key and count its
        # usage twice, which is the inflation this dedupe exists to remove.
        key = ev.get("requestId") or message.get("id") or ev.get("uuid")
        # ponytail: the first line of a request is charged even if it carries
        # no usage, so a split reply whose usage lands only on a later line
        # reports zero for that request. Every assistant line in the measured
        # corpus carries usage, and charging the first line is what keeps a
        # request's tokens attributed to the call that drove it. Fixing it
        # properly needs the driver remembered per key, which is more state
        # than an unobserved case earns.
        if key not in seen:
            seen.add(key)
            buckets[driver][0] += sum(usage.get(k, 0) for k in (
                "input_tokens", "output_tokens",
                "cache_read_input_tokens", "cache_creation_input_tokens"))
            round_trips += 1
            driver = "<none>"
        for block in message.get("content") or []:
            if not isinstance(block, dict) or block.get("type") != "tool_use":
                continue
            name = block.get("name") or ""
            raw = json.dumps(block.get("input") or {})
            driver = classify(name, raw)
            call_id = block.get("id") or f"call-{call_ordinal + 1}"
            call_commands[call_id] = command_text(name, raw)
            buckets[driver][1] += 1
            if starts_task(name, raw):
                call_ordinal += 1
                calls.append({"id": call_id,
                              "dispatch_id": dispatch_identity(name, raw, call_ordinal),
                              "success": None})
            if driver == "POLL":
                window = wait_window(name, raw)
                if window is not None:
                    windows.append(window)
        # Claude's tool_result block is often on a later assistant line. Keep
        # it available by the tool-use id when the export carries that id.
        for block in message.get("content") or []:
            if isinstance(block, dict) and block.get("type") == "tool_result":
                results[block.get("tool_use_id")] = block
    # A transcript no line could date cannot be placed in or out of --since, so
    # it is dropped rather than counted into a range it may not belong to.
    for call in calls:
        result = results.get(call["id"])
        if result is not None:
            text = result_text(result)
            call["success"] = result_success(result, text)
            kind = wake_kind(text)
            if kind:
                wake_kinds[kind] += 1
    for call_id, payload in results.items():
        if ("orca terminal read" in call_commands.get(call_id, "").lower()
                and wake_kinds.get("orca_timeout", 0)):
            wake_kinds["justified_recovery"] += 1
    successful = {call["dispatch_id"] for call in calls
                  if call["success"] is not False and call["dispatch_id"]}
    failed = sum(call["success"] is False for call in calls)
    dispatch_stats = {"attempts": len(calls), "successful": len(successful),
                      "failed": failed, "ids": sorted(successful)}
    return ((started, buckets, len(successful), round_trips, claude_agent(path), windows,
             dispatch_stats, dict(wake_kinds)) if buckets and started else None)


def scan(path, since):
    """-> (started, {bucket: [tokens, calls]}, tasks, round_trips, agent, windows)
    or None, where windows are the wait windows in ms that supervision calls
    declared. The schema is detected per file: only Codex wraps every line in a
    `payload`."""
    try:
        lines = open(path, encoding="utf-8", errors="replace").readlines()
    except OSError:
        return None
    try:
        head = json.loads(lines[0])
    except (ValueError, IndexError):
        head = None
    # Only Codex wraps every line in a `payload`, and only Codex needs its
    # first line -- the session_meta. A first line that will not parse is
    # therefore routed to the Claude reader, which skips bad lines and reads
    # the rest, rather than discarding a whole transcript over one of them.
    if not (isinstance(head, dict) and "payload" in head):
        return scan_claude(path, lines, since)
    meta = head.get("payload") or {}
    started = meta.get("timestamp", "")[:10]
    if started < since:
        return None
    agent = agent_path(meta)
    buckets = collections.defaultdict(lambda: [0, 0])  # bucket -> [tokens, calls]
    tasks = round_trips = 0
    driver = "<none>"
    windows = []
    calls, results, wake_kinds = [], {}, collections.Counter()
    call_commands = {}
    call_ordinal = 0
    for line in lines:
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        payload = ev.get("payload") if isinstance(ev.get("payload"), dict) else {}
        kind = payload.get("type")
        if ev.get("type") == "response_item" and kind in ("custom_tool_call", "function_call"):
            name = payload.get("name") or ""
            raw = payload.get("arguments") or payload.get("input") or ""
            raw = raw if isinstance(raw, str) else json.dumps(raw)
            driver = classify(name, raw)
            # Calls are counted as they happen. Counting them per round-trip
            # instead would score a batch of eight waits as one supervision
            # call while the budget counts dispatches one by one.
            buckets[driver][1] += 1
            call_id = payload.get("call_id") or payload.get("id") or f"call-{call_ordinal + 1}"
            call_commands[call_id] = command_text(name, raw)
            if starts_task(name, raw):
                call_ordinal += 1
                calls.append({"id": call_id,
                              "dispatch_id": dispatch_identity(name, raw, call_ordinal),
                              "success": None})
            # Only a supervision call declares a supervision window. The same
            # flag on a dispatch bounds how long that dispatch may take.
            if driver == "POLL":
                window = wait_window(name, raw)
                if window is not None:
                    windows.append(window)
        elif ev.get("type") == "response_item" and kind in (
                "function_call_output", "custom_tool_call_output", "tool_result"):
            call_id = payload.get("call_id") or payload.get("tool_call_id")
            text = result_text(payload)
            if call_id:
                results[call_id] = (payload, text)
        elif ev.get("type") == "event_msg" and kind not in ("token_count", ""):
            # Harness/Orca output exports vary by runtime.  Only inspect event
            # messages that are explicitly output-like; token counts are not
            # wake evidence.
            text = result_text(payload)
            wake = wake_kind(text)
            if wake:
                wake_kinds[wake] += 1
        elif ev.get("type") == "event_msg" and kind == "token_count":
            usage = (payload.get("info") or {}).get("last_token_usage") or {}
            # Tokens belong to the round-trip, so they land on whichever call
            # drove it; a round-trip with no preceding call lands in <none>.
            buckets[driver][0] += usage.get("input_tokens", 0) + usage.get("output_tokens", 0)
            round_trips += 1
            driver = "<none>"
    for call in calls:
        result = results.get(call["id"])
        if result is not None:
            payload, text = result
            call["success"] = result_success(payload, text)
            wake = wake_kind(text)
            if wake:
                wake_kinds[wake] += 1
    for call_id, (payload, text) in results.items():
        if ("orca terminal read" in call_commands.get(call_id, "").lower()
                and wake_kinds.get("orca_timeout", 0)):
            wake_kinds["justified_recovery"] += 1
    successful = {call["dispatch_id"] for call in calls
                  if call["success"] is not False and call["dispatch_id"]}
    failed = sum(call["success"] is False for call in calls)
    tasks = len(successful)
    dispatch_stats = {"attempts": len(calls), "successful": tasks,
                      "failed": failed, "ids": sorted(successful)}
    return (started, buckets, tasks, round_trips, agent, windows, dispatch_stats,
            dict(wake_kinds)) if buckets else None


def report(buckets, tasks, round_trips, label, windows, min_wait_ms, indent="",
           dispatch_stats=None, wake_kinds=None):
    """Print the breakdown. `tasks=None` omits the ratio, for a view that spans
    sessions of different roles: pooling one session's polls against another's
    dispatches produces a number that means nothing next to the enforced one."""
    total = sum(t for t, _ in buckets.values()) or 1
    polls = buckets["POLL"][1]
    # Tokens per round-trip is the context tax: on a measured repo, 97% of all
    # spend was context re-sent, not text produced, so what a turn *did* moves
    # the bill far less than how much context it carried while doing it. A
    # session that keeps its reads bounded pays a third of what a session that
    # loads the codebase pays for the same number of turns. Printed next to the
    # ratio because the two rules trade against each other: waiting wider costs
    # fewer turns, and every turn is charged at this rate.
    per_trip = total / round_trips if round_trips else 0
    head = (f"{indent}{label}: {total/1e6:.1f}M tokens, {round_trips} round-trips, "
            f"{per_trip/1e3:.0f}k per trip")
    if tasks is None:
        per_task = None
        print(head)
    else:
        # No dispatches but still polling is unbounded waste, not a clean ratio.
        per_task = polls / tasks if tasks else (float("inf") if polls else 0.0)
        print(f"{head}, {polls} polls / {tasks} tasks = {ratio_text(per_task)} per task")
        if tasks:
            print(f"{indent}  {polls} polls / {tasks} successful dispatches = "
                  f"{ratio_text(per_task)} polls per dispatch")
    for name in ("POLL", "WORK", "DISPATCH", "EDIT", "<none>"):
        tok, cnt = buckets[name]
        if tok:
            print(f"{indent}  {name:9} {cnt:5} calls {tok/1e6:7.1f}M {100*tok/total:5.1f}%")
    short = [w for w in windows if w < min_wait_ms]
    if short:
        print(f"{indent}  {len(short)} of {len(windows)} declared wait windows under "
                f"{min_wait_ms // 60000}m, shortest {min(short) / 1000:.0f}s")
    if dispatch_stats:
        print(f"{indent}  dispatch attempts {dispatch_stats['attempts']}, successful "
              f"{dispatch_stats['successful']}, failed {dispatch_stats['failed']}")
    if wake_kinds is not None:
        print(f"{indent}  wakes: event delivery {wake_kinds.get('event_delivery', 0)}, "
              f"empty resumption {wake_kinds.get('empty_resumption', 0)}, "
              f"harness wake {wake_kinds.get('harness_yield', 0)}, "
              f"Orca timeout {wake_kinds.get('orca_timeout', 0)}, "
              f"justified recovery {wake_kinds.get('justified_recovery', 0)}")
    return per_task


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", help="YYYY-MM-DD (default: 7 days ago)")
    ap.add_argument("--sessions", action="store_true", help="break down per session")
    ap.add_argument("--root", action="append", metavar="DIR",
                    help="log directory, repeatable (default: ~/.codex/sessions "
                         "and ~/.claude/projects)")
    ap.add_argument("--max-polls-per-task", type=float, default=2.0,
                    help="supervision budget from docs/orchestration/supervision.md")
    # 5 minutes, not the 15 the rule states, because 15 is not reachable on
    # this path: the effective window is capped by the harness yield, and the
    # largest yield observed across the measured corpus is 300000 ms against
    # 1469 calls at 30000. A floor of 15 minutes here would fail every session
    # unconditionally and stop being a signal. 15 minutes remains the rule for
    # a coordinator that waits *outside* the model loop, where nothing caps it.
    ap.add_argument("--min-wait-ms", type=int, default=300_000,
                    help="shortest effective supervision wait the substrate can honour "
                         "(5 minutes; docs/orchestration/supervision.md asks for 15 off-loop)")
    args = ap.parse_args()
    since = args.since or str(datetime.date.today() - datetime.timedelta(days=7))
    try:
        datetime.date.fromisoformat(since)
    except ValueError:
        print(f"--since must be YYYY-MM-DD, got {since!r}", file=sys.stderr)
        return 2

    roots = args.root or ["~/.codex/sessions", "~/.claude/projects"]
    found = [(p, r)
             for root in roots
             for p in glob.glob(os.path.expanduser(root) + "/**/*.jsonl", recursive=True)
             for r in [scan(p, since)] if r]
    if not found:
        print(f"no sessions since {since} under {', '.join(roots)} — nothing measured, "
              f"budget not checked")
        return 0

    combined = collections.defaultdict(lambda: [0, 0])
    tasks = round_trips = 0
    # The budget divides by dispatched tasks, so only sessions that dispatched
    # something are coordinators the rule can apply to. A worker session waits
    # on its own commands and dispatches nothing; judging it would flag normal
    # work as unbounded supervision.
    coordinator_polls = coordinator_tasks = 0
    successful_dispatch_ids = set()
    coordinator_tokens = worker_tokens = polling_tokens = 0
    combined_wakes = collections.Counter()
    worst = (0.0, "")
    all_windows = []
    # The window rule is about a single call, not a rate, so unlike the ratio it
    # applies to any session that supervises -- a worker waiting on its own
    # children is subject to it too. Named by the session with the most short
    # windows rather than the single shortest one: pairing a global count with
    # the owner of one outlier reads as if that session owned them all.
    worst_windows = (0, "")
    for path, (started, buckets, session_tasks, session_trips, agent, windows,
               dispatch_stats, wake_kinds) in sorted(found, key=lambda x: x[1][0]):
        for name, (tok, cnt) in buckets.items():
            combined[name][0] += tok
            combined[name][1] += cnt
        tasks += session_tasks
        round_trips += session_trips
        all_windows += windows
        combined_wakes.update(wake_kinds)
        session_total = sum(tok for tok, _ in buckets.values())
        polling_tokens += buckets["POLL"][0]
        if dispatch_stats["attempts"]:
            coordinator_tokens += session_total
        else:
            worker_tokens += session_total
        label = f"{started} {os.path.basename(path)[:40]}"
        if agent:
            label += f" (subagent {agent})"
        if args.sessions:
            report(buckets, session_tasks, session_trips, label, windows, args.min_wait_ms,
                   indent="  ", dispatch_stats=dispatch_stats, wake_kinds=wake_kinds)
        short = [w for w in windows if w < args.min_wait_ms]
        if len(short) > worst_windows[0]:
            worst_windows = (len(short), label)
        if not dispatch_stats["attempts"]:
            continue
        polls = buckets["POLL"][1]
        coordinator_polls += polls
        successful_dispatch_ids.update(dispatch_stats["ids"])
        if session_tasks and polls / session_tasks > worst[0]:
            worst = (polls / session_tasks, label)
    coordinator_tasks = len(successful_dispatch_ids)
    print()
    report(combined, None, round_trips, f"all sessions since {since}", all_windows,
           args.min_wait_ms, dispatch_stats={
               "attempts": sum(x[1][6]["attempts"] for x in found),
               "successful": coordinator_tasks,
               "failed": sum(x[1][6]["failed"] for x in found),
               "ids": sorted(successful_dispatch_ids),
           }, wake_kinds=dict(combined_wakes))
    print(f"coordinator tokens: {coordinator_tokens/1e6:.1f}M")
    print(f"worker tokens: {worker_tokens/1e6:.1f}M")
    print(f"polling tokens: {polling_tokens/1e6:.1f}M")

    # Both rules are reported before either exits, so one breach never hides
    # the other.
    failed = False
    if worst_windows[0]:
        print(f"\nwindow too short: worst is {worst_windows[0]} under "
              f"{args.min_wait_ms // 60000} minutes — {worst_windows[1]}. A short window makes "
              f"the right primitive poll: the wait returns, nothing has finished, and the whole "
              f"context is re-sent to wait again. See docs/orchestration/supervision.md#supervise.")
        failed = True

    if not coordinator_tasks:
        print("no session dispatched a task — the per-task budget does not apply")
        return 1 if failed else 0

    # The rule is per dispatch, so a pooled average is not enough: one runaway
    # coordinator is exactly what an average over many quiet sessions hides.
    pooled = coordinator_polls / coordinator_tasks
    summary = (f"coordinator sessions: {coordinator_polls} polls / {coordinator_tasks} tasks "
               f"= {pooled:.1f} per task")
    print(f"{coordinator_polls} polls / {coordinator_tasks} successful dispatches = "
          f"{pooled:.1f} polls per dispatch")
    print(f"{summary}; worst {worst[0]:.1f} — {worst[1]}" if worst[1] else summary)
    breach = max(pooled, worst[0])
    if breach > args.max_polls_per_task:
        print(f"\nover budget: {breach:.1f} supervision calls per dispatched task "
              f"> {args.max_polls_per_task:.0f}. Wait wider — one blocking wait covering every "
              f"outstanding worker. Cheapest is to wait off the model loop and be re-invoked on "
              f"the event; if blocking in-call, set the harness yield and the window together, "
              f"since the smaller one decides how often you wake. See "
              f"docs/orchestration/supervision.md#supervise.")
        failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
