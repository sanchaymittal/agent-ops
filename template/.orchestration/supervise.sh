#!/usr/bin/env bash
# Provider-neutral entry point for durable supervision and the bounded fallback.
set -euo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
usage() {
  printf 'usage: %s runtime|fallback|policy ...\n' "$0" >&2
  exit 2
}

command=${1:-}
shift || true
case "$command" in
  runtime)
    exec python3 "$DIR/supervisor.py" "$@"
    ;;
  fallback)
    exec python3 "$DIR/fallback-supervisor.py" "$@"
    ;;
  policy)
    active=${1:-}
    candidate=${2:-}
    [ -n "$active" ] && [ -n "$candidate" ] || usage
    if [ -e "$active" ]; then
      case "$candidate" in
        *\;*|*\|*|*\&*|*\`*|*'orca terminal'*|*'orca status'*|*'terminal read'*)
          printf 'blocked: supervision: command policy rejects inspection while wait is active\n' >&2
          exit 1
          ;;
        *'orca orchestration check --wait'*'--peek'*) ;;
        *)
          printf 'blocked: supervision: command policy rejects inspection while wait is active\n' >&2
          exit 1
          ;;
      esac
    fi
    printf 'allowed: %s\n' "$candidate"
    ;;
  *) usage ;;
esac
