#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-ops-init.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

target="$TMP_ROOT/target"
mkdir -p "$target"
"$ROOT/init.sh" "$target" demo "printf verified" >/dev/null

[ -L "$target/CLAUDE.md" ] || { echo 'CLAUDE.md symlink missing' >&2; exit 1; }
[ -x "$target/.orchestration/preflight.sh" ] || { echo 'preflight missing' >&2; exit 1; }
[ -x "$target/.orchestration/lease.sh" ] || { echo 'lease missing' >&2; exit 1; }
[ -f "$target/.orchestration/burn.py" ] || { echo 'burn diagnostic missing' >&2; exit 1; }
[ ! -d "$target/.claude/agents" ] || { echo 'generic Claude roster was installed' >&2; exit 1; }
grep -Fq -- 'printf verified' "$target/AGENTS.md" || { echo 'verify command was not rendered' >&2; exit 1; }

printf 'PASS: init\n'
