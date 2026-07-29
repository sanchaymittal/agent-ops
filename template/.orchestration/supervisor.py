#!/usr/bin/env python3
"""Durable, event-driven orchestration supervision.

This module is deliberately small and provider-neutral.  Orca (or a compatible
runtime) owns the durable subscription; this file owns the coordinator-facing
state machine and its crash boundaries.  It is also useful as a deterministic
test double for a runtime that has not yet exposed its subscription API.

The important invariant is that waiting never acknowledges an event.  A peek
may return the same unread event after a process restart, but only ``ack``
removes it, and only after the coordinator has applied the event to task state.
Claiming an event is durable and idempotent, so a restart asks for recovery of
the same event instead of creating a second model resumption.
"""
from __future__ import annotations

import argparse
import datetime as dt
import functools
import hashlib
import json
import os
import pathlib
import sys
import tempfile
from contextlib import contextmanager
from typing import Any

try:
    import fcntl
except ImportError:  # pragma: no cover - the shipped target is POSIX
    fcntl = None

EVENT_TYPES = {
    "worker_done",
    "escalation",
    "decision_gate",
    "terminal_exit",
    "user_cancelled",
}
TASK_STATUSES = {"outstanding", "completed", "failed", "blocked", "cancelled"}


class StateError(RuntimeError):
    pass


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def event_id(event: dict[str, Any]) -> str:
    value = event.get("event_id") or event.get("id")
    if value:
        return str(value)
    stable = json.dumps(event, sort_keys=True, separators=(",", ":")).encode()
    return "event-" + hashlib.sha256(stable).hexdigest()[:24]


