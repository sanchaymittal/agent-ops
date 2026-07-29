#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BURN="$ROOT/template/.orchestration/burn.py"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-ops-garuda.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

python3 - "$TMP_ROOT/2026/07/24/rollout-garuda.jsonl" <<'PY'
import json, pathlib, sys

path = pathlib.Path(sys.argv[1])
path.parent.mkdir(parents=True)
rows = [{"type": "session_meta", "payload": {"timestamp": "2026-07-24T01:00:00Z"}}]
def call(name, arguments, call_id):
    rows.append({"type": "response_item", "payload": {
        "type": "function_call", "name": name, "call_id": call_id,
        "arguments": json.dumps(arguments),
    }})
    rows.append({"type": "event_msg", "payload": {"type": "token_count",
                 "info": {"last_token_usage": {"input_tokens": 9000, "output_tokens": 1000}}}})

for i in range(8):
    call("exec_command", {"cmd": f"orca orchestration dispatch --task garuda-{i}"}, f"d-{i}")
    rows.append({"type": "response_item", "payload": {
        "type": "function_call_output", "call_id": f"d-{i}",
        "exit_code": 0 if i != 3 else 1,
        "output": "dispatch accepted" if i != 3 else "dispatch failed",
    }})
for i in range(119):
    call("wait", {"cell_id": "garuda", "yield_time_ms": 900000}, f"p-{i}")
path.write_text("\n".join(json.dumps(row) for row in rows) + "\n")
PY

output=$(python3 "$BURN" --root "$TMP_ROOT" --since 2026-07-01 --max-polls-per-task 17)
case "$output" in
  *'119 polls / 7 tasks = 17.0 per task'*) ;;
  *) printf 'FAIL: Garuda replay did not report 119 / 7: %s\n' "$output" >&2; exit 1 ;;
esac
case "$output" in
  *'119 polls / 7 successful dispatches = 17.0 polls per dispatch'*) ;;
  *) printf 'FAIL: Garuda replay did not report polls per dispatch: %s\n' "$output" >&2; exit 1 ;;
esac
case "$output" in
  *'dispatch attempts 8, successful 7, failed 1'*) ;;
  *) printf 'FAIL: failed dispatch inflated the denominator: %s\n' "$output" >&2; exit 1 ;;
esac

STATE="$TMP_ROOT/runtime-state.json"
proof=$("$ROOT/template/.orchestration/supervise.sh" runtime selftest --state "$STATE")
case "$proof" in
  *'"status": "proof_passed"'*'"task_status": "completed"'*) ;;
  *) printf 'FAIL: runtime synthetic proof did not complete: %s\n' "$proof" >&2; exit 1 ;;
esac

printf 'PASS: Garuda lifecycle replay\n'
