#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-ops-report-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

create_repo() {
  local target=$1 verify_cmd=${2:-printf verified}

  "$ROOT/init.sh" "$target" demo DEMO "$verify_cmd" >/dev/null
  git -C "$target" init -q
  git -C "$target" config user.name test
  git -C "$target" config user.email test@example.com
  git -C "$target" config commit.gpgsign false
  git -C "$target" add .
  git -C "$target" commit -qm baseline
}

write_evidence() {
  local target=$1 task_id=$2 allowed_paths=$3 base_sha=$4 diff_sha=$5
  local basename
  basename=$(printf '%s-engineering-minimal-change-engineer-change.md' "$(printf '%s' "$task_id" | tr '[:upper:]' '[:lower:]')")

  cp "$target/.orchestration/prompts/TEMPLATE.md" "$target/.orchestration/prompts/$basename"
  cp "$target/.orchestration/reports/TEMPLATE.md" "$target/.orchestration/reports/$basename"
  BASE_SHA=$base_sha DIFF_SHA=$diff_sha TASK_ID=$task_id ALLOWED_PATHS=$allowed_paths perl -pi -e '
    s/<OUTCOME>/done/g;
    s/<TASK_ID>/$ENV{TASK_ID}/g;
    s/<ATTEMPT>/1/g;
    s/<ROLE>/engineering-minimal-change-engineer/g;
    s/<BASE_SHA>/$ENV{BASE_SHA}/g;
    s/<RISK_TIER>/low/g;
    s#<ALLOWED_PATHS>#$ENV{ALLOWED_PATHS}#g;
    s/<FINAL_DIFF_SHA>/$ENV{DIFF_SHA}/g;
    s/<VERIFY_EXIT>/0/g;
    s/<VERIFIED_AT>/2026-07-19T00:00:00Z/g;
    s#<ACCEPTANCE_CHECK>#artifact: result.txt#g;
    s/<ACCEPTANCE_EVIDENCE>/result.txt contains the expected line/g;
  ' "$target/.orchestration/prompts/$basename" "$target/.orchestration/reports/$basename"

  printf '%s/.orchestration/reports/%s' "$target" "$basename"
}

test_accepts_report_for_current_diff() {
  local target="$TMP_ROOT/valid" base_sha diff_sha report
  create_repo "$target"
  base_sha=$(git -C "$target" rev-parse HEAD)
  printf 'changed\n' >"$target/result.txt"
  diff_sha=$(cd "$target" && ./.orchestration/verify.sh --diff-sha)
  report=$(write_evidence "$target" DEMO-1 result.txt "$base_sha" "$diff_sha")

  if ! "$target/.orchestration/verify.sh" "$report"; then
    fail "valid report was rejected"
  fi
}

test_rejects_out_of_scope_path() {
  local target="$TMP_ROOT/out-of-scope" base_sha diff_sha report
  create_repo "$target"
  base_sha=$(git -C "$target" rev-parse HEAD)
  printf 'allowed\n' >"$target/result.txt"
  printf 'not allowed\n' >"$target/secret.txt"
  diff_sha=$(cd "$target" && ./.orchestration/verify.sh --diff-sha)
  report=$(write_evidence "$target" DEMO-2 result.txt "$base_sha" "$diff_sha")

  if "$target/.orchestration/verify.sh" "$report" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"; then
    fail "report with an out-of-scope path was accepted"
  fi
}

test_rejects_edit_after_verification() {
  local target="$TMP_ROOT/stale-hash" base_sha diff_sha report
  create_repo "$target"
  base_sha=$(git -C "$target" rev-parse HEAD)
  printf 'first state\n' >"$target/result.txt"
  diff_sha=$(cd "$target" && ./.orchestration/verify.sh --diff-sha)
  report=$(write_evidence "$target" DEMO-3 result.txt "$base_sha" "$diff_sha")
  printf 'edited after verification\n' >"$target/result.txt"

  if "$target/.orchestration/verify.sh" "$report" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"; then
    fail "report survived an edit after verification"
  fi
}

test_rejects_attempt_mismatch() {
  local target="$TMP_ROOT/attempt-mismatch" base_sha diff_sha report
  create_repo "$target"
  base_sha=$(git -C "$target" rev-parse HEAD)
  printf 'changed\n' >"$target/result.txt"
  diff_sha=$(cd "$target" && ./.orchestration/verify.sh --diff-sha)
  report=$(write_evidence "$target" DEMO-4 result.txt "$base_sha" "$diff_sha")
  perl -pi -e 's/^- Attempt: 1$/- Attempt: 2/' "$report"

  if "$target/.orchestration/verify.sh" "$report" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"; then
    fail "report from a different attempt was accepted"
  fi
}

