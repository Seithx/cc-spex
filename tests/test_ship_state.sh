#!/usr/bin/env bash
# Tests for spex-ship-state.py resume handling.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHIP_STATE="$REPO_ROOT/spex/scripts/spex-ship-state.py"

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
  export SHIP_STATE_FILE="$TMPDIR/.specify/.spex-state"
  (cd "$TMPDIR" && python3 "$SHIP_STATE" create brainstorm/01-x.md --ask smart --start-from review-spec >/dev/null)
  python3 "$SHIP_STATE" pause >/dev/null
  jq '.retries = 2' "$SHIP_STATE_FILE" > "$SHIP_STATE_FILE.tmp" && mv "$SHIP_STATE_FILE.tmp" "$SHIP_STATE_FILE"
}

field() {
  jq -r ".$1" "$SHIP_STATE_FILE"
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"; FAIL=$((FAIL + 1))
  fi
}

echo "Test: resume without --ask keeps the saved level"
setup
OUT=$(python3 "$SHIP_STATE" resume)
assert_eq "output" "RESUMED stage=review-spec index=2 ask=smart" "$OUT"
assert_eq "status running" "running" "$(field status)"
assert_eq "retries reset" "0" "$(field retries)"
assert_eq "ask kept" "smart" "$(field ask)"
cleanup

echo "Test: resume --ask overrides the saved level"
setup
OUT=$(python3 "$SHIP_STATE" resume --ask never)
assert_eq "output" "RESUMED stage=review-spec index=2 ask=never" "$OUT"
assert_eq "ask overridden" "never" "$(field ask)"
assert_eq "stage kept" "review-spec" "$(field stage)"
cleanup

echo "Test: resume rejects an invalid level and leaves state unchanged"
setup
RC=0; python3 "$SHIP_STATE" resume --ask sometimes >/dev/null 2>&1 || RC=$?
assert_eq "exit code" "2" "$RC"
assert_eq "ask unchanged" "smart" "$(field ask)"
assert_eq "status unchanged" "paused" "$(field status)"
cleanup

echo "Test: resume without a state file fails"
TMPDIR=$(mktemp -d)
export SHIP_STATE_FILE="$TMPDIR/.specify/.spex-state"
RC=0; python3 "$SHIP_STATE" resume >/dev/null 2>&1 || RC=$?
assert_eq "exit code" "1" "$RC"
cleanup

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
