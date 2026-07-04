#!/usr/bin/env bash
# Stamp the agent-ops operating system into a target repo.
set -euo pipefail

usage() {
  echo "usage: $0 TARGET_DIR PROJECT_NAME ISSUE_PREFIX [VERIFY_CMD]" >&2
  echo "example: $0 ~/github/example-app example-app EX 'npm run verify'" >&2
  echo "linear: LINEAR_TEAM=eng LINEAR_PROJECT=example-app $0 ~/github/example-app example-app EX 'npm run verify'" >&2
  exit 1
}

[ $# -ge 3 ] && [ $# -le 4 ] || usage
TARGET=$1
T_PREFIX=$3
T_PREFIX_LOWER=$(printf '%s' "$T_PREFIX" | tr '[:upper:]' '[:lower:]')
T_VERIFY=${4:-npm run verify}

if [ -n "${LINEAR_TEAM:-}" ] || [ -n "${LINEAR_PROJECT:-}" ]; then
  if [ -z "${LINEAR_TEAM:-}" ] || [ -z "${LINEAR_PROJECT:-}" ]; then
    echo "refusing: set both LINEAR_TEAM and LINEAR_PROJECT, or neither" >&2
    exit 1
  fi
  T_TRACKER_NAME="Linear"
  T_TRACKER_DETAILS="Linear team \`$LINEAR_TEAM\`, project \`$LINEAR_PROJECT\`, issues \`$T_PREFIX-xx\`"
  T_TRACKER_UPDATE="update Linear"
else
  T_TRACKER_NAME="project issue tracker"
  T_TRACKER_DETAILS="issues \`$T_PREFIX-xx\` in the project's chosen tracker"
  T_TRACKER_UPDATE="update the issue tracker"
fi

export T_NAME=$2 T_PREFIX T_PREFIX_LOWER T_VERIFY T_TRACKER_NAME T_TRACKER_DETAILS T_TRACKER_UPDATE
SRC="$(cd "$(dirname "$0")/template" && pwd)"

mkdir -p "$TARGET"

conflicts=()
while IFS= read -r -d '' rel; do
  rel=${rel#./}
  if [ "$rel" != "." ] && [ -e "$TARGET/$rel" ] && [ ! -d "$TARGET/$rel" ]; then
    conflicts+=("$rel")
  fi
done < <(cd "$SRC" && find . -name .DS_Store -prune -o -type d -print0)

while IFS= read -r -d '' rel; do
  rel=${rel#./}
  if [ -e "$TARGET/$rel" ] || [ -L "$TARGET/$rel" ]; then
    conflicts+=("$rel")
  fi
done < <(cd "$SRC" && find . -name .DS_Store -prune -o -type f -print0)

if [ -e "$TARGET/CLAUDE.md" ] || [ -L "$TARGET/CLAUDE.md" ]; then
  conflicts+=("CLAUDE.md")
fi

if [ ${#conflicts[@]} -gt 0 ]; then
  echo "refusing: target already has managed path(s)" >&2
  printf '  %s\n' "${conflicts[@]}" >&2
  exit 1
fi

# copy payload (dotdirs included); managed-file conflicts were checked above
tar -C "$SRC" --exclude='.DS_Store' -cf - . | tar -C "$TARGET" -xf -

# substitute placeholders in payload markdown (perl for BSD/GNU portability)
find "$TARGET/docs" "$TARGET/.orchestration" "$TARGET/AGENTS.md" -type f -name '*.md' -print0 |
  xargs -0 perl -pi -e '
    s/\{\{PROJECT_NAME\}\}/$ENV{T_NAME}/g;
    s/\{\{TASK_TRACKER_NAME\}\}/$ENV{T_TRACKER_NAME}/g;
    s/\{\{TASK_TRACKER_DETAILS\}\}/$ENV{T_TRACKER_DETAILS}/g;
    s/\{\{TASK_TRACKER_UPDATE\}\}/$ENV{T_TRACKER_UPDATE}/g;
    s/\{\{ISSUE_PREFIX\}\}/$ENV{T_PREFIX}/g;
    s/\{\{ISSUE_PREFIX_LOWER\}\}/$ENV{T_PREFIX_LOWER}/g;
    s/\{\{VERIFY_CMD\}\}/$ENV{T_VERIFY}/g;
  '

ln -s AGENTS.md "$TARGET/CLAUDE.md"

echo "done: $TARGET"
echo "next:"
echo "  1. AGENTS.md — fill both TODO(project) blocks (description, layout table)"
echo "  2. create or refresh README.md if the target repo does not already have one"
echo "  3. docs/gates/index.md — one row per human-provisioned dependency"
echo "  4. ensure '$T_VERIFY' exists and is green"
echo "  5. commit; configure '$T_TRACKER_NAME' if the repo needs an external backlog"