test_diff_sha_is_worktree_independent() {
  local first="$TMP_ROOT/hash-first" second="$TMP_ROOT/hash-second" first_sha second_sha
  create_repo "$first"
  create_repo "$second"
  printf 'same bytes\n' >"$first/result.txt"
  printf 'same bytes\n' >"$second/result.txt"
  first_sha=$(cd "$first" && ./.orchestration/verify.sh --diff-sha)
  second_sha=$(cd "$second" && ./.orchestration/verify.sh --diff-sha)

  [ "$first_sha" = "$second_sha" ] || fail "identical diffs hash differently across worktrees"
}

test_rejects_missing_acceptance_check() {
  local target="$TMP_ROOT/acceptance-missing" base_sha diff_sha report
  create_repo "$target"
  base_sha=$(git -C "$target" rev-parse HEAD)
  printf 'changed\n' >"$target/result.txt"
  diff_sha=$(cd "$target" && ./.orchestration/verify.sh --diff-sha)
  report=$(write_evidence "$target" DEMO-5 result.txt "$base_sha" "$diff_sha")
  perl -ni -e 'print unless /^- Acceptance check: /' "$report"

  if "$target/.orchestration/verify.sh" "$report" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"; then
    fail "report without an acceptance check was accepted"
  fi
}

test_rejects_acceptance_check_mismatch() {
  local target="$TMP_ROOT/acceptance-mismatch" base_sha diff_sha report
  create_repo "$target"
  base_sha=$(git -C "$target" rev-parse HEAD)
  printf 'changed\n' >"$target/result.txt"
  diff_sha=$(cd "$target" && ./.orchestration/verify.sh --diff-sha)
  report=$(write_evidence "$target" DEMO-6 result.txt "$base_sha" "$diff_sha")
  perl -pi -e 's{^- Acceptance check: .*$}{- Acceptance check: artifact: other.txt}' "$report"

  if "$target/.orchestration/verify.sh" "$report" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"; then
    fail "acceptance check that disagrees with the prompt was accepted"
  fi
}

test_rejects_missing_acceptance_evidence() {
  local target="$TMP_ROOT/acceptance-evidence" base_sha diff_sha report
  create_repo "$target"
  base_sha=$(git -C "$target" rev-parse HEAD)
  printf 'changed\n' >"$target/result.txt"
  diff_sha=$(cd "$target" && ./.orchestration/verify.sh --diff-sha)
  report=$(write_evidence "$target" DEMO-7 result.txt "$base_sha" "$diff_sha")
  perl -pi -e 's{^- Acceptance evidence: .*$}{- Acceptance evidence: }' "$report"

  if "$target/.orchestration/verify.sh" "$report" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"; then
    fail "report without acceptance evidence was accepted"
  fi
}

test_rejects_unobservable_acceptance_artifact() {
  local target="$TMP_ROOT/acceptance-artifact" base_sha diff_sha report
  create_repo "$target"
  base_sha=$(git -C "$target" rev-parse HEAD)
  printf 'changed\n' >"$target/result.txt"
  diff_sha=$(cd "$target" && ./.orchestration/verify.sh --diff-sha)
  report=$(write_evidence "$target" DEMO-8 result.txt "$base_sha" "$diff_sha")
  perl -pi -e 's{^- Acceptance check: .*$}{- Acceptance check: artifact: never-written.txt}' \
    "$report" "$target/.orchestration/prompts/$(basename "$report")"

  if "$target/.orchestration/verify.sh" "$report" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"; then
    fail "acceptance artifact that does not exist was accepted"
  fi
}

test_run_verify_rejects_failing_verify_command() {
  local target="$TMP_ROOT/run-verify-fail" base_sha diff_sha report
  create_repo "$target" false
  base_sha=$(git -C "$target" rev-parse HEAD)
  printf 'changed\n' >"$target/result.txt"
  diff_sha=$(cd "$target" && ./.orchestration/verify.sh --diff-sha)
  report=$(write_evidence "$target" DEMO-9 result.txt "$base_sha" "$diff_sha")

  if ! "$target/.orchestration/verify.sh" "$report" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"; then
    fail "static validation should still pass when only the verify command fails"
  fi
  if "$target/.orchestration/verify.sh" --run-verify "$report" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"; then
    fail "--run-verify accepted a report whose verify command fails"
  fi
}

