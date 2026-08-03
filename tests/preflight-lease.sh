#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-ops-preflight.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

repo="$TMP_ROOT/repo"
mkdir -p "$repo/.orchestration"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
printf '#!/usr/bin/env bash\nprintf ok\n' >"$repo/verify.sh"
chmod +x "$repo/verify.sh"
cp "$ROOT/template/.orchestration/preflight.sh" "$repo/.orchestration/preflight.sh"
cp "$ROOT/template/.orchestration/lease.sh" "$repo/.orchestration/lease.sh"
chmod +x "$repo/.orchestration"/*.sh

output=$(cd "$repo" && ./.orchestration/preflight.sh --verify-cmd ./verify.sh)
grep -Fq 'preflight: ok' <<<"$output"

acquired=$(cd "$repo" && ./.orchestration/lease.sh acquire --dispatch DEMO-1)
grep -Fq 'lease: acquired' <<<"$acquired"
if (cd "$repo" && ./.orchestration/lease.sh acquire --dispatch DEMO-2 >/dev/null 2>&1); then
  echo 'second lease acquisition unexpectedly succeeded' >&2
  exit 1
fi
status=$(cd "$repo" && ./.orchestration/lease.sh status 2>&1 || true)
grep -Fq 'lease:' <<<"$status"
cd "$repo" && ./.orchestration/lease.sh release --force >/dev/null

printf 'PASS: preflight and lease\n'
