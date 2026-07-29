#!/usr/bin/env python3
"""Bounded fallback for runtimes without an event wakeup API.

The fallback is intentionally a policy gate around a single all-worker
``check --wait --peek``.  It never turns a harness yield into a liveness read.
Callers classify the completed result with ``resume`` and may inspect liveness
only for a genuine Orca timeout/empty result.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import shlex
import subprocess
import sys
from typing import Any

MIN_TIMEOUT_MS = 900_000
MIN_CONTINUATION_MS = 300_000
HARNESS_YIELD = re.compile(r"(?:process|command|script)\s+(?:is\s+)?still\s+running|still running", re.I)
ORCA_EMPTY = re.compile(r"(?:\b\"?count\"?\s*[:=]\s*0\b|\btimeout\b|timed out|no events?)", re.I)
EVENT = re.compile(r"worker_done|escalation|decision[_ -]?gate|terminal[_ -]?exit|user[_ -]?cancel", re.I)


def fail(message: str) -> None:
    raise ValueError(message)


def command_policy(command: str) -> dict[str, Any]:
    if "orca orchestration check" not in command:
        fail("wait command must be Orca orchestration check")
    if "--wait" not in command or "--peek" not in command:
        fail("every fallback wait must include --wait and --peek")
    if re.search(r"[;&|`$()]", command):
        fail("wait command must contain one argv command and no shell composition")
    match = re.search(r"--timeout-ms(?:=|\s+)(\d+)", command)
    if not match or int(match.group(1)) < MIN_TIMEOUT_MS:
        fail("fallback wait window must be at least 900000 ms")
    if re.search(r"orca\s+(?:terminal|status)|\b(?:read|list|show|task-list)\b", command):
        fail("status and terminal inspection are forbidden while the wait is active")
    return {"wait": "all outstanding workers", "timeout_ms": int(match.group(1)), "peek": True}


def classify(text: str) -> str:
    if HARNESS_YIELD.search(text):
        return "harness_yield"
    if EVENT.search(text):
        return "event_delivery"
    if ORCA_EMPTY.search(text):
        return "orca_timeout"
    return "unknown"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="command", required=True)
    start = sub.add_parser("start")
    start.add_argument("--state", required=True)
    start.add_argument("--wait-command", required=True)
    start.add_argument("--workers", nargs="+", required=True)
    start.add_argument("--run", action="store_true",
                       help="execute the validated wait command and capture its result")
    result = sub.add_parser("resume")
    result.add_argument("--state", required=True)
    result.add_argument("--result-file", required=True)
    result.add_argument("--continuation-ms", type=int, default=300_000)
    args = ap.parse_args(argv)
    try:
        if args.command == "start":
            policy = command_policy(args.wait_command)
            path = pathlib.Path(args.state)
            if path.exists():
                fail("an active fallback wait already exists")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps({
                "active": True,
                "workers": args.workers,
                "supervision_calls": 1,
                "policy": policy,
                "phase": "waiting",
            }, indent=2) + "\n", encoding="utf-8")
            if args.run:
                completed = subprocess.run(shlex.split(args.wait_command),
                                           capture_output=True, text=True, check=False)
                output = (completed.stdout or "") + (completed.stderr or "")
                path.write_text(json.dumps({
                    "active": True, "workers": args.workers, "supervision_calls": 1,
                    "policy": policy, "phase": classify(output),
                    "result": output[:32768], "exit_code": completed.returncode,
                }, indent=2) + "\n", encoding="utf-8")
                print(json.dumps({"status": "wait_completed", "reason": classify(output),
                                  "exit_code": completed.returncode,
                                  "supervision_calls": 1}))
                return 0
            print(json.dumps({"status": "start_wait", "supervision_calls": 1, **policy}))
            return 0
        state_path = pathlib.Path(args.state)
        state = json.loads(state_path.read_text(encoding="utf-8"))
        if state.get("supervision_calls", 0) >= 2:
            fail("fallback supervision cap exceeded; escalate instead of polling")
        text = pathlib.Path(args.result_file).read_text(encoding="utf-8", errors="replace")
        kind = classify(text)
        if kind == "harness_yield":
            if args.continuation_ms < MIN_CONTINUATION_MS:
                fail("harness-yield continuation must be at least 300000 ms")
            state["phase"] = "waiting"
            state_path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
            print(json.dumps({"status": "continue_wait", "reason": kind,
                              "supervision_calls": 1, "inspection": False,
                              "continuation_ms": args.continuation_ms}))
        elif kind == "orca_timeout":
            state["supervision_calls"] = state.get("supervision_calls", 0) + 1
            state["phase"] = "liveness_allowed"
            state_path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
            print(json.dumps({"status": "liveness_allowed", "reason": kind,
                              "supervision_calls": state["supervision_calls"], "inspection": True}))
        elif kind == "event_delivery":
            print(json.dumps({"status": "act_on_event", "reason": kind,
                              "supervision_calls": 1, "inspection": False,
                              "consume_after_action": True}))
        else:
            fail("result is neither a harness yield, Orca timeout, nor event delivery")
        return 0
    except (OSError, ValueError) as exc:
        print(f"blocked: fallback: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
