#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

die() {
  printf 'invalid report: %s\n' "$1" >&2
  exit 1
}

repo_root() {
  git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || die "not inside a Git repository"
}

diff_sha() {
  local root path content_sha
  root=$(cd "$(repo_root)" && pwd -P)

  {
    git -C "$root" diff --binary --no-ext-diff HEAD -- . \
      ':(exclude).orchestration/prompts/**' \
      ':(exclude).orchestration/reports/**'
    git -C "$root" ls-files --others --exclude-standard | LC_ALL=C sort | while IFS= read -r path; do
      case $path in
        .orchestration/prompts/*|.orchestration/reports/*) continue ;;
      esac
      printf 'untracked %s\n' "$path"
      content_sha=$(shasum -a 256 -- "$root/$path" | awk '{print $1}')
      printf '%s\n' "$content_sha"
    done
  } | shasum -a 256 | awk '{print $1}'
}

changed_paths() {
  local root path
  root=$(cd "$(repo_root)" && pwd -P)
  {
    git -C "$root" diff --name-only HEAD -- . \
      ':(exclude).orchestration/prompts/**' \
      ':(exclude).orchestration/reports/**'
    git -C "$root" ls-files --others --exclude-standard
  } | while IFS= read -r path; do
    case $path in
      .orchestration/prompts/*|.orchestration/reports/*) continue ;;
    esac
    printf '%s\n' "$path"
  done | LC_ALL=C sort -u
}

path_is_allowed() {
  local path=$1 allowed=$2 pattern prefix
  local -a patterns
  IFS=',' read -r -a patterns <<<"$allowed"

  for pattern in "${patterns[@]}"; do
    pattern=${pattern#"${pattern%%[![:space:]]*}"}
    pattern=${pattern%"${pattern##*[![:space:]]}"}
    case $pattern in
      ''|/*|../*|*/../*|*/..) die "invalid allowed path: $pattern" ;;
      *'/**')
        prefix=${pattern%/**}
        if [ "$path" = "$prefix" ] || [[ $path == "$prefix/"* ]]; then
          return 0
        fi
        ;;
      *'*'*|*'?'*|*'['*) die "only exact paths and directory/** prefixes are supported: $pattern" ;;
      *) [ "$path" = "$pattern" ] && return 0 ;;
    esac
  done
  return 1
}

verify_scope() {
  local allowed=$1 path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    path_is_allowed "$path" "$allowed" || die "changed path is outside prompt scope: $path"
  done < <(changed_paths)
}

field() {
  local file=$1 label=$2
  sed -n "s/^- ${label}: //p" "$file" | head -n 1
}

require_field() {
  local file=$1 label=$2 value
  value=$(field "$file" "$label")
  [ -n "$value" ] || die "$file is missing '$label'"
  if printf '%s\n' "$value" | grep -Eq '^<[A-Z_]+>$'; then
    die "$file has unresolved '$label' placeholder"
  fi
  printf '%s' "$value"
}

require_heading() {
  local file=$1 heading=$2
  grep -Fxq "## $heading" "$file" || die "$file is missing '## $heading'"
}

# Acceptance checks are either an executable command or an observable artifact.
# Anything else is rejected rather than guessed at.
verify_acceptance() {
  local root=$1 check=$2 path
  case $check in
    'run: '*)
      [ -n "${check#run: }" ] || die "Acceptance check 'run:' has no command"
      ;;
    'artifact: '*)
      path=${check#artifact: }
      case $path in
        ''|/*|../*|*/../*|*/..) die "Acceptance check artifact must be a worktree-relative path: $path" ;;
      esac
      [ -e "$root/$path" ] || die "Acceptance check artifact does not exist: $path"
      ;;
    *) die "Acceptance check must start with 'run: ' or 'artifact: '" ;;
  esac
}

