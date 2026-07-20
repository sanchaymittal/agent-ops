#!/usr/bin/env bash
# Stamp the agent-ops operating system into a target repo.
set -euo pipefail

usage() {
  echo "usage: $0 TARGET_DIR PROJECT_NAME ISSUE_PREFIX [VERIFY_CMD]" >&2
  echo "example: $0 ~/github/example-app example-app EX 'npm run verify'" >&2
  echo "linear: LINEAR_TEAM=eng LINEAR_PROJECT=example-app $0 ~/github/example-app example-app EX 'npm run verify'" >&2
  echo "models: COORDINATOR=hermes PLANNER=fable CODER=fable REVIEWER=codex $0 ... (defaults: codex/fable/agy/codex)" >&2
  echo "graphify: GRAPHIFY=1 $0 ... (adds a codebase-map row pointing at graphify-out/wiki, for large repos)" >&2
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

# model allocation (override via env; defaults preserve prior behavior)
T_COORDINATOR=${COORDINATOR:-codex}
T_PLANNER=${PLANNER:-fable}
T_CODER=${CODER:-agy}
T_REVIEWER=${REVIEWER:-codex}
for binding in "$T_COORDINATOR" "$T_PLANNER" "$T_CODER" "$T_REVIEWER"; do
  if [ -z "$(printf '%s' "$binding" | tr -d '[:space:]')" ]; then
    echo "refusing: model bindings must not be blank" >&2
    exit 1
  fi
done
if [ "$T_CODER" = "$T_REVIEWER" ]; then
  echo "refusing: CODER and REVIEWER must differ (cross-model review rule)" >&2
  exit 1
fi

case ${GRAPHIFY:-0} in
  0) T_GRAPHIFY=0 ;;
  1) T_GRAPHIFY=1 ;;
  *)
    echo "refusing: GRAPHIFY must be 0 or 1" >&2
    exit 1
    ;;
esac

export T_NAME=$2 T_PREFIX T_PREFIX_LOWER T_VERIFY T_TRACKER_NAME T_TRACKER_DETAILS T_TRACKER_UPDATE \
  T_COORDINATOR T_PLANNER T_CODER T_REVIEWER
SRC="$(cd "$(dirname "$0")/template" && pwd)"

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

# Render the complete payload before touching the target. This keeps a failed
# substitution, symlink, or optional feature from leaving a partial install.
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/agent-ops-stage.XXXXXX")
cleanup() {
  rm -rf "$STAGE"
}
trap cleanup EXIT

tar -C "$SRC" --exclude='.DS_Store' -cf - . | tar -C "$STAGE" -xf -

# substitute placeholders in payload markdown (perl for BSD/GNU portability)
find "$STAGE/docs" "$STAGE/.orchestration" "$STAGE/AGENTS.md" -type f -name '*.md' -print0 |
  xargs -0 perl -pi -e '
    s/\{\{PROJECT_NAME\}\}/$ENV{T_NAME}/g;
    s/\{\{TASK_TRACKER_NAME\}\}/$ENV{T_TRACKER_NAME}/g;
    s/\{\{TASK_TRACKER_DETAILS\}\}/$ENV{T_TRACKER_DETAILS}/g;
    s/\{\{TASK_TRACKER_UPDATE\}\}/$ENV{T_TRACKER_UPDATE}/g;
    s/\{\{ISSUE_PREFIX\}\}/$ENV{T_PREFIX}/g;
    s/\{\{ISSUE_PREFIX_LOWER\}\}/$ENV{T_PREFIX_LOWER}/g;
    s/\{\{VERIFY_CMD\}\}/$ENV{T_VERIFY}/g;
    s/\{\{COORDINATOR\}\}/$ENV{T_COORDINATOR}/g;
    s/\{\{PLANNER\}\}/$ENV{T_PLANNER}/g;
    s/\{\{CODER\}\}/$ENV{T_CODER}/g;
    s/\{\{REVIEWER\}\}/$ENV{T_REVIEWER}/g;
  '

ln -s AGENTS.md "$STAGE/CLAUDE.md"

if [ "$T_GRAPHIFY" = 1 ]; then
  printf '| Codebase map | [`graphify-out/wiki/index.md`](../graphify-out/wiki/index.md) | Generated codebase knowledge graph — regenerate before trusting; stale map is worse than grep |\n' >> "$STAGE/docs/index.md"
fi

# Managed-file conflicts were checked above; merge the rendered payload only
# after every staging operation has succeeded.
mkdir -p "$TARGET"
tar -C "$STAGE" --exclude='.DS_Store' -cf - . | tar -C "$TARGET" -xf -
rm -rf "$STAGE"
trap - EXIT

echo "done: $TARGET"
echo "models: coordinator=$T_COORDINATOR planner=$T_PLANNER coder=$T_CODER reviewer=$T_REVIEWER"
echo "next:"
echo "  1. AGENTS.md — fill both TODO(project) blocks (description, layout table)"
echo "  2. create or refresh README.md if the target repo does not already have one"
echo "  3. docs/gates/index.md — one row per human-provisioned dependency"
echo "  4. ensure '$T_VERIFY' exists and is green"
echo "  5. initialize git, then run './.orchestration/verify.sh --diff-sha'"
echo "  6. commit; configure '$T_TRACKER_NAME' if the repo needs an external backlog"

if [ "$T_GRAPHIFY" = 1 ]; then
  echo "  7. generate graphify-out/wiki (graphify) so the codebase-map row resolves"
fi
