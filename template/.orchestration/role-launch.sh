#!/usr/bin/env bash
# Resolve a role for each supported provider, or emit a hashed inline role.
set -euo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)
usage() { printf 'usage: %s --provider codex|claude|opencode --role NAME\n' "$0" >&2; exit 2; }

provider=''; role=''; native_requested=0
while [ $# -gt 0 ]; do
  case $1 in
    --provider) provider=${2:-}; shift 2 || usage ;;
    --role) role=${2:-}; shift 2 || usage ;;
    --native) native_requested=1; shift ;;
    *) usage ;;
  esac
done
[ -n "$provider" ] && [ -n "$role" ] || usage
case "$role" in */*|.*|'') printf 'blocked: role must be a roster name\n' >&2; exit 1 ;; esac

case "$provider" in
  codex) role_file="$ROOT/.codex/agents/$role.toml"; native='--agent' ;;
  claude) role_file="$ROOT/.claude/agents/$role.md"; native='--agent' ;;
  opencode) role_file="$ROOT/.opencode/agents/$role.md"; native='--agent' ;;
  *) printf 'blocked: unsupported provider: %s\n' "$provider" >&2; exit 1 ;;
esac
[ -f "$role_file" ] || { printf 'blocked: role is not in the local roster: %s\n' "$role" >&2; exit 1; }
role_sha=$(shasum -a 256 "$role_file" | awk '{print $1}')

# The adapter is a launch manifest, not an unverified promise that a provider
# accepted a role flag. A caller may use the native flag only after its
# provider's CLI has independently proven that the selected role resolves.
# Inline is the safe default and carries the exact body/hash to the provider.
case "$provider" in
  # TOML stores the role body as an escaped string. Passing the canonical file
  # itself is lossless and keeps the hash meaningful to an adapter that wants
  # to decode it natively.
  codex) body=$(<"$role_file") ;;
  *) body=$(awk 'BEGIN{p=0} /^---$/{p++; next} p>=2{print}' "$role_file") ;;
esac
if [ "$native_requested" = 1 ]; then
  command -v "$provider" >/dev/null 2>&1 || {
    printf 'blocked: provider CLI is not on PATH: %s\n' "$provider" >&2; exit 1;
  }
  printf '{"provider":"%s","role":"%s","resolution":"native","role_sha256":"%s","role_file":"%s","native_flag":"%s"}\n' \
    "$provider" "$role" "$role_sha" "${role_file#"$ROOT/"}" "$native"
else
  printf '%s\n' "$body"
fi
