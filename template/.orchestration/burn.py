#!/usr/bin/env python3
"""Supervision-cost meter: what a coordinator spent watching vs doing.

Reads Codex rollout logs (~/.codex/sessions/**/*.jsonl) and attributes every API
round-trip to the tool call that drove it -- a round-trip with no preceding
call lands in <none>. Enforces the rule in
docs/orchestration/supervision.md: at most 2 supervision calls per dispatched
task. The token shares it also prints are context, not the budget.

    python3 .orchestration/burn.py                # last 7 days
    python3 .orchestration/burn.py --since 2026-07-22 --sessions

Scope limits, so the numbers are not read for more than they are:
  - Codex rollout logs only. A coordinator running on another CLI is invisible
    here; point --root at that CLI's logs only if they share this schema.
  - EDIT counts the `apply_patch` tool. A patch applied through a shell command
    lands in WORK, so EDIT is a floor on real editing, not a measurement of it.
"""
import argparse, collections, datetime, glob, json, os, re, sys

# These match raw command text, so both ends need anchoring. A bare `spawn`
# counts `grep -rn spawn docs/` as dispatched work; a trailing \b counts the
# read-only `dispatch-show` as a dispatch, because \b matches before a hyphen.
# Either one inflates the denominator the budget divides by and turns a
# violation into a pass, so subcommands are listed exactly and (?![\w-]) stops
# a prefix from matching its own longer siblings.
def _subcommands(group, *names):
    return rf"\b{group}\s+(?:{'|'.join(names)})(?![\w-])"


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
POLL_TOOLS = {"wait", "wait_agent"}
DISPATCH_TOOLS = {"send_message", "spawn_agent", "followup_task"}
TASK_START_TOOLS = {"spawn_agent"}


def classify(name, args):
    """Bucket a call. The tool name is authoritative; only fall back to reading
    the arguments when the name alone does not say what the call is."""
    if name == "apply_patch":
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
    if name == "apply_patch":  # patch text is content, never a dispatch
        return False
    return name in TASK_START_TOOLS or bool(TASK_START.search(args))


def ratio_text(per_task):
    return "n/a" if per_task == float("inf") else f"{per_task:.1f}"


def scan(path, since):
    """-> (started, {bucket: [tokens, calls]}, tasks, round_trips) or None."""
    try:
        lines = open(path, encoding="utf-8", errors="replace").readlines()
        head = json.loads(lines[0])
    except (OSError, ValueError, IndexError):
        return None
    started = (head.get("payload") or {}).get("timestamp", "")[:10]
    if started < since:
        return None
    buckets = collections.defaultdict(lambda: [0, 0])  # bucket -> [tokens, calls]
    tasks = round_trips = 0
    driver = "<none>"
    pending_task = 0
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
            pending_task += starts_task(name, raw)
        elif ev.get("type") == "event_msg" and kind == "token_count":
            usage = (payload.get("info") or {}).get("last_token_usage") or {}
            # Tokens belong to the round-trip, so they land on whichever call
            # drove it; a round-trip with no preceding call lands in <none>.
            buckets[driver][0] += usage.get("input_tokens", 0) + usage.get("output_tokens", 0)
            round_trips += 1
            tasks += pending_task
            driver, pending_task = "<none>", 0
    return (started, buckets, tasks, round_trips) if buckets else None


def report(buckets, tasks, round_trips, label, indent=""):
    """Print the breakdown. `tasks=None` omits the ratio, for a view that spans
    sessions of different roles: pooling one session's polls against another's
    dispatches produces a number that means nothing next to the enforced one."""
    total = sum(t for t, _ in buckets.values()) or 1
    polls = buckets["POLL"][1]
    head = f"{indent}{label}: {total/1e6:.1f}M tokens, {round_trips} round-trips"
    if tasks is None:
        per_task = None
        print(head)
    else:
        # No dispatches but still polling is unbounded waste, not a clean ratio.
        per_task = polls / tasks if tasks else (float("inf") if polls else 0.0)
        print(f"{head}, {polls} polls / {tasks} tasks = {ratio_text(per_task)} per task")
    for name in ("POLL", "WORK", "DISPATCH", "EDIT", "<none>"):
        tok, cnt = buckets[name]
        if tok:
            print(f"{indent}  {name:9} {cnt:5} calls {tok/1e6:7.1f}M {100*tok/total:5.1f}%")
    return per_task


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", help="YYYY-MM-DD (default: 7 days ago)")
    ap.add_argument("--sessions", action="store_true", help="break down per session")
    ap.add_argument("--root", default="~/.codex/sessions", help="rollout log directory")
    ap.add_argument("--max-polls-per-task", type=float, default=2.0,
                    help="supervision budget from docs/orchestration/supervision.md")
    args = ap.parse_args()
    since = args.since or str(datetime.date.today() - datetime.timedelta(days=7))
    try:
        datetime.date.fromisoformat(since)
    except ValueError:
        print(f"--since must be YYYY-MM-DD, got {since!r}", file=sys.stderr)
        return 2

    found = [(p, r) for p in glob.glob(os.path.expanduser(args.root) + "/**/*.jsonl", recursive=True)
             for r in [scan(p, since)] if r]
    if not found:
        print(f"no sessions since {since} under {args.root} — nothing measured, "
              f"budget not checked")
        return 0

    combined = collections.defaultdict(lambda: [0, 0])
    tasks = round_trips = 0
    # The budget divides by dispatched tasks, so only sessions that dispatched
    # something are coordinators the rule can apply to. A worker session waits
    # on its own commands and dispatches nothing; judging it would flag normal
    # work as unbounded supervision.
    coordinator_polls = coordinator_tasks = 0
    worst = (0.0, "")
    for path, (started, buckets, session_tasks, session_trips) in sorted(found, key=lambda x: x[1][0]):
        for name, (tok, cnt) in buckets.items():
            combined[name][0] += tok
            combined[name][1] += cnt
        tasks += session_tasks
        round_trips += session_trips
        label = f"{started} {os.path.basename(path)[:40]}"
        if args.sessions:
            report(buckets, session_tasks, session_trips, label, indent="  ")
        if not session_tasks:
            continue
        polls = buckets["POLL"][1]
        coordinator_polls += polls
        coordinator_tasks += session_tasks
        if polls / session_tasks > worst[0]:
            worst = (polls / session_tasks, label)
    print()
    report(combined, None, round_trips, f"all sessions since {since}")
    if not coordinator_tasks:
        print("no session dispatched a task — budget does not apply")
        return 0

    # The rule is per dispatch, so a pooled average is not enough: one runaway
    # coordinator is exactly what an average over many quiet sessions hides.
    pooled = coordinator_polls / coordinator_tasks
    summary = (f"coordinator sessions: {coordinator_polls} polls / {coordinator_tasks} tasks "
               f"= {pooled:.1f} per task")
    print(f"{summary}; worst {worst[0]:.1f} — {worst[1]}" if worst[1] else summary)
    breach = max(pooled, worst[0])
    if breach > args.max_polls_per_task:
        print(f"\nover budget: {breach:.1f} supervision calls per dispatched task "
              f"> {args.max_polls_per_task:.0f}. Wait wider — one blocking wait covering every "
              f"outstanding worker, window >= 15 minutes. See "
              f"docs/orchestration/supervision.md#supervise.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
