#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-ops-lease-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

create_repo() {
  local target=$1
  "$ROOT/init.sh" "$target" demo DEMO "printf verified" >/dev/null
  git -C "$target" init -q
  git -C "$target" config user.name test
  git -C "$target" config user.email test@example.com
  git -C "$target" config commit.gpgsign false
  git -C "$target" add .
  git -C "$target" commit -qm baseline
}

REPO="$TMP_ROOT/repo"
create_repo "$REPO"
PREFLIGHT="$REPO/.orchestration/preflight.sh"
LEASE="$REPO/.orchestration/lease.sh"
LEASE_DIR="$REPO/.orchestration/.lease"

test_preflight_accepts_a_valid_dispatch() {
  local base_sha
  base_sha=$(git -C "$REPO" rev-parse HEAD)
  "$PREFLIGHT" --verify-cmd "printf verified" --base-sha "$base_sha" \
    --cli git --role engineering-minimal-change-engineer >/dev/null ||
    fail "preflight rejected a valid dispatch"
}

test_preflight_prints_the_supervision_numbers() {
  local output
  output=$("$PREFLIGHT" --verify-cmd "printf verified") ||
    fail "preflight rejected a valid dispatch"
  # The delivery mechanism, not decoration: these lines are the only copy of the
  # rule a coordinator is guaranteed to have in context when it starts waiting.
  case $output in
    *'window >= 900000 ms'*) ;;
    *) fail "preflight did not print the window floor: $output" ;;
  esac
  case $output in
    *'--peek'*) ;;
    *) fail "preflight did not print the non-consuming wait rule: $output" ;;
  esac
  case $output in
    *'max 2 supervision calls per dispatched task'*) ;;
    *) fail "preflight did not print the polling budget: $output" ;;
  esac
}

test_preflight_rejects_missing_cli_and_verify_command() {
  local output
  if output=$("$PREFLIGHT" --verify-cmd "printf verified" --cli agent-ops-absent-cli 2>&1); then fail "preflight accepted a missing CLI"; fi
  case $output in
    'blocked: capability: CLI not on PATH: agent-ops-absent-cli') ;;
    *) fail "unexpected missing-CLI failure: $output" ;;
  esac

  if output=$("$PREFLIGHT" --verify-cmd "agent-ops-absent-runner test" 2>&1); then fail "preflight accepted an unavailable verify command"; fi
  case $output in
    'blocked: capability: verify command not on PATH: agent-ops-absent-runner') ;;
    *) fail "unexpected verify-command failure: $output" ;;
  esac

  if output=$("$PREFLIGHT" --verify-cmd "" 2>&1); then fail "preflight accepted an empty verify command"; fi
  case $output in
    'blocked: task: '*) ;;
    *) fail "unexpected empty verify-command failure: $output" ;;
  esac
}

test_preflight_rejects_an_unknown_role() {
  local output
  if output=$("$PREFLIGHT" --verify-cmd "printf verified" --role engineering-not-a-role 2>&1); then fail "preflight accepted a role outside the roster"; fi
  case $output in
    'blocked: task: role is not in the local roster: engineering-not-a-role') ;;
    *) fail "unexpected role failure: $output" ;;
  esac
}

test_first_owner_acquires_the_lease() {
  "$LEASE" acquire --dispatch DEMO-1 --owner alice >/dev/null || fail "first acquire failed"
  [ -d "$LEASE_DIR" ] || fail "acquire did not create the lease directory"
  grep -qx 'owner=alice' "$LEASE_DIR/meta" || fail "lease record is missing its owner"
  grep -qx 'dispatch=DEMO-1' "$LEASE_DIR/meta" || fail "lease record is missing its dispatch"
  grep -q '^pid=[0-9][0-9]*$' "$LEASE_DIR/meta" || fail "lease record is missing its pid"
  grep -q '^acquired=....-..-..T' "$LEASE_DIR/meta" || fail "lease record is missing its timestamp"
}

# Invoked directly, never inside $(...): a command substitution would make the
# recorded PPID a subshell that exits at once, which is exactly the bug here.
test_a_fresh_lease_is_not_stale() {
  local output
  if output=$("$LEASE" status 2>&1); then fail "status reported a held lease as available"; fi
  case $output in
    *'[stale'*) fail "a freshly acquired lease was reported stale: $output" ;;
  esac
  if "$PREFLIGHT" --verify-cmd "printf verified" >/dev/null 2>&1; then fail "preflight passed while a lease was held"; fi
  output=$("$PREFLIGHT" --verify-cmd "printf verified" 2>&1 || true)
  case $output in
    'blocked: lease: held by alice'*) ;;
    *) fail "preflight double-prefixed or mangled the lease detail: $output" ;;
  esac
}

test_lease_is_invisible_to_the_diff_hash() {
  local before after
  "$LEASE" release --owner alice --force >/dev/null
  before=$(cd "$REPO" && ./.orchestration/verify.sh --diff-sha)
  "$LEASE" acquire --dispatch DEMO-1 --owner alice >/dev/null
  after=$(cd "$REPO" && ./.orchestration/verify.sh --diff-sha)
  [ "$before" = "$after" ] || fail "a held lease changed the worktree diff SHA"
}

test_second_owner_is_rejected_without_losing_the_lease() {
  local output
  if output=$("$LEASE" acquire --dispatch DEMO-2 --owner bob 2>&1); then fail "a second owner acquired a held lease"; fi
  case $output in
    'blocked: lease: held by alice (dispatch DEMO-1'*) ;;
    *) fail "unexpected second-owner failure: $output" ;;
  esac
  [ -d "$LEASE_DIR" ] || fail "the rejected acquire deleted the first lease"
  grep -qx 'owner=alice' "$LEASE_DIR/meta" || fail "the rejected acquire overwrote the lease record"

  if "$PREFLIGHT" --verify-cmd "printf verified" >/dev/null 2>&1; then fail "preflight passed while another writer held the lease"; fi
}