# Fail-closed capability profile for the re-run command. Three rules, in order,
# and a command must satisfy all three:
#
#   1. Character profile. Only [alnum] and space . _ / = : @ + - may appear.
#      Every shell composition character is therefore absent by construction:
#      pipes, `;`/`&&`/`||` lists, `&` backgrounding, `<`/`>` redirects,
#      `$(...)`/`` ` `` substitution, `~`/`*`/`?` expansion, and both quote
#      styles. Nothing can be escaped or quoted back in.
#   2. Program shape. The first word must be a worktree-relative path
#      (`./x`, `dir/x`, never absolute, never containing `..`) or a bare name
#      on VERIFY_RUNNERS. Nothing else runs.
#   3. Capability deny set. No word may have a basename in VERIFY_DENIED —
#      shell/interpreter wrappers, privilege and exec helpers, network
#      utilities, and destructive utilities — regardless of path or shape.
#      This is what stops `./sh`, `tools/curl`, and `rm -R` even though rule 2
#      would accept their shape. It applies to every word, not just the
#      program: only argv[0] is executed, so an argument match refuses a
#      command that would have been inert (`make watch`). That is deliberate —
#      fail closed, and never silently accept a command that reads as an
#      external action.
#
# The command is then split on whitespace and executed as argv. No shell
# interprets the recorded string at any point, so rule 1 is the only parser.
#
# ponytail: arguments of an allowed runner are not semantically inspected — an
# allowlisted runner told to do something external (`make deploy`) still runs.
# Per-runner argument profiles are the upgrade path.
VERIFY_RUNNERS='make npm pnpm yarn cargo go mvn gradle pytest tox rake bundle printf echo true false'

VERIFY_DENIED='sh bash zsh ksh dash csh tcsh fish ash busybox
env eval exec command source xargs sudo doas su chroot nohup setsid script
timeout time watch nice ionice stdbuf strace ltrace open osascript
perl python python2 python3 ruby node deno bun npx irb php lua tclsh expect awk gawk sed
curl wget nc ncat netcat telnet ftp sftp ssh scp rsync git hg svn docker kubectl aws gcloud az
rm rmdir unlink mv dd shred srm mkfs fdisk diskutil chmod chown chgrp chflags
kill killall pkill halt reboot shutdown launchctl systemctl crontab at'

require_local_verify_command() {
  local command=$1 program word base denied
  denied=" $(printf '%s' "$VERIFY_DENIED" | tr '\n' ' ') "
  if printf '%s' "$command" | LC_ALL=C grep -q '[^[:alnum:][:space:]._/=:@+-]'; then
    die "refusing to re-run a verify command containing shell metacharacters: $command"
  fi

  read -r -a VERIFY_ARGV <<<"$command"
  [ ${#VERIFY_ARGV[@]} -gt 0 ] || die "refusing to re-run an empty verify command"

  for word in "${VERIFY_ARGV[@]}"; do
    base=${word##*/}
    case $denied in
      *" $base "*) die "refusing to re-run a verify command using a denied capability ($base): $command" ;;
    esac
  done

  program=${VERIFY_ARGV[0]}
  case $program in
    /*) die "refusing to re-run a verify command outside the worktree: $command" ;;
    ..|../*|*/..|*/../*) die "refusing to re-run a verify command outside the worktree: $command" ;;
    */*) return 0 ;;
  esac
  case " $VERIFY_RUNNERS " in
    *" $program "*) return 0 ;;
  esac
  die "refusing to re-run a verify command that is not a project-local runner: $command"
}

# Re-runs the recorded verify command at the repository root, captures a
# byte-bounded transcript, and fails on any non-zero exit.
run_verify_command() {
  local root=$1 command=$2 log status
  require_local_verify_command "$command"
  log=$(mktemp "${TMPDIR:-/tmp}/agent-ops-verify-log.XXXXXX")
  status=0
  ( cd "$root" && "${VERIFY_ARGV[@]}" ) >"$log" 2>&1 || status=$?
  printf '%s\n' "--- verify command output (first 32768 bytes) ---" >&2
  head -c 32768 "$log" >&2
  printf '\n%s\n' "--- exit $status ---" >&2
  rm -f "$log"
  [ "$status" -eq 0 ] || die "verify command failed with exit $status: $command"
}

