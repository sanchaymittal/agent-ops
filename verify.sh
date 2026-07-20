#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-ops-verify.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

bash -n "$ROOT/init.sh" "$ROOT/verify.sh" "$ROOT/template/.orchestration/verify.sh" \
  "$ROOT/tests/init.sh" "$ROOT/tests/verify-report.sh"

"$ROOT/tests/init.sh"
"$ROOT/tests/verify-report.sh"

while IFS= read -r index; do
  lines=$(wc -l <"$index" | tr -d ' ')
  if [ "$lines" -gt 40 ]; then
    printf 'index exceeds 40 lines: %s (%s)\n' "${index#"$ROOT"/}" "$lines" >&2
    exit 1
  fi
done < <(find "$ROOT/template/docs" -type f -name index.md | LC_ALL=C sort)

for claude_role in "$ROOT"/template/.claude/agents/*.md; do
  role=$(basename "$claude_role")
  cmp -s "$claude_role" "$ROOT/template/.agents/agents/$role" || {
    printf 'role drift: .claude/agents/%s != .agents/agents/%s\n' "$role" "$role" >&2
    exit 1
  }
  awk 'seen || /^# / { seen=1; if ($0 != "---") print }' "$claude_role" >"$TMP_ROOT/claude-$role"
  awk 'seen || /^# / { seen=1; if ($0 != "---") print }' \
    "$ROOT/template/.opencode/agents/$role" >"$TMP_ROOT/opencode-$role"
  cmp -s "$TMP_ROOT/claude-$role" "$TMP_ROOT/opencode-$role" || {
    printf 'role body drift: .claude/agents/%s != .opencode/agents/%s\n' "$role" "$role" >&2
    exit 1
  }
done

git -C "$ROOT" diff --check
printf 'PASS: repository verification\n'
