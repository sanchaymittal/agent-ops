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

# A window literal in shipped text is copied and generalized to every wait,
# regardless of the prose around it -- that is how a measured coordinator ended
# up polling at 60s against 15-60 minute tasks. Prose can restate the floor;
# only a check keeps a shorter number from being shipped next to it. burn.py is
# exempt: it is the file that defines the floor and tests numbers below it.
# Scoped to the shipped payload. This repo's own prompts/ and reports/ are
# immutable dispatch history: the handoff that diagnosed this failure quotes
# the 60s literal as evidence, and rewriting history to satisfy a lint is a
# worse trade than leaving the past on record.
# grep exits 1 for "no matches", which is the clean case, and 2+ for a real
# error. Collapsing both into `|| true` would turn an unreadable directory into
# a silent pass -- the gate reporting nothing wrong because it read nothing.
# `[[:space:]]` rather than a literal space: a tab is valid shell between a
# flag and its value, and would otherwise walk straight past the gate.
window_hits=$(grep -rnoE --binary-files=without-match -- '--timeout-ms[=[:space:]]+[0-9]+' "$ROOT/template") \
  || [ $? -eq 1 ] \
  || { printf 'window gate: grep failed scanning template/\n' >&2; exit 1; }
bad_windows=$(printf '%s\n' "$window_hits" \
  | grep -v -e '^$' -e '/burn\.py:' -e '/__pycache__/' \
  | awk -F'[=[:space:]]' '{ n = $NF + 0; if (n < 900000) print }') || true
[ -z "$bad_windows" ] || {
  printf 'supervision window below the 15-minute floor in shipped text:\n%s\n' "$bad_windows" >&2
  exit 1
}

# Same failure as the window gate, one flag over: a wait that consumes the event
# it returns. Delivery is exactly-once, so an abandoned waiter -- which is what a
# harness yield shorter than the window leaves behind on every iteration -- eats
# the completion the coordinator is still waiting for. `--peek` leaves it unread.
# Exemptions match the window gate for the same reasons: burn.py quotes the
# un-peeked form as the defect it measures.
peek_hits=$(grep -rnE --binary-files=without-match -- 'orca[[:space:]]+orchestration[[:space:]]+check.*--wait' "$ROOT/template") \
  || [ $? -eq 1 ] \
  || { printf 'peek gate: grep failed scanning template/\n' >&2; exit 1; }
bad_peek=$(printf '%s\n' "$peek_hits" \
  | grep -v -e '^$' -e '/burn\.py:' -e '/__pycache__/' \
  | grep -v -- '--peek') || true
[ -z "$bad_peek" ] || {
  printf 'consuming check --wait (no --peek) in shipped text:\n%s\n' "$bad_peek" >&2
  exit 1
}

git -C "$ROOT" diff --check
printf 'PASS: repository verification\n'
