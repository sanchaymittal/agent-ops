#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)

bash -n "$ROOT/init.sh" "$ROOT/verify.sh" \
  "$ROOT/template/.orchestration/preflight.sh" \
  "$ROOT/template/.orchestration/lease.sh" \
  "$ROOT/tests/init.sh" "$ROOT/tests/preflight-lease.sh" "$ROOT/tests/burn.sh"

python3 -m py_compile "$ROOT/template/.orchestration/burn.py" \
  "$ROOT/template/.orchestration/installer.py"

"$ROOT/tests/init.sh"
"$ROOT/tests/preflight-lease.sh"
"$ROOT/tests/burn.sh"

while IFS= read -r index; do
  lines=$(wc -l <"$index" | tr -d ' ')
  if [ "$lines" -gt 40 ]; then
    printf 'index exceeds 40 lines: %s (%s)\n' "${index#"$ROOT"/}" "$lines" >&2
    exit 1
  fi
done < <(find "$ROOT/template/docs" -type f -name index.md | LC_ALL=C sort)

for required in \
  template/AGENTS.md \
  template/.orchestration/README.md \
  template/.orchestration/preflight.sh \
  template/.orchestration/lease.sh \
  template/.orchestration/burn.py \
  template/.orchestration/installer.py; do
  [ -f "$ROOT/$required" ] || { printf 'missing required template file: %s\n' "$required" >&2; exit 1; }
done

if find "$ROOT/template" -type f \( -path '*/.agents/*' -o -path '*/.claude/agents/*' -o -path '*/.codex/agents/*' -o -path '*/.opencode/agents/*' \) -print -quit | grep -q .; then
  printf 'generic role roster found in template; repository-local copies are intentionally not maintained\n' >&2
  exit 1
fi

git -C "$ROOT" diff --check
printf 'PASS: repository verification\n'
