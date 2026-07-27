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

# Round-trip shapes taken from real rollouts under ~/.codex/sessions: a shell
# command is `exec_command` carrying a `cmd` string (not an argv array), and a
# blocking wait is the `wait` tool. Every round-trip is 10k tokens, so token
# share stays fixed and only the supervision ratio moves.
turn() { # $1 = tool name, $2 = arguments JSON (already escaped for the log)
  printf '{"type":"response_item","payload":{"type":"function_call","name":"%s","arguments":"%s"}}\n' "$1" "$2"
  printf '{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":9000,"output_tokens":1000}}}}\n'
}

shell_turn() { # $1 = command line
  turn exec_command "{\\\"cmd\\\":\\\"$1\\\",\\\"yield_time_ms\\\":10000,\\\"workdir\\\":\\\"/demo\\\"}"
}

# A rollout log with $1 polling round-trips, $2 task dispatches, $3 work
# round-trips.
write_rollout() {
  local dir=$1 polls=$2 dispatches=$3 work=$4 i
  mkdir -p "$dir"
  {
    printf '{"type":"session_meta","payload":{"timestamp":"2026-07-24T01:00:00.000Z","cwd":"/demo"}}\n'
    for ((i = 0; i < dispatches; i++)); do
      shell_turn "orca orchestration dispatch --task t$i --inject"
    done
    for ((i = 0; i < polls; i++)); do
      turn wait '{\"cell_id\":\"1\",\"yield_time_ms\":30000,\"max_tokens\":5000}'
    done
    for ((i = 0; i < work; i++)); do
      shell_turn "pytest -q"
    done
  } >"$dir/rollout-demo.jsonl"
}

raw_turn() { # $1 = raw (non-JSON) argument string, as `exec` really arrives
  printf '{"type":"response_item","payload":{"type":"custom_tool_call","name":"exec","input":"%s"}}\n' "$1"
  printf '{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":9000,"output_tokens":1000}}}}\n'
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
  output=$(burn "$root" --sessions) || fail "a session with no dispatches must not be judged: $output"
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
  local root="$TMP_ROOT/range" output
  write_rollout "$root/2026/07/24" 9 1 0
  # In range the same fixture is a clear violation, so the empty-range pass
  # below can only come from the date filter.
  if output=$(burn "$root"); then
    fail "the fixture must be a violation when in range: $output"
  fi
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
  {
    shell_turn "grep -rn spawn docs/"
    shell_turn "grep -rn respawn docs/"
    shell_turn "rg dispatched docs/"
  } >>"$root/2026/07/24/rollout-demo.jsonl"
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

test_read_only_subcommands_count_as_supervision() {
  local root="$TMP_ROOT/readonly" output
  # `dispatch-show` and `task-list` only ask how a worker is doing, so they are
  # supervision. A trailing \b in the dispatch pattern would match before the
  # hyphen and score `dispatch-show` as dispatched work instead.
  write_rollout "$root/2026/07/24" 6 1 0
  {
    shell_turn "orca orchestration dispatch-show --id d1"
    shell_turn "orca orchestration dispatch-show --id d2"
    shell_turn "orca orchestration task-list --json"
    shell_turn "orca terminal list --json"
  } >>"$root/2026/07/24/rollout-demo.jsonl"
  if output=$(burn "$root"); then
    fail "read-only subcommands must count against the budget: $output"
  fi
  case $output in
    *'10 polls / 1 tasks = 10.0 per task'*) ;;
    *) fail "expected 10 supervision calls over 1 dispatch, got: $output" ;;
  esac
}

test_an_undefined_ratio_never_prints_as_inf() {
  local root="$TMP_ROOT/undefined" output
  write_rollout "$root/2026/07/24" 3 0 0
  output=$(burn "$root" --sessions 2>&1) || true
  case $output in
    *'= inf per task'* | *'over budget: inf'*)
      fail "an undefined ratio must render as n/a, not inf: $output" ;;
  esac
  case $output in
    *'= n/a per task'*) ;;
    *) fail "expected the undefined ratio to render as n/a, got: $output" ;;
  esac
}

test_patch_text_is_edit_not_dispatch() {
  local root="$TMP_ROOT/patchtext" output
  write_rollout "$root/2026/07/24" 2 1 0
  # The tool name is authoritative: a patch that happens to contain the word
  # "dispatch" is still an edit.
  turn apply_patch '{\"input\":\"+ orca orchestration dispatch --task t1\"}' \
    >>"$root/2026/07/24/rollout-demo.jsonl"
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
  local root="$TMP_ROOT/breakdown" output
  write_rollout "$root/2026/07/24" 0 20 0
  mv "$root/2026/07/24/rollout-demo.jsonl" "$root/2026/07/24/rollout-quiet.jsonl"
  write_rollout "$root/2026/07/25" 9 1 0
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

test_two_dispatches_in_one_round_trip_count_twice() {
  local root="$TMP_ROOT/batched" output
  write_rollout "$root/2026/07/24" 4 0 0
  # Two dispatch calls before a single token_count. Collapsing them to one task
  # loses part of the denominator and inflates the ratio.
  {
    printf '{"type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"orca orchestration dispatch --task a\\"}"}}\n'
    printf '{"type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"orca orchestration dispatch --task b\\"}"}}\n'
    printf '{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":9000,"output_tokens":1000}}}}\n'
  } >>"$root/2026/07/24/rollout-demo.jsonl"
  output=$(burn "$root") || fail "4 polls over 2 tasks is within budget: $output"
  case $output in
    *'4 polls / 2 tasks = 2.0 per task'*) ;;
    *) fail "both dispatches in one round-trip must count, got: $output" ;;
  esac
}

