#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-ops-burn-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# One synthetic rollout: 2 polling round-trips (10k each), 1 work round-trip (10k).
mkdir -p "$TMP_ROOT/sessions/2026/07/24"
{
  printf '{"type":"session_meta","payload":{"timestamp":"2026-07-24T01:00:00.000Z","cwd":"/demo"}}\n'
  for _ in 1 2; do
    printf '{"type":"response_item","payload":{"type":"function_call","name":"wait","arguments":"{\\"cell_id\\":\\"1\\"}"}}\n'
    printf '{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":9000,"output_tokens":1000}}}}\n'
  done
  printf '{"type":"response_item","payload":{"type":"function_call","name":"exec","arguments":"{\\"command\\":[\\"pytest\\"]}"}}\n'
  printf '{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":9000,"output_tokens":1000}}}}\n'
} >"$TMP_ROOT/sessions/2026/07/24/rollout-demo.jsonl"

run_burn() {
  python3 "$ROOT/template/.orchestration/burn.py" --root "$TMP_ROOT/sessions" --since 2026-07-01 "$@"
}

# 2 of 3 round-trips are polling -> 67%, over the default 40% budget.
if output=$(run_burn); then
  fail "expected non-zero exit when polling is over budget: $output"
fi
printf '%s\n' "$output" | grep -q '67% polling' || fail "expected 67% polling, got: $output"
printf '%s\n' "$output" | grep -q 'over budget' || fail "expected over-budget warning: $output"

# Same data under a permissive budget passes.
run_burn --budget 90 >/dev/null || fail "expected zero exit when polling is within budget"

# No sessions in range is reported, not an error.
run_burn --since 2027-01-01 | grep -q 'no sessions since' || fail "expected empty-range notice"

printf 'burn: ok\n'
