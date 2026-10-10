#!/usr/bin/env bash
set -euo pipefail

# Tests for spex-walkthrough-workspace.sh (FR-007, FR-008, FR-009)
# Asserts a persistent timestamped workspace is created under
# specs/<feature>/.walkthrough/, the path is printed as WORKSPACE_PATH,
# and nothing is deleted.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WS_SCRIPT="$REPO_ROOT/spex/scripts/spex-walkthrough-workspace.sh"

PASS=0
FAIL=0
TMPDIR=""

cleanup() {
  if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -q "$needle"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected to contain '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

setup_spec_dir() {
  TMPDIR=$(mktemp -d)
  mkdir -p "$TMPDIR/specs/999-sample"
  echo "# spec" > "$TMPDIR/specs/999-sample/spec.md"
}

# ─── Test: --new creates a timestamped workspace and prints its path ───
echo "=== Test: --new creates workspace and prints WORKSPACE_PATH ==="
setup_spec_dir
set +e
OUT=$(bash "$WS_SCRIPT" "$TMPDIR/specs/999-sample" --new)
RC=$?
set -e
assert_eq "exit 0" "0" "$RC"
assert_contains "prints WORKSPACE_PATH token" "WORKSPACE_PATH " "$OUT"
WS_PATH=$(echo "$OUT" | awk '/WORKSPACE_PATH/ {print $2}')
assert_eq "created dir exists" "true" "$([ -d "$WS_PATH" ] && echo true || echo false)"
assert_contains "path is under .walkthrough" "/.walkthrough/" "$WS_PATH"
assert_eq "path is absolute" "true" "$(case "$WS_PATH" in /*) echo true;; *) echo false;; esac)"
cleanup

# ─── Test: nothing is deleted; a seeded file survives resolve ───
echo "=== Test: never deletes existing artifacts ==="
setup_spec_dir
OUT=$(bash "$WS_SCRIPT" "$TMPDIR/specs/999-sample" --new)
WS_PATH=$(echo "$OUT" | awk '/WORKSPACE_PATH/ {print $2}')
echo "artifact" > "$WS_PATH/artifact.txt"
# Resolve (no --new) must return the same workspace and keep the file.
OUT2=$(bash "$WS_SCRIPT" "$TMPDIR/specs/999-sample")
WS_PATH2=$(echo "$OUT2" | awk '/WORKSPACE_PATH/ {print $2}')
assert_eq "resolve returns the existing workspace" "$WS_PATH" "$WS_PATH2"
assert_eq "seeded artifact survives" "true" "$([ -f "$WS_PATH/artifact.txt" ] && echo true || echo false)"
cleanup

# ─── Test: --new on a dir with an existing workspace adds a new one ───
echo "=== Test: --new creates a distinct second workspace ==="
setup_spec_dir
OUT=$(bash "$WS_SCRIPT" "$TMPDIR/specs/999-sample" --new)
WS1=$(echo "$OUT" | awk '/WORKSPACE_PATH/ {print $2}')
OUT=$(bash "$WS_SCRIPT" "$TMPDIR/specs/999-sample" --new)
WS2=$(echo "$OUT" | awk '/WORKSPACE_PATH/ {print $2}')
assert_eq "two --new runs differ" "true" "$([ "$WS1" != "$WS2" ] && echo true || echo false)"
assert_eq "first workspace still exists" "true" "$([ -d "$WS1" ] && echo true || echo false)"
COUNT=$(find "$TMPDIR/specs/999-sample/.walkthrough" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
assert_eq "two workspaces on disk" "2" "$COUNT"
# With two workspaces present, a plain resolve must return the most recent (WS2),
# not an arbitrary or the oldest one (guards the `sort | tail -1` contract).
OUT=$(bash "$WS_SCRIPT" "$TMPDIR/specs/999-sample")
WS_RESOLVED=$(echo "$OUT" | awk '/WORKSPACE_PATH/ {print $2}')
assert_eq "resolve returns the most recent of two" "$WS2" "$WS_RESOLVED"
cleanup

# ─── Test: usage error exits 2 ───
echo "=== Test: missing argument is a usage error ==="
setup_spec_dir
set +e
bash "$WS_SCRIPT" >/dev/null 2>&1
RC=$?
set -e
assert_eq "exit 2 on no args" "2" "$RC"
cleanup

# ─── Test: nonexistent spec dir is a usage error, creates nothing ───
echo "=== Test: nonexistent spec dir exits 2 and creates nothing ==="
setup_spec_dir
set +e
bash "$WS_SCRIPT" "$TMPDIR/specs/does-not-exist" --new >/dev/null 2>&1
RC=$?
set -e
assert_eq "exit 2 on missing spec dir" "2" "$RC"
assert_eq "no .walkthrough fabricated" "false" "$([ -d "$TMPDIR/specs/does-not-exist/.walkthrough" ] && echo true || echo false)"
cleanup

# ─── Summary ───
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
