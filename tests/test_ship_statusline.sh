#!/usr/bin/env bash
# Tests for spex-ship-statusline.sh state file resolution with parallel
# pipelines (main checkout + worktrees under .claude/worktrees/).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUSLINE="$REPO_ROOT/spex/scripts/spex-ship-statusline.sh"

PASS=0
FAIL=0
TMPDIR=""

cleanup() {
  if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

setup() {
  TMPDIR=$(mktemp -d)
  MAIN="$(cd "$TMPDIR" && pwd -P)/main"
  WT1="$MAIN/.claude/worktrees/001-first"
  WT2="$MAIN/.claude/worktrees/002-second"
  mkdir -p "$MAIN/.specify" "$WT1/.specify" "$WT2/.specify"
}

ship_state() {
  printf '{"mode":"ship","stage":"%s","stage_index":%s,"total_stages":8,"ask":"smart","status":"running"}\n' "$1" "$2"
}

# Run the statusline like Claude Code does: process CWD is the session's
# current directory, CLAUDE_PROJECT_DIR is the launch directory, and the
# JSON arrives on stdin slightly after the process starts.
run_statusline() {
  local cwd="$1" project="$2"
  local json
  json=$(printf '{"workspace":{"current_dir":"%s","project_dir":"%s"},"context_window":{"used_percentage":42}}' "$cwd" "$project")
  (cd "$cwd" && (sleep 0.1; echo "$json") | env -u SHIP_STATE_FILE CLAUDE_PROJECT_DIR="$project" bash "$STATUSLINE" 2>/dev/null || true) \
    | sed $'s/\033\\[[0-9;]*m//g'
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$needle' in '$haystack')"; FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (did not expect '$needle' in '$haystack')"; FAIL=$((FAIL + 1))
  fi
}

echo "Test: finished worktree session ignores a new pipeline's state in main"
setup
ship_state specify 0 > "$MAIN/.specify/.spex-state"
OUT=$(run_statusline "$WT1" "$MAIN")
assert_not_contains "no ship status from main checkout" "ship" "$OUT"
cleanup

echo "Test: worktree session shows its own pipeline, not the other worktree's"
setup
ship_state implement 6 > "$WT1/.specify/.spex-state"
ship_state clarify 1 > "$WT2/.specify/.spex-state"
OUT=$(run_statusline "$WT1" "$MAIN")
assert_contains "own stage shown" "implement" "$OUT"
assert_not_contains "other stage not shown" "clarify" "$OUT"
cleanup

echo "Test: main session shows the pipeline running in main"
setup
ship_state specify 0 > "$MAIN/.specify/.spex-state"
OUT=$(run_statusline "$MAIN" "$MAIN")
assert_contains "main stage shown" "specify" "$OUT"
cleanup

echo "Test: subdirectory of a worktree resolves to that worktree's state"
setup
git -C "$WT1" init -q
mkdir -p "$WT1/src"
ship_state plan 3 > "$WT1/.specify/.spex-state"
ship_state specify 0 > "$MAIN/.specify/.spex-state"
OUT=$(run_statusline "$WT1/src" "$MAIN")
assert_contains "worktree stage shown" "plan" "$OUT"
cleanup

echo "Test: context percentage from delayed stdin JSON is rendered"
setup
ship_state plan 3 > "$WT1/.specify/.spex-state"
OUT=$(run_statusline "$WT1" "$MAIN")
assert_contains "context percentage shown" "42%" "$OUT"
cleanup

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