verify_report() {
  local report=$1 run_verify=${2:-0} root relative basename prompt outcome
  local task_id prompt_task attempt prompt_attempt role prompt_role base_sha prompt_base
  local verify_command prompt_verify verify_exit expected_sha actual_sha verified_at
  local acceptance prompt_acceptance
  local risk_tier prompt_risk_tier
  local allowed_paths prompt_allowed_paths

  root=$(cd "$(repo_root)" && pwd -P)
  report=$(cd "$(dirname "$report")" && pwd -P)/$(basename "$report")
  case $report in
    "$root"/.orchestration/reports/*.md) ;;
    *) die "report must be under .orchestration/reports" ;;
  esac
  [ -f "$report" ] || die "report does not exist: $report"
  basename=$(basename "$report")
  [ "$basename" != TEMPLATE.md ] || die "TEMPLATE.md is not a task report"
  prompt="$root/.orchestration/prompts/$basename"
  [ -f "$prompt" ] || die "matching prompt does not exist: $prompt"

  outcome=$(awk 'NF { print; exit }' "$report")
  case $outcome in
    done|blocked:\ missing\ *|blocked:\ decision:\ *) ;;
    *) die "first non-empty line must be done or a supported blocked outcome" ;;
  esac

  task_id=$(require_field "$report" "Task ID")
  prompt_task=$(require_field "$prompt" "Task ID")
  [ "$task_id" = "$prompt_task" ] || die "Task ID does not match prompt"
  attempt=$(require_field "$report" "Attempt")
  prompt_attempt=$(require_field "$prompt" "Attempt")
  [ "$attempt" = "$prompt_attempt" ] || die "Attempt does not match prompt"
  role=$(require_field "$report" "Role")
  prompt_role=$(require_field "$prompt" "Role")
  [ "$role" = "$prompt_role" ] || die "Role does not match prompt"
  base_sha=$(require_field "$report" "Base SHA")
  prompt_base=$(require_field "$prompt" "Base SHA")
  [ "$base_sha" = "$prompt_base" ] || die "Base SHA does not match prompt"
  git -C "$root" cat-file -e "$base_sha^{commit}" 2>/dev/null || die "Base SHA is not a commit"
  [ "$(git -C "$root" rev-parse HEAD)" = "$base_sha" ] || die "worktree HEAD has moved from the prompt Base SHA"
  risk_tier=$(require_field "$report" "Risk tier")
  prompt_risk_tier=$(require_field "$prompt" "Risk tier")
  [ "$risk_tier" = "$prompt_risk_tier" ] || die "Risk tier does not match prompt"
  case $risk_tier in
    low|medium|high) ;;
    *) die "Risk tier must be low, medium, or high" ;;
  esac
  allowed_paths=$(require_field "$report" "Allowed paths")
  prompt_allowed_paths=$(require_field "$prompt" "Allowed paths")
  [ "$allowed_paths" = "$prompt_allowed_paths" ] || die "Allowed paths do not match prompt"
  verify_scope "$allowed_paths"

  for heading in "Files changed" "Commands run" "Failures" "Deviations" "Remaining risks"; do
    require_heading "$report" "$heading"
  done

  if [ "$outcome" = done ]; then
    verify_command=$(require_field "$report" "Verify command")
    prompt_verify=$(require_field "$prompt" "Verify command")
    [ "$verify_command" = "$prompt_verify" ] || die "Verify command does not match prompt"
    acceptance=$(require_field "$report" "Acceptance check")
    prompt_acceptance=$(require_field "$prompt" "Acceptance check")
    [ "$acceptance" = "$prompt_acceptance" ] || die "Acceptance check does not match prompt"
    verify_acceptance "$root" "$acceptance"
    require_field "$report" "Acceptance evidence" >/dev/null
    verify_exit=$(require_field "$report" "Verify exit")
    [ "$verify_exit" = 0 ] || die "Verify exit is not zero"
    verified_at=$(require_field "$report" "Verified at")
    [ -n "$verified_at" ] || die "Verified at is blank"
    expected_sha=$(require_field "$report" "Final diff SHA")
    actual_sha=$(diff_sha)
    [ "$expected_sha" = "$actual_sha" ] || die "Final diff SHA does not match the current worktree"
    # Re-run last: the recorded state is already proven to be the final state.
    if [ "$run_verify" = 1 ]; then
      run_verify_command "$root" "$verify_command"
    fi
  fi

  printf 'valid report: %s\n' "${report#"$root"/}"
}

usage='usage: '$0' --diff-sha | [--run-verify] REPORT.md'

case ${1:-} in
  --diff-sha)
    [ $# -eq 1 ] || die "$usage"
    diff_sha
    ;;
  --run-verify)
    [ $# -eq 2 ] || die "$usage"
    verify_report "$2" 1
    ;;
  ''|-*) die "$usage" ;;
  *)
    [ $# -eq 1 ] || die "$usage"
    verify_report "$1" 0
    ;;
esac
