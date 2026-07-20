#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-ops-init-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

test_rejects_blank_model_binding() {
  local target="$TMP_ROOT/blank-model"

  if CODER='   ' REVIEWER=codex "$ROOT/init.sh" "$target" demo DEMO "printf verified" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"; then
    fail "whitespace-only CODER binding was accepted"
  fi

  [ ! -e "$target" ] || fail "rejected input created the target directory"
}

test_render_failure_is_atomic() {
  local target="$TMP_ROOT/render-failure"

  if PERL5OPT='-MThisModuleCannotExist' "$ROOT/init.sh" "$target" demo DEMO "printf verified" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"; then
    fail "render failure unexpectedly succeeded"
  fi

  [ ! -e "$target" ] || fail "render failure left a partial target"
}

test_graphify_zero_is_disabled() {
  local target="$TMP_ROOT/graphify-zero"

  GRAPHIFY=0 "$ROOT/init.sh" "$target" demo DEMO "printf verified" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"

  if grep -q 'graphify-out/wiki/index.md' "$target/docs/index.md"; then
    fail "GRAPHIFY=0 enabled the codebase-map row"
  fi
}

test_clean_install_contains_enforcement_surface() {
  local target="$TMP_ROOT/clean install"

  "$ROOT/init.sh" "$target" demo DEMO "printf verified" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err"

  [ -x "$target/.orchestration/verify.sh" ] || fail "installed verifier is not executable"
  [ -f "$target/.orchestration/prompts/TEMPLATE.md" ] || fail "prompt template is missing"
  [ -f "$target/.orchestration/reports/TEMPLATE.md" ] || fail "report template is missing"
  [ "$(readlink "$target/CLAUDE.md")" = AGENTS.md ] || fail "CLAUDE.md does not point to AGENTS.md"
  grep -Fq -- '- Verify command: printf verified' "$target/.orchestration/prompts/TEMPLATE.md" || \
    fail "verify command was not stamped into prompt template"
  if grep -rEn '\{\{[A-Z_]+\}\}' "$target" >/dev/null; then
    fail "clean install contains unresolved template placeholders"
  fi
}

test_rejects_blank_model_binding
test_render_failure_is_atomic
test_graphify_zero_is_disabled
test_clean_install_contains_enforcement_surface
printf 'PASS: init integration tests\n'
