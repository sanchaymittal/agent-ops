#!/usr/bin/env bash
# Stamp the agent-ops operating system into a target repo.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/template" && pwd)"

if [ "${1:-}" = --check ] || [ "${1:-}" = --upgrade ]; then
  [ $# -eq 2 ] || { echo "usage: $0 --check|--upgrade TARGET_DIR" >&2; exit 2; }
  case "$1" in
    --check)
      exec python3 "$SRC/.orchestration/installer.py" check --source "$SRC" --target "$2"
      ;;
    --upgrade)
      exec python3 "$SRC/.orchestration/installer.py" upgrade --source "$SRC" --target "$2"
      ;;
  esac
fi

usage() {
  echo "usage: $0 TARGET_DIR PROJECT_NAME [VERIFY_CMD]" >&2
  echo "example: $0 ~/github/example-app example-app 'npm run verify'" >&2
  echo "graphify: GRAPHIFY=1 $0 ... (adds a codebase-map row pointing at graphify-out/wiki, for large repos)" >&2
  exit 1
}

[ $# -ge 2 ] && [ $# -le 3 ] || usage
TARGET=$1
T_VERIFY=${3:-npm run verify}

case ${GRAPHIFY:-0} in
  0) T_GRAPHIFY=0 ;;
  1) T_GRAPHIFY=1 ;;
  *)
    echo "refusing: GRAPHIFY must be 0 or 1" >&2
    exit 1
    ;;
esac

export T_NAME=$2 T_VERIFY
conflicts=()
while IFS= read -r -d '' rel; do
  rel=${rel#./}
  if [ "$rel" != "." ] && [ -e "$TARGET/$rel" ] && [ ! -d "$TARGET/$rel" ]; then
    conflicts+=("$rel")
  fi
done < <(cd "$SRC" && find . -name .DS_Store -prune -o -name __pycache__ -prune -o -type d -print0)

while IFS= read -r -d '' rel; do
  rel=${rel#./}
  if [ -e "$TARGET/$rel" ] || [ -L "$TARGET/$rel" ]; then
    conflicts+=("$rel")
  fi
done < <(cd "$SRC" && find . -name .DS_Store -prune -o -name __pycache__ -prune -o -type f -print0)

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

tar -C "$SRC" --exclude='.DS_Store' --exclude='__pycache__' -cf - . | tar -C "$STAGE" -xf -

# substitute placeholders in payload markdown (perl for BSD/GNU portability)
find "$STAGE/docs" "$STAGE/.orchestration" "$STAGE/AGENTS.md" -type f -name '*.md' -print0 |
  xargs -0 perl -pi -e '
    s/\{\{PROJECT_NAME\}\}/$ENV{T_NAME}/g;
    s/\{\{VERIFY_CMD\}\}/$ENV{T_VERIFY}/g;
  '

ln -s AGENTS.md "$STAGE/CLAUDE.md"

if [ "$T_GRAPHIFY" = 1 ]; then
  printf '| Codebase map | [`graphify-out/wiki/index.md`](../graphify-out/wiki/index.md) | Generated codebase knowledge graph — regenerate before trusting; stale map is worse than grep |\n' >> "$STAGE/docs/index.md"
fi

python3 "$SRC/.orchestration/installer.py" stamp --source "$SRC" --stage "$STAGE" \
  --project-name "$T_NAME" \
  --verify-command "$T_VERIFY"

# Managed-file conflicts were checked above; merge the rendered payload only
# after every staging operation has succeeded.
mkdir -p "$TARGET"
tar -C "$STAGE" --exclude='.DS_Store' --exclude='__pycache__' -cf - . | tar -C "$TARGET" -xf -
rm -rf "$STAGE"
trap - EXIT

echo "done: $TARGET"
echo "next:"
echo "  1. AGENTS.md — fill both TODO(project) blocks (description, layout table)"
echo "  2. create or refresh README.md if the target repo does not already have one"
echo "  3. docs/gates/index.md — one row per human-provisioned dependency"
echo "  4. ensure '$T_VERIFY' exists and is green"
echo "  5. initialize git, then run './.orchestration/preflight.sh' when delegating work"
echo "  6. configure a tracker only if the project needs one"

if [ "$T_GRAPHIFY" = 1 ]; then
  echo "  7. generate graphify-out/wiki (graphify) so the codebase-map row resolves"
fi
