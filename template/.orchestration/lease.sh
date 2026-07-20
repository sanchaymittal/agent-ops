#!/usr/bin/env bash
# One writer per worktree. `mkdir` is the lock: it is atomic on every POSIX
# filesystem and fails when the directory exists, so a losing acquirer never
# touches the winner's record.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

die() {
  printf 'lease: %s\n' "$1" >&2
  exit 1
}

repo_root() {
  git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || die "not inside a Git repository"
}

ROOT=$(cd "$(repo_root)" && pwd -P)
LEASE="$ROOT/.orchestration/.lease"
META="$LEASE/meta"

# A meta that is missing *or* unreadable is a crash-window lease, not an error:
# every caller must still be able to read, report, and (with --force) clear it.
# -r subsumes -f; a mode-600 meta written under another UID is the realistic case.
meta_field() {
  [ -r "$META" ] || return 0
  sed -n "s/^$1=//p" "$META" 2>/dev/null | head -n 1
}

# Only a PID we can positively prove is gone counts as dead. `kill -0` also
# fails with EPERM for a live process owned by another user, so an unusable
# answer falls through to `ps -p`, and an unusable `ps` means "assume live".
pid_live() {
  local pid=$1 rc
  case $pid in ''|*[!0-9]*) return 0 ;; esac
  kill -0 "$pid" 2>/dev/null && return 0
  ps -p "$pid" >/dev/null 2>&1 && return 0
  rc=$?
  [ "$rc" -eq 1 ] && return 1
  return 0
}

# A dead PID makes a lease stale, not free: breaking it still needs --force so
# a live worker is never evicted by a wrong guess about its process.
lease_summary() {
  local owner dispatch pid acquired note=''
  owner=$(meta_field owner)
  dispatch=$(meta_field dispatch)
  pid=$(meta_field pid)
  acquired=$(meta_field acquired)
  if ! pid_live "$pid"; then
    note=' [stale: pid not running]'
  fi
  printf 'held by %s (dispatch %s, pid %s, since %s)%s' \
    "${owner:-unknown}" "${dispatch:-unknown}" "${pid:-unknown}" "${acquired:-unknown}" "$note"
}

acquire() {
  local dispatch=$1 owner=$2
  if ! mkdir "$LEASE" 2>/dev/null; then
    [ -d "$LEASE" ] || die "cannot create lease directory: $LEASE"
    printf 'blocked: lease: %s\n' "$(lease_summary)" >&2
    exit 1
  fi
  {
    printf 'dispatch=%s\n' "$dispatch"
    printf 'owner=%s\n' "$owner"
    printf 'pid=%s\n' "$LEASE_PID"
    printf 'acquired=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  } >"$META"
  printf 'lease: acquired by %s (dispatch %s)\n' "$owner" "$dispatch"
}

release() {
  local owner=$1 force=$2 held
  if [ ! -d "$LEASE" ]; then
    printf 'lease: no lease held\n'
    return 0
  fi
  held=$(meta_field owner)
  if [ "$force" != 1 ] && [ "$held" != "$owner" ]; then
    printf 'blocked: lease: %s; --force required to break it\n' "$(lease_summary)" >&2
    exit 1
  fi
  rm -rf -- "$LEASE"
  printf 'lease: released (owner %s)\n' "${held:-unknown}"
}

status() {
  if [ ! -d "$LEASE" ]; then
    printf 'lease: available\n'
    return 0
  fi
  printf 'lease: %s\n' "$(lease_summary)"
  exit 1
}

usage='usage: '$0' acquire --dispatch ID [--owner NAME] | release [--owner NAME] [--force] | status'

command=${1:-}
shift || true
dispatch=''
owner=${LEASE_OWNER:-${USER:-unknown}}
force=0
nl='
'

while [ $# -gt 0 ]; do
  case $1 in
    --dispatch) dispatch=${2:-}; shift 2 || die "$usage" ;;
    --owner) owner=${2:-}; shift 2 || die "$usage" ;;
    --force) force=1; shift ;;
    *) die "$usage" ;;
  esac
done

[ -n "$owner" ] || die "--owner must not be empty"

# The record is line-oriented: a newline in a caller value would forge extra
# fields (a second pid= line wins over the real one), so reject it outright.
case $owner in *"$nl"*) die "--owner must not contain a newline" ;; esac
case $dispatch in *"$nl"*) die "--dispatch must not contain a newline" ;; esac

# The lease outlives lease.sh itself, so record the caller's process (the worker
# or coordinator shell), not this short-lived one. LEASE_PID overrides for
# callers invoked through a transient wrapper.
LEASE_PID=${LEASE_PID:-$PPID}
case $LEASE_PID in ''|*[!0-9]*) die "LEASE_PID must be a numeric process id" ;; esac

case $command in
  acquire)
    [ -n "$dispatch" ] || die "acquire requires --dispatch ID"
    acquire "$dispatch" "$owner"
    ;;
  release) release "$owner" "$force" ;;
  status) status ;;
  *) die "$usage" ;;
esac
