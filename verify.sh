#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-ops-verify.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

bash -n "$ROOT/init.sh" "$ROOT/verify.sh" "$ROOT/template/.orchestration/verify.sh" \
  "$ROOT/template/.orchestration/preflight.sh" "$ROOT/template/.orchestration/lease.sh" \
  "$ROOT/tests/init.sh" "$ROOT/tests/verify-report.sh" "$ROOT/tests/preflight-lease.sh" \
  "$ROOT/tests/burn.sh"

"$ROOT/tests/init.sh"
"$ROOT/tests/verify-report.sh"
"$ROOT/tests/preflight-lease.sh"
"$ROOT/tests/burn.sh"

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

# A role is dispatched by the name it declares, so that name must be the slug
# the docs advertise. Frontmatter drift here silently breaks `--agent <role>`.
# .agents/ is omitted: the parity check above already proves it byte-identical
# to .claude/. Only the first frontmatter block counts — a `name:` in the body
# is prose, not a declaration.
for role_file in "$ROOT"/template/.claude/agents/*.md "$ROOT"/template/.opencode/agents/*.md; do
  slug=$(basename "$role_file" .md)
  declared=$(awk '/^---$/ { block++; next } block == 1 && /^name: / { sub(/^name: /, ""); print; exit }' "$role_file")
  [ "$declared" = "$slug" ] || {
    printf 'roster name drift: %s declares %s\n' "${role_file#"$ROOT"/}" "${declared:-<none>}" >&2
    exit 1
  }
done

for role_file in "$ROOT"/template/.codex/agents/*.toml; do
  slug=$(basename "$role_file" .toml)
  declared=$(awk -F'"' '/^name = /{print $2; exit}' "$role_file")
  [ "$declared" = "$slug" ] || {
    printf 'roster name drift: %s declares %s\n' "${role_file#"$ROOT"/}" "${declared:-<none>}" >&2
    exit 1
  }
done

git -C "$ROOT" diff --check
printf 'PASS: repository verification\n'
