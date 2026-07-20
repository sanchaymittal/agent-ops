#!/usr/bin/env bash
# Fail before a worker loads task context, not after. Every check here is local:
# no network, no model API, nothing that can pass for the wrong reason.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

# Structured failure: `blocked: <class>: <detail>`, class in capability|task|lease.
# capability = the environment cannot run the task; task = the dispatch itself is
# wrong; lease = another writer owns this worktree.
fail() {
  printf 'blocked: %s: %s\n' "$1" "$2" >&2
  exit 1
}

usage='usage: '$0' --verify-cmd CMD [--base-sha SHA] [--cli NAME] [--role NAME]'

verify_cmd=''
base_sha=''
cli=''
role=''

while [ $# -gt 0 ]; do
  case $1 in
    --verify-cmd) verify_cmd=${2:-}; shift 2 || fail task "$usage" ;;
    --base-sha) base_sha=${2:-}; shift 2 || fail task "$usage" ;;
    --cli) cli=${2:-}; shift 2 || fail task "$usage" ;;
    --role) role=${2:-}; shift 2 || fail task "$usage" ;;
    *) fail task "$usage" ;;
  esac
done

root=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null) ||
  fail capability "not inside a Git repository or worktree"
root=$(cd "$root" && pwd -P)

if [ -n "$base_sha" ]; then
  git -C "$root" cat-file -e "$base_sha^{commit}" 2>/dev/null ||
    fail task "base SHA is not a commit in this repository: $base_sha"
  head_sha=$(git -C "$root" rev-parse HEAD)
  [ "$head_sha" = "$(git -C "$root" rev-parse "$base_sha")" ] ||
    fail task "worktree HEAD $head_sha is not the dispatch base SHA $base_sha"
fi

[ -n "$verify_cmd" ] || fail task "--verify-cmd is required and must not be empty"
program=${verify_cmd%%[[:space:]]*}
case $program in
  */*)
    [ -x "$root/$program" ] || [ -x "$program" ] ||
      fail capability "verify command is not executable: $program" ;;
  *)
    command -v -- "$program" >/dev/null 2>&1 ||
      fail capability "verify command not on PATH: $program" ;;
esac

if [ -n "$cli" ]; then
  command -v -- "$cli" >/dev/null 2>&1 || fail capability "CLI not on PATH: $cli"
fi

# The roster is the local role files, not the docs table — a role that cannot be
# selected by the CLI is the dispatch defect this catches.
if [ -n "$role" ]; then
  case $role in
    */*|.*) fail task "role must be a roster name, not a path: $role" ;;
  esac
  [ -f "$root/.claude/agents/$role.md" ] ||
    fail task "role is not in the local roster: $role"
fi

# One capture, so a release between two calls cannot report a free lease as
# blocked; lease.sh already prefixes its own output, and `fail` adds the class.
lease_status=$("$SCRIPT_DIR/lease.sh" status 2>&1) ||
  fail lease "${lease_status#lease: }"

printf 'preflight: ok (root %s)\n' "$root"