# Each entry is a verify command that must never reach execution: a bare
# external action, a shell wrapper hiding one, or a destructive command in a
# casing the old denylist missed.
test_run_verify_refuses_external_action() {
  local target base_sha diff_sha report command index=0
  local -a commands=(
    'git push origin main'
    "sh -c 'git push origin main'"
    "bash -c 'git push origin main'"
    "zsh -c 'git push origin main'"
    'eval git push origin main'
    'env GIT_DIR=. git push origin main'
    'xargs git push'
    '"git" push origin main'
    'rm -R somedir'
    'rm -fR somedir'
    'curl https://example.com'
    'npm test | tee out.txt'
    'npm test > out.txt'
    'npm test 2>&1'
    'npm test && git push origin main'
    'npm test; git push origin main'
    'npm test &'
    'npm test $(git push origin main)'
    'npm test `git push origin main`'
    './scripts/sh -c git-push'
    'tools/curl https://example.com'
    'python3 -c import os'
    'node -e process.exit'
    '../outside/verify.sh'
    '/bin/sh -c true'
  )

  for command in "${commands[@]}"; do
    index=$((index + 1))
    target="$TMP_ROOT/run-verify-external-$index"
    create_repo "$target" "$command"
    base_sha=$(git -C "$target" rev-parse HEAD)
    printf 'changed\n' >"$target/result.txt"
    diff_sha=$(cd "$target" && ./.orchestration/verify.sh --diff-sha)
    report=$(write_evidence "$target" "DEMO-10-$index" result.txt "$base_sha" "$diff_sha")

    if "$target/.orchestration/verify.sh" --run-verify "$report" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"; then
      fail "--run-verify executed a command with external effects: $command"
    fi
    grep -q 'refusing to re-run' "$TMP_ROOT/err" || \
      fail "--run-verify did not refuse before executing: $command"
  done
}

test_run_verify_runs_project_local_command() {
  local target="$TMP_ROOT/run-verify-local" base_sha diff_sha report
  create_repo "$target" "./.orchestration/verify.sh --diff-sha"
  base_sha=$(git -C "$target" rev-parse HEAD)
  printf 'changed\n' >"$target/result.txt"
  diff_sha=$(cd "$target" && ./.orchestration/verify.sh --diff-sha)
  report=$(write_evidence "$target" DEMO-12 result.txt "$base_sha" "$diff_sha")

  if ! "$target/.orchestration/verify.sh" --run-verify "$report" 2>"$TMP_ROOT/err"; then
    fail "--run-verify refused an ordinary project-local verify command"
  fi
}

# The documented supported workflow: a repository-local ./verify.sh must still
# run under the capability profile.
test_run_verify_runs_repo_verify_script() {
  local target="$TMP_ROOT/run-verify-script" base_sha diff_sha report
  create_repo "$target" "./verify.sh"
  base_sha=$(git -C "$target" rev-parse HEAD)
  printf 'changed\n' >"$target/result.txt"
  printf '#!/usr/bin/env bash\nprintf "repo verify ran\\n"\n' >"$target/verify.sh"
  chmod +x "$target/verify.sh"
  diff_sha=$(cd "$target" && ./.orchestration/verify.sh --diff-sha)
  report=$(write_evidence "$target" DEMO-13 "result.txt,verify.sh" "$base_sha" "$diff_sha")

  if ! "$target/.orchestration/verify.sh" --run-verify "$report" 2>"$TMP_ROOT/err"; then
    fail "--run-verify refused the documented ./verify.sh command"
  fi
  grep -q 'repo verify ran' "$TMP_ROOT/err" || fail "./verify.sh output was not captured"
}

test_run_verify_accepts_report_after_final_edit() {
  local target="$TMP_ROOT/run-verify-pass" base_sha diff_sha report
  create_repo "$target"
  base_sha=$(git -C "$target" rev-parse HEAD)
  printf 'changed\n' >"$target/result.txt"
  diff_sha=$(cd "$target" && ./.orchestration/verify.sh --diff-sha)
  report=$(write_evidence "$target" DEMO-11 result.txt "$base_sha" "$diff_sha")

  if ! "$target/.orchestration/verify.sh" --run-verify "$report" 2>"$TMP_ROOT/err"; then
    fail "--run-verify rejected a valid report verified after the final edit"
  fi
}

test_accepts_report_for_current_diff
test_rejects_out_of_scope_path
test_rejects_edit_after_verification
test_rejects_attempt_mismatch
test_diff_sha_is_worktree_independent
test_rejects_missing_acceptance_check
test_rejects_acceptance_check_mismatch
test_rejects_missing_acceptance_evidence
test_rejects_unobservable_acceptance_artifact
test_run_verify_rejects_failing_verify_command
test_run_verify_refuses_external_action
test_run_verify_accepts_report_after_final_edit
test_run_verify_runs_project_local_command
test_run_verify_runs_repo_verify_script
printf 'PASS: report verification tests\n'
