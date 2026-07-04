#!/usr/bin/env bash
# Stamp the agent-ops operating system into a target repo.
set -euo pipefail

usage() {
  echo "usage: $0 TARGET_DIR PROJECT_NAME LINEAR_TEAM LINEAR_PROJECT ISSUE_PREFIX [VERIFY_CMD]" >&2
  echo "example: $0 ~/github/myapp myapp sanchay myapp MYA 'npm run verify'" >&2
  exit 1
}

[ $# -ge 5 ] || usage
TARGET=$1
export T_NAME=$2 T_TEAM=$3 T_PROJECT=$4 T_PREFIX=$5 T_VERIFY=${6:-npm run verify}
SRC="$(cd "$(dirname "$0")/template" && pwd)"

if [ -e "$TARGET/AGENTS.md" ]; then
  echo "refusing: $TARGET/AGENTS.md already exists" >&2
  exit 1
fi
mkdir -p "$TARGET"

# copy payload (dotdirs included); never clobbers files outside the payload
tar -C "$SRC" -cf - . | tar -C "$TARGET" -xf -

# substitute placeholders in payload markdown (perl for BSD/GNU portability)
find "$TARGET/docs" "$TARGET/.orchestration" "$TARGET/AGENTS.md" -type f -name '*.md' -print0 |
  xargs -0 perl -pi -e '
    s/\{\{PROJECT_NAME\}\}/$ENV{T_NAME}/g;
    s/\{\{LINEAR_TEAM\}\}/$ENV{T_TEAM}/g;
    s/\{\{LINEAR_PROJECT\}\}/$ENV{T_PROJECT}/g;
    s/\{\{ISSUE_PREFIX\}\}/$ENV{T_PREFIX}/g;
    s/\{\{VERIFY_CMD\}\}/$ENV{T_VERIFY}/g;
  '

ln -s AGENTS.md "$TARGET/CLAUDE.md"

echo "done: $TARGET"
echo "next:"
echo "  1. AGENTS.md — fill both TODO(project) blocks (description, layout table)"
echo "  2. docs/gates/index.md — one row per human-provisioned dependency"
echo "  3. ensure '$T_VERIFY' exists and is green"
echo "  4. commit; create Linear team '$T_TEAM' / project '$T_PROJECT' if missing"
