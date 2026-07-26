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

test_a_session_that_dispatched_nothing_is_not_judged() {
  local root="$TMP_ROOT/nodispatch" output
  # A worker session waits on its own commands and dispatches nothing. The
  # budget divides by dispatched tasks, so the rule cannot apply to it.
  write_rollout "$root/2026/07/24" 4 0 1
  output=$(burn "$root") || fail "a session with no dispatches must not be judged: $output"
  case $output in
    *'4 polls / 0 tasks = n/a per task'*) ;;
    *) fail "expected an undefined ratio, got: $output" ;;
  esac
  case $output in
    *'no session dispatched a task — budget does not apply'*) ;;
    *) fail "expected the budget to be declared inapplicable, got: $output" ;;
  esac
}

test_worker_polling_does_not_inflate_a_coordinator_ratio() {
  local root="$TMP_ROOT/mixedroles" output
  write_rollout "$root/2026/07/24" 4 2 0   # coordinator: 4/2 = 2.0, at budget
  mv "$root/2026/07/24/rollout-demo.jsonl" "$root/2026/07/24/rollout-coord.jsonl"
  write_rollout "$root/2026/07/25" 30 0 0  # worker: heavy waiting, no dispatch
  output=$(burn "$root") || fail "worker waits must not push a compliant coordinator over: $output"
  case $output in
    *'coordinator sessions: 4 polls / 2 tasks = 2.0 per task'*) ;;
    *) fail "expected only coordinator sessions in the ratio, got: $output" ;;
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

test_prose_mentioning_dispatch_words_is_not_a_task() {
  local root="$TMP_ROOT/prose" output
  # A read-only grep for "spawn"/"dispatch" is ordinary coordinator activity.
  # If it counted as dispatched work it would inflate the denominator and turn
  # a real violation into a pass.
  write_rollout "$root/2026/07/24" 6 1 0
  for phrase in "grep -rn spawn docs/" "grep -rn respawn docs/" "rg dispatched docs/"; do
    {
      printf '{"type":"response_item","payload":{"type":"function_call","name":"exec","arguments":"{\\"command\\":[\\"bash\\",\\"-lc\\",\\"%s\\"]}"}}\n' "$phrase"
      printf '{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":9000,"output_tokens":1000}}}}\n'
    } >>"$root/2026/07/24/rollout-demo.jsonl"
  done
  # One real dispatch, six polls: 6.0 per task, a clear violation. If the greps
  # counted as dispatches the ratio would fall to 1.5 and silently pass.
  if output=$(burn "$root"); then
    fail "grepping for the word spawn must not count as a dispatch: $output"
  fi
  case $output in
    *'6 polls / 1 tasks'*) ;;
    *) fail "expected 1 task from one real dispatch, got: $output" ;;
  esac
}

test_an_undefined_ratio_never_prints_as_inf() {
  local root="$TMP_ROOT/prose" output
  output=$(burn "$root" 2>&1) || true
  case $output in
    *inf*) fail "an undefined ratio must render as n/a, not inf: $output" ;;
  esac
}

test_patch_text_is_edit_not_dispatch() {
  local root="$TMP_ROOT/patchtext" output
  write_rollout "$root/2026/07/24" 2 1 0
  # The tool name is authoritative: a patch that happens to contain the word
  # "dispatch" is still an edit.
  {
    printf '{"type":"response_item","payload":{"type":"function_call","name":"apply_patch","arguments":"{\\"input\\":\\"+ orca orchestration dispatch --task t1\\"}"}}\n'
    printf '{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":9000,"output_tokens":1000}}}}\n'
  } >>"$root/2026/07/24/rollout-demo.jsonl"
  output=$(burn "$root") || fail "2 polls / 1 task is within budget: $output"
  case $output in
    *'2 polls / 1 tasks'*) ;;
    *) fail "patch text must not add a task, got: $output" ;;
  esac
  case $output in
    *'EDIT          1 calls'*) ;;
    *) fail "apply_patch must bucket as EDIT, got: $output" ;;
  esac
}

test_one_bad_session_is_not_hidden_by_quiet_ones() {
  local root="$TMP_ROOT/mixed" output
  write_rollout "$root/2026/07/24" 0 20 0   # 20 tasks, no polling
  mv "$root/2026/07/24/rollout-demo.jsonl" "$root/2026/07/24/rollout-quiet.jsonl"
  write_rollout "$root/2026/07/25" 9 1 0    # one runaway coordinator: 9.0
  # Pooled: 9 polls / 21 tasks = 0.4, comfortably "within budget".
  if output=$(burn "$root"); then
    fail "a runaway session must fail even when the average is fine: $output"
  fi
  case $output in
    *'worst 9.0 — '*) ;;
    *) fail "expected the worst session to be named, got: $output" ;;
  esac
  case $output in
    *'over budget: 9.0 '*) ;;
    *) fail "the breach must be the worst session, not the average, got: $output" ;;
  esac
}

test_per_session_breakdown_reports_each_session() {
  local root="$TMP_ROOT/mixed" output
  output=$(burn "$root" --sessions) || true
  case $output in
    *rollout-quiet.jsonl*) ;;
    *) fail "--sessions must list each session, got: $output" ;;
  esac
  case $output in
    *'0 polls / 20 tasks = 0.0 per task'*) ;;
    *) fail "--sessions must show the per-session ratio, got: $output" ;;
  esac
}

test_bad_since_is_rejected() {
  local root="$TMP_ROOT/ratio" status=0
  python3 "$BURN" --root "$root" --since 07-24-2026 >/dev/null 2>&1 || status=$?
  [ "$status" -eq 2 ] || fail "a malformed --since must exit 2, got $status"
}

test_budget_counts_polls_per_task_not_token_share
test_budget_rejects_excess_supervision
test_a_session_that_dispatched_nothing_is_not_judged
test_worker_polling_does_not_inflate_a_coordinator_ratio
test_a_quiet_session_is_within_budget
test_budget_is_configurable
test_empty_range_reports_that_nothing_was_checked
test_malformed_lines_do_not_abort_the_scan
test_prose_mentioning_dispatch_words_is_not_a_task
test_an_undefined_ratio_never_prints_as_inf
test_patch_text_is_edit_not_dispatch
test_one_bad_session_is_not_hidden_by_quiet_ones
test_per_session_breakdown_reports_each_session
test_bad_since_is_rejected

printf 'PASS: supervision-cost meter\n'
