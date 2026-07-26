#!/usr/bin/env python3
"""Supervision-cost meter: how many tokens went to polling vs real work.

Reads Codex rollout logs (~/.codex/sessions/**/*.jsonl) and attributes every API
round-trip to the tool call that caused it. Enforces the budget in
docs/orchestration/orca.md: polling should not dominate a coordinator session.

    python3 .orchestration/burn.py                # last 7 days
    python3 .orchestration/burn.py --since 2026-07-22 --sessions
"""
import argparse, collections, datetime, glob, json, os, re, sys

POLL = re.compile(r"orchestration check|terminal read|terminal wait|orchestration (?:inbox|status)", re.I)
DISPATCH = re.compile(r"orchestration (?:dispatch|task-create|reply|send)|terminal (?:send|create)|spawn", re.I)
POLL_TOOLS = {"wait", "wait_agent", "write_stdin"}
DISPATCH_TOOLS = {"send_message", "spawn_agent", "followup_task"}


def classify(name, args):
    if name in POLL_TOOLS or POLL.search(args):
        return "POLL"
    if name in DISPATCH_TOOLS or DISPATCH.search(args):
        return "DISPATCH"
    return "EDIT" if name == "apply_patch" else "WORK"


def scan(path, since):
    """-> (started, {bucket: [tokens, calls]}) or None if out of range/unparsable."""
    try:
        lines = open(path, encoding="utf-8", errors="replace").readlines()
        head = json.loads(lines[0])
    except (OSError, ValueError, IndexError):
        return None
    started = (head.get("payload") or {}).get("timestamp", "")[:10]
    if started < since:
        return None
    buckets = collections.defaultdict(lambda: [0, 0])
    driver = "<none>"
    for line in lines:
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        payload = ev.get("payload") if isinstance(ev.get("payload"), dict) else {}
        kind = payload.get("type")
        if ev.get("type") == "response_item" and kind in ("custom_tool_call", "function_call"):
            raw = payload.get("arguments") or payload.get("input") or ""
            driver = classify(payload.get("name") or "", raw if isinstance(raw, str) else json.dumps(raw))
        elif ev.get("type") == "event_msg" and kind == "token_count":
            usage = (payload.get("info") or {}).get("last_token_usage") or {}
            slot = buckets[driver]
            slot[0] += usage.get("input_tokens", 0) + usage.get("output_tokens", 0)
            slot[1] += 1
            driver = "<none>"
    return (started, buckets) if buckets else None


def report(buckets, label, indent=""):
    total = sum(t for t, _ in buckets.values()) or 1
    calls = sum(c for _, c in buckets.values())
    poll_pct = 100 * buckets["POLL"][0] / total
    print(f"{indent}{label}: {total/1e6:.1f}M tokens, {calls} round-trips, {poll_pct:.0f}% polling")
    for name in ("POLL", "WORK", "DISPATCH", "EDIT", "<none>"):
        tok, cnt = buckets[name]
        if tok:
            print(f"{indent}  {name:9} {cnt:5} calls {tok/1e6:7.1f}M {100*tok/total:5.1f}%")
    return poll_pct


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", help="YYYY-MM-DD (default: 7 days ago)")
    ap.add_argument("--sessions", action="store_true", help="break down per session")
    ap.add_argument("--root", default="~/.codex/sessions", help="rollout log directory")
    ap.add_argument("--budget", type=float, default=40.0, help="max %% of tokens spent polling")
    args = ap.parse_args()
    since = args.since or str(datetime.date.today() - datetime.timedelta(days=7))

    found = [(p, r) for p in glob.glob(os.path.expanduser(args.root) + "/**/*.jsonl", recursive=True)
             for r in [scan(p, since)] if r]
    if not found:
        print(f"no sessions since {since} under {args.root}")
        return 0

    combined = collections.defaultdict(lambda: [0, 0])
    for path, (started, buckets) in sorted(found, key=lambda x: x[1][0]):
        for name, (tok, cnt) in buckets.items():
            combined[name][0] += tok
            combined[name][1] += cnt
        if args.sessions:
            report(buckets, f"{started} {os.path.basename(path)[:40]}", indent="  ")
    print()
    poll_pct = report(combined, f"all sessions since {since}")
    if poll_pct > args.budget:
        print(f"\nover budget: {poll_pct:.0f}% polling > {args.budget:.0f}%. "
              f"Wait wider (one call, >=180s) — see docs/orchestration/orca.md#supervise.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
