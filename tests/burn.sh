#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BURN="$ROOT/template/.orchestration/burn.py"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-ops-burn-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# A rollout log with $1 polling round-trips, $2 task dispatches, $3 work
# round-trips. Every round-trip is 10k tokens, so token share stays fixed and
# only the supervision ratio moves.
write_rollout() {
  local dir=$1 polls=$2 dispatches=$3 work=$4 i
  mkdir -p "$dir"
  {
    printf '{"type":"session_meta","payload":{"timestamp":"2026-07-24T01:00:00.000Z","cwd":"/demo"}}\n'
    for ((i = 0; i < dispatches; i++)); do
      printf '{"type":"response_item","payload":{"type":"function_call","name":"exec","arguments":"{\\"command\\":[\\"bash\\",\\"-lc\\",\\"orca orchestration dispatch --task t%d --inject\\"]}"}}\n' "$i"
      printf '{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":9000,"output_tokens":1000}}}}\n'
    done
    for ((i = 0; i < polls; i++)); do
      printf '{"type":"response_item","payload":{"type":"function_call","name":"wait","arguments":"{\\"cell_id\\":\\"1\\"}"}}\n'
      printf '{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":9000,"output_tokens":1000}}}}\n'
    done
    for ((i = 0; i < work; i++)); do
      printf '{"type":"response_item","payload":{"type":"function_call","name":"exec","arguments":"{\\"command\\":[\\"pytest\\"]}"}}\n'
      printf '{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":9000,"output_tokens":1000}}}}\n'
    done
  } >"$dir/rollout-demo.jsonl"
}

burn() {
  local root=$1
  shift
  python3 "$BURN" --root "$root" --since 2026-07-01 "$@"
}

test_budget_counts_polls_per_task_not_token_share() {
  local root="$TMP_ROOT/ratio"
  # 6 polls / 3 dispatches = 2.0 per task: exactly at budget, and polling is
  # 60% of tokens. A token-share budget would reject this; the documented rule
  # does not.
  write_rollout "$root/2026/07/24" 6 3 1
  local output
  output=$(burn "$root") || fail "2.0 polls/task must pass a budget of 2: $output"
  case $output in
    *'6 polls / 3 tasks = 2.0 per task'*) ;;
    *) fail "expected the ratio in the summary line, got: $output" ;;
  esac
}

test_budget_rejects_excess_supervision() {
  local root="$TMP_ROOT/excess" output
  write_rollout "$root/2026/07/24" 9 3 1
  if output=$(burn "$root"); then
    fail "3.0 polls/task must fail a budget of 2: $output"
  fi
  case $output in
    *'over budget: 3.0 supervision calls per dispatched task > 2'*) ;;
    *) fail "expected the over-budget line, got: $output" ;;
  esac
  case $output in
    *'window >= 15 minutes'*) ;;
    *) fail "remediation must state the documented window, got: $output" ;;
  esac
}

test_polling_with_no_dispatch_is_rejected() {
  local root="$TMP_ROOT/nodispatch" output
  write_rollout "$root/2026/07/24" 4 0 1
  if output=$(burn "$root"); then
    fail "polling with nothing dispatched must fail: $output"
  fi
  case $output in
    *'4 polls / 0 tasks = n/a per task'*) ;;
    *) fail "expected an undefined ratio, got: $output" ;;
  esac
}

test_a_quiet_session_is_within_budget() {
  local root="$TMP_ROOT/quiet"
  write_rollout "$root/2026/07/24" 0 2 5
  burn "$root" >/dev/null || fail "no polling must pass"
}

test_budget_is_configurable() {
  local root="$TMP_ROOT/configurable"
  write_rollout "$root/2026/07/24" 9 3 1
  burn "$root" --max-polls-per-task 3 >/dev/null ||
    fail "3.0 polls/task must pass an explicit budget of 3"
}

test_empty_range_reports_that_nothing_was_checked() {
  local root="$TMP_ROOT/ratio" output
  output=$(burn "$root" --since 2027-01-01) || fail "an empty range is not a violation"
  case $output in
    *'nothing measured, budget not checked'*) ;;
    *) fail "an empty range must say the budget went unchecked, got: $output" ;;
  esac
}

test_malformed_lines_do_not_abort_the_scan() {
  local root="$TMP_ROOT/malformed" output
  write_rollout "$root/2026/07/24" 6 3 1
  printf 'not json at all\n{"type":"response_item"}\n' >>"$root/2026/07/24/rollout-demo.jsonl"
  output=$(burn "$root") || fail "malformed lines must be skipped, not fatal: $output"
  case $output in
    *'6 polls / 3 tasks'*) ;;
    *) fail "malformed lines must not change the tally, got: $output" ;;
  esac
}

test_bad_since_is_rejected() {
  local root="$TMP_ROOT/ratio" status=0
  python3 "$BURN" --root "$root" --since 07-24-2026 >/dev/null 2>&1 || status=$?
  [ "$status" -eq 2 ] || fail "a malformed --since must exit 2, got $status"
}

test_budget_counts_polls_per_task_not_token_share
test_budget_rejects_excess_supervision
test_polling_with_no_dispatch_is_rejected
test_a_quiet_session_is_within_budget
test_budget_is_configurable
test_empty_range_reports_that_nothing_was_checked
test_malformed_lines_do_not_abort_the_scan
test_bad_since_is_rejected

printf 'PASS: supervision-cost meter\n'