def load(path: pathlib.Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {"version": 1, "workers": {}, "events": {}, "dispatches": {}}
    except (OSError, json.JSONDecodeError) as exc:
        raise StateError(f"cannot read state: {path}: {exc}") from exc


def save(path: pathlib.Path, state: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(state, fh, sort_keys=True, indent=2)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(temp_name, path)
        directory_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass


def state_path(value: str) -> pathlib.Path:
    return pathlib.Path(value).expanduser().resolve()


@contextmanager
def state_lock(path: pathlib.Path):
    """Serialize read/modify/write transitions across coordinator restarts."""
    lock_path = pathlib.Path(str(path) + ".lock")
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a+") as lock:
        if fcntl is not None:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            if fcntl is not None:
                fcntl.flock(lock.fileno(), fcntl.LOCK_UN)


def locked(fn):
    @functools.wraps(fn)
    def wrapper(args):
        with state_lock(state_path(args.state)):
            return fn(args)
    return wrapper


def require_status(status: str) -> str:
    if status not in TASK_STATUSES:
        raise StateError(f"invalid task status: {status}")
    return status


@locked
def dispatch(args: argparse.Namespace) -> dict[str, Any]:
    path = state_path(args.state)
    state = load(path)
    dispatch_id = args.dispatch_id
    if dispatch_id in state["dispatches"]:
        existing = state["dispatches"][dispatch_id]
        if existing["worker_id"] != args.worker_id:
            raise StateError(f"dispatch ID already belongs to worker {existing['worker_id']}")
        return {"status": "already_dispatched", "dispatch": existing}
    record = {
        "dispatch_id": dispatch_id,
        "worker_id": args.worker_id,
        "status": "outstanding",
        "created_at": now(),
    }
    state["dispatches"][dispatch_id] = record
    state["workers"][args.worker_id] = {
        "dispatch_id": dispatch_id,
        "status": "outstanding",
    }
    save(path, state)
    return {"status": "dispatched", "dispatch": record}


@locked
def publish(args: argparse.Namespace) -> dict[str, Any]:
    path = state_path(args.state)
    state = load(path)
    if args.type not in EVENT_TYPES:
        raise StateError(f"unsupported event type: {args.type}")
    identity = {
        "event_id": args.event_id,
        "type": args.type,
        "dispatch_id": args.dispatch_id,
        "worker_id": args.worker_id,
        "status": args.status,
        "payload": args.payload,
    }
    eid = event_id(identity)
    existing = state["events"].get(eid)
    if existing:
        return {"status": "already_published", "event": existing}
    status = require_status(args.status)
    dispatch_record = state["dispatches"].get(args.dispatch_id)
    if args.dispatch_id and not dispatch_record:
        raise StateError(f"event references unknown dispatch: {args.dispatch_id}")
    if dispatch_record and dispatch_record["status"] in {"failed", "blocked", "cancelled"} \
            and status == "completed":
        raise StateError("a failed, blocked, or cancelled dispatch cannot become completed")
    event = {
        "event_id": eid,
        "type": args.type,
        "dispatch_id": args.dispatch_id,
        "worker_id": args.worker_id,
        "status": status,
        "payload": args.payload or {},
        "published_at": now(),
        "acknowledged": False,
        "claimed": False,
    }
    state["events"][eid] = event
    if args.dispatch_id:
        state["dispatches"][args.dispatch_id]["status"] = status
        if args.worker_id in state["workers"]:
            state["workers"][args.worker_id]["status"] = status
    save(path, state)
    return {"status": "published", "event": event}


@locked
def peek(args: argparse.Namespace) -> dict[str, Any]:
    state = load(state_path(args.state))
    for event in state["events"].values():
        if event["acknowledged"]:
            continue
        if args.type and event["type"] != args.type:
            continue
        if event["claimed"]:
            return {"status": "recovery_required", "event": event}
        return {"status": "event", "event": event}
    return {"status": "empty", "count": 0}


@locked
def claim(args: argparse.Namespace) -> dict[str, Any]:
    path = state_path(args.state)
    state = load(path)
    event = state["events"].get(args.event_id)
    if not event:
        raise StateError(f"event does not exist: {args.event_id}")
    if event["acknowledged"]:
        return {"status": "already_acknowledged", "event": event}
    if event["claimed"]:
        return {"status": "recovery_required", "event": event}
    event["claimed"] = True
    event["claimed_at"] = now()
    save(path, state)
    return {"status": "resumed", "event": event}


@locked
def acknowledge(args: argparse.Namespace) -> dict[str, Any]:
    path = state_path(args.state)
    state = load(path)
    event = state["events"].get(args.event_id)
    if not event:
        raise StateError(f"event does not exist: {args.event_id}")
    if not event["claimed"]:
        raise StateError("event must be claimed after coordinator action before acknowledgement")
    event["acknowledged"] = True
    event["acknowledged_at"] = now()
    save(path, state)
    return {"status": "acknowledged", "event": event}


@locked
def status(args: argparse.Namespace) -> dict[str, Any]:
    state = load(state_path(args.state))
    outstanding = [x for x in state["dispatches"].values() if x["status"] == "outstanding"]
    unread = [x for x in state["events"].values() if not x["acknowledged"]]
    return {
        "outstanding_workers": len(outstanding),
        "unread_events": len(unread),
        "workers": state["workers"],
        "events": unread,
    }


@locked
def subscribe(args: argparse.Namespace) -> dict[str, Any]:
    """Persist the one runtime-side all-worker subscription declaration."""
    path = state_path(args.state)
    state = load(path)
    check_name, wait_flag, peek_flag = "orca orchestration check", "--wait", "--peek"
    if check_name not in args.command or wait_flag not in args.command or peek_flag not in args.command:
        raise StateError("subscription must be one Orca check --wait --peek command")
    subscription = {
        "command": args.command,
        "types": sorted(EVENT_TYPES),
        "durable": True,
        "outstanding_workers": args.workers,
        "created_at": now(),
    }
    state["subscription"] = subscription
    save(path, state)
    return {"status": "subscribed", "subscription": subscription}


def selftest(args: argparse.Namespace) -> dict[str, Any]:
    """Synthetic dispatch/completion proof required before runtime adoption."""
    subscribed = subscribe(argparse.Namespace(
        state=args.state,
        command="orca orchestration check --wait --peek --types worker_done escalation decision_gate terminal_exit user_cancelled --timeout-ms 900000 --json",
        workers=[args.worker_id],
    ))
    dispatch_args = argparse.Namespace(state=args.state, dispatch_id=args.dispatch_id,
                                       worker_id=args.worker_id)
    dispatched = dispatch(dispatch_args)
    publish_args = argparse.Namespace(
        state=args.state, event_id="selftest-event", type="worker_done",
        dispatch_id=args.dispatch_id, worker_id=args.worker_id, status="completed",
        payload={"synthetic": True},
    )
    published = publish(publish_args)
    event = published["event"]
    claimed = claim(argparse.Namespace(state=args.state, event_id=event["event_id"]))
    acknowledged = acknowledge(argparse.Namespace(state=args.state, event_id=event["event_id"]))
    return {"status": "proof_passed", "subscription": subscribed["status"],
            "dispatch": dispatched["status"],
            "event": claimed["status"], "ack": acknowledged["status"],
            "task_status": acknowledged["event"]["status"]}


def parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="command", required=True)
    for name, fn in (("dispatch", dispatch), ("publish", publish), ("peek", peek),
                     ("claim", claim), ("ack", acknowledge), ("status", status),
                     ("subscribe", subscribe), ("selftest", selftest)):
        command = sub.add_parser(name)
        command.set_defaults(fn=fn)
        command.add_argument("--state", required=True)
        if name == "dispatch":
            command.add_argument("--dispatch-id", required=True)
            command.add_argument("--worker-id", required=True)
        elif name == "publish":
            command.add_argument("--event-id")
            command.add_argument("--type", required=True)
            command.add_argument("--dispatch-id", default="")
            command.add_argument("--worker-id", default="")
            command.add_argument("--status", required=True)
            command.add_argument("--payload", type=json.loads, default={})
        elif name == "peek":
            command.add_argument("--type")
        elif name in {"claim", "ack"}:
            command.add_argument("--event-id", required=True)
        elif name == "selftest":
            command.add_argument("--dispatch-id", default="synthetic-dispatch")
            command.add_argument("--worker-id", default="synthetic-worker")
        elif name == "subscribe":
            command.add_argument("--command", required=True)
            command.add_argument("--workers", nargs="+", required=True)
    return ap


def main(argv: list[str] | None = None) -> int:
    try:
        args = parser().parse_args(argv)
        print(json.dumps(args.fn(args), sort_keys=True))
        return 0
    except StateError as exc:
        print(f"blocked: supervision: {exc}", file=sys.stderr)
        return 1
    except (OSError, ValueError, TypeError) as exc:
        print(f"blocked: supervision: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