test_batched_supervision_calls_each_count() {
  local root="$TMP_ROOT/batchedpolls" output
  write_rollout "$root/2026/07/24" 0 1 0
  # Eight waits before a single token_count. Counting polls per round-trip
  # while counting tasks per call would score this 1 poll / 1 task and pass,
  # while the same batching on the dispatch side counts eight.
  {
    for _ in 1 2 3 4 5 6 7 8; do
      printf '{"type":"response_item","payload":{"type":"function_call","name":"wait","arguments":"{\\"cell_id\\":\\"1\\"}"}}\n'
    done
    printf '{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":9000,"output_tokens":1000}}}}\n'
  } >>"$root/2026/07/24/rollout-demo.jsonl"
  if output=$(burn "$root"); then
    fail "eight batched waits must each count as supervision: $output"
  fi
  case $output in
    *'8 polls / 1 tasks = 8.0 per task'*) ;;
    *) fail "expected all eight waits counted, got: $output" ;;
  esac
}

test_raw_argument_calls_are_classified() {
  local root="$TMP_ROOT/rawargs" output
  write_rollout "$root/2026/07/24" 0 1 0
  # `exec` arrives as a custom_tool_call whose arguments are a raw string.
  {
    raw_turn 'const r = await sh(\"orca orchestration check --wait\");'
    raw_turn 'const r = await sh(\"orca terminal read --terminal t1\");'
    raw_turn 'const r = await sh(\"orca terminal read --terminal t2\");'
  } >>"$root/2026/07/24/rollout-demo.jsonl"
  if output=$(burn "$root"); then
    fail "supervision in raw-argument calls must count: $output"
  fi
  case $output in
    *'3 polls / 1 tasks = 3.0 per task'*) ;;
    *) fail "expected raw-argument supervision to be counted, got: $output" ;;
  esac
}

test_write_stdin_counts_as_supervision_only_when_empty() {
  local root="$TMP_ROOT/stdin" output
  write_rollout "$root/2026/07/24" 0 1 0
  {
    turn write_stdin '{\"chars\":\"\",\"session_id\":\"s1\"}'
    turn write_stdin '{\"chars\":\"\",\"session_id\":\"s1\"}'
    turn write_stdin '{\"chars\":\"continue the task\",\"session_id\":\"s1\"}'
  } >>"$root/2026/07/24/rollout-demo.jsonl"
  output=$(burn "$root") || fail "2 empty writes over 1 task is within budget: $output"
  case $output in
    *'2 polls / 1 tasks = 2.0 per task'*) ;;
    *) fail "only the empty writes are supervision, got: $output" ;;
  esac
}

test_the_role_mixed_total_shows_no_ratio() {
  local root="$TMP_ROOT/rolemixed" output
  write_rollout "$root/2026/07/24" 6 2 0    # coordinator: 3.0 per task
  mv "$root/2026/07/24/rollout-demo.jsonl" "$root/2026/07/24/rollout-coord.jsonl"
  write_rollout "$root/2026/07/25" 20 0 0   # worker: polls, dispatches nothing
  # Pooling the worker's polls against the coordinator's dispatches would print
  # 26 polls / 2 tasks = 13.0 right above the 3.0 that is actually enforced.
  if output=$(burn "$root"); then
    fail "3.0 per task must fail the budget: $output"
  fi
  case $output in
    *'26 polls'* | *'= 13.0 per task'*)
      fail "the role-mixed total must not print a ratio: $output" ;;
  esac
  case $output in
    *'coordinator sessions: 6 polls / 2 tasks = 3.0 per task'*) ;;
    *) fail "expected the coordinator ratio, got: $output" ;;
  esac
}

test_a_subagent_session_is_labelled_as_one() {
  local root="$TMP_ROOT/subagent" output
  write_rollout "$root/2026/07/24" 2 1 0
  # A forked reviewer thread. Its log opens with the parent's history replayed,
  # and it dispatches nothing, so unlabelled it reads as another coordinator
  # that only ever watched. `source` is an object here, a bare "cli" string in
  # the session above.
  mkdir -p "$root/2026/07/25"
  {
    printf '{"type":"session_meta","payload":{"timestamp":"2026-07-25T01:00:00.000Z","cwd":"/demo","thread_source":"subagent","source":{"subagent":{"thread_spawn":{"parent_thread_id":"p1","depth":1,"agent_path":"/root/standards_review"}}}}}\n'
    shell_turn "pytest -q"
  } >"$root/2026/07/25/rollout-fork.jsonl"
  output=$(burn "$root" --sessions) || fail "2 polls / 1 task is within budget: $output"
  case $output in
    *'rollout-fork.jsonl (subagent /root/standards_review)'*) ;;
    *) fail "a forked thread must be labelled with its agent path, got: $output" ;;
  esac
  case $output in
    *'rollout-demo.jsonl:'*) ;;
    *) fail "a user-started session must carry no subagent label, got: $output" ;;
  esac
  case $output in
    *'rollout-demo.jsonl (subagent'*)
      fail "a user-started session must not be labelled a subagent: $output" ;;
  esac
}

test_bad_since_is_rejected() {
  local root="$TMP_ROOT/since" status=0
  write_rollout "$root/2026/07/24" 0 1 0
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
test_read_only_subcommands_count_as_supervision
test_an_undefined_ratio_never_prints_as_inf
test_patch_text_is_edit_not_dispatch
test_one_bad_session_is_not_hidden_by_quiet_ones
test_per_session_breakdown_reports_each_session
test_two_dispatches_in_one_round_trip_count_twice
test_batched_supervision_calls_each_count
test_raw_argument_calls_are_classified
test_write_stdin_counts_as_supervision_only_when_empty
test_the_role_mixed_total_shows_no_ratio
test_a_subagent_session_is_labelled_as_one
test_bad_since_is_rejected

printf 'PASS: supervision-cost meter\n'