test_release_is_owner_aware_and_safe_when_unheld() {
  local output
  if output=$("$LEASE" release --owner bob 2>&1); then fail "a non-owner released the lease"; fi
  case $output in
    'blocked: lease: held by alice'*'--force required'*) ;;
    *) fail "unexpected non-owner release failure: $output" ;;
  esac
  [ -d "$LEASE_DIR" ] || fail "a rejected release deleted the lease"

  "$LEASE" release --owner alice >/dev/null || fail "the owner could not release its lease"
  if [ -d "$LEASE_DIR" ]; then fail "release left the lease directory behind"; fi

  "$LEASE" release --owner alice >/dev/null || fail "release failed when no lease was held"
  "$LEASE" status >/dev/null || fail "status did not report an available lease"
}

test_stale_lease_needs_an_explicit_force() {
  local output
  "$LEASE" acquire --dispatch DEMO-3 --owner ghost >/dev/null
  # A PID that cannot be running: the record is stale, but never auto-reaped.
  perl -pi -e 's/^pid=.*/pid=2147483647/' "$LEASE_DIR/meta"

  if output=$("$LEASE" status 2>&1); then fail "status reported a held lease as available"; fi
  case $output in
    *'[stale: pid not running]') ;;
    *) fail "status did not mark the lease stale: $output" ;;
  esac

  if output=$("$LEASE" acquire --dispatch DEMO-4 --owner carol 2>&1); then fail "a stale lease was silently taken over"; fi
  [ -d "$LEASE_DIR" ] || fail "a stale lease was removed without --force"

  "$LEASE" release --owner carol --force >/dev/null || fail "--force could not break a stale lease"
  if [ -d "$LEASE_DIR" ]; then fail "--force release left the lease directory behind"; fi
  "$LEASE" acquire --dispatch DEMO-4 --owner carol >/dev/null ||
    fail "the lease was not reusable after a forced release"
  "$LEASE" release --owner carol >/dev/null
}

# The acquirer can die between the mkdir lock and the meta write; --force is the
# documented escape hatch and has to work in exactly that state.
test_force_release_clears_a_lease_with_no_meta() {
  mkdir "$LEASE_DIR"
  "$LEASE" release --owner carol --force >/dev/null || fail "--force could not clear a lease with no meta"
  if [ -d "$LEASE_DIR" ]; then fail "--force left a meta-less lease directory behind"; fi

  mkdir "$LEASE_DIR"
  if "$LEASE" release --owner carol >/dev/null 2>&1; then fail "an unforced release cleared a meta-less lease"; fi
  [ -d "$LEASE_DIR" ] || fail "an unforced release removed a meta-less lease"
  "$LEASE" status >/dev/null 2>&1 && fail "status reported a meta-less lease as available"
  "$LEASE" release --owner carol --force >/dev/null
}

# A meta written under umask 077 by another UID is readable to its owner and not
# to a coordinator: --force has to clear that too. Root can read anything, so the
# case is only meaningful for a non-root runner.
test_force_release_clears_a_lease_with_unreadable_meta() {
  if [ "$(id -u)" = 0 ]; then
    printf 'SKIP: unreadable-meta case is meaningless as root\n'
    return 0
  fi
  "$LEASE" acquire --dispatch DEMO-6 --owner eve >/dev/null
  chmod 000 "$LEASE_DIR/meta"
  # chmod back before any failure path, so the EXIT trap can always clean up.
  if "$LEASE" release --owner eve >/dev/null 2>&1; then
    chmod 600 "$LEASE_DIR/meta" 2>/dev/null || true
    fail "an unforced release claimed a lease whose meta is unreadable"
  fi
  [ -d "$LEASE_DIR" ] || fail "an unforced release removed a lease with unreadable meta"

  if ! "$LEASE" release --owner eve --force >/dev/null; then
    chmod 600 "$LEASE_DIR/meta" 2>/dev/null || true
    fail "--force could not clear a lease whose meta is unreadable"
  fi
  if [ -d "$LEASE_DIR" ]; then fail "--force left an unreadable-meta lease behind"; fi
}

test_newlines_in_caller_values_are_rejected() {
  local output injected
  injected=$(printf 'evil\npid=1')
  if output=$("$LEASE" acquire --dispatch DEMO-5 --owner "$injected" 2>&1); then fail "a newline in --owner was accepted"; fi
  case $output in
    'lease: --owner must not contain a newline') ;;
    *) fail "unexpected newline-owner failure: $output" ;;
  esac
  if [ -d "$LEASE_DIR" ]; then fail "a rejected acquire created the lease directory"; fi

  if output=$("$LEASE" acquire --dispatch "$injected" --owner dave 2>&1); then fail "a newline in --dispatch was accepted"; fi
  case $output in
    'lease: --dispatch must not contain a newline') ;;
    *) fail "unexpected newline-dispatch failure: $output" ;;
  esac
}

test_preflight_accepts_a_valid_dispatch
test_preflight_prints_the_supervision_numbers
test_preflight_rejects_missing_cli_and_verify_command
test_preflight_rejects_an_unknown_role
test_first_owner_acquires_the_lease
test_a_fresh_lease_is_not_stale
test_lease_is_invisible_to_the_diff_hash
test_second_owner_is_rejected_without_losing_the_lease
test_release_is_owner_aware_and_safe_when_unheld
test_stale_lease_needs_an_explicit_force
test_force_release_clears_a_lease_with_no_meta
test_force_release_clears_a_lease_with_unreadable_meta
test_newlines_in_caller_values_are_rejected

printf 'PASS: preflight and writer leases\n'
