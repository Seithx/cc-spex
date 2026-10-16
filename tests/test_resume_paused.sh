#!/usr/bin/env bash
# Tests for the prompt-submit hook resuming a paused ship pipeline
# (spex/scripts/hooks/shared/resume-paused.sh via the Claude and Codex
# context hooks).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAUDE_HOOK="$REPO_ROOT/spex/scripts/hooks/context-hook.py"
CODEX_HOOK="$REPO_ROOT/spex/scripts/adapters/codex/context-hook.py"

PASS=0
FAIL=0
TMPROOT=""

cleanup() {
  if [ -n "$TMPROOT" ] && [ -d "$TMPROOT" ]; then
    rm -rf "$TMPROOT"
  fi
}
trap cleanup EXIT

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"; FAIL=$((FAIL + 1))
  fi
}

TMPROOT=$(mktemp -d)
[ -n "$TMPROOT" ] && [ -d "$TMPROOT" ] || { echo "mktemp failed"; exit 1; }

# make_project <dir> <state-json or empty>
make_project() {
  local dir="$1" state="$2"
  mkdir -p "$dir/.specify"
  git -C "$dir" init -q -b main
  if [ -n "$state" ]; then
    printf '%s\n' "$state" > "$dir/.specify/.spex-state"
  fi
}

# run_hook <hook> <cwd> <prompt>: prints the hook's stdout
run_hook() {
  local hook="$1" cwd="$2" prompt="$3"
  jq -n --arg p "$prompt" --arg c "$cwd" '{prompt: $p, cwd: $c, session_id: "test", turn_id: "test"}' \
    | TMPDIR="$TMPROOT" python3 "$hook"
}

field() {
  jq -r ".$2" "$1/.specify/.spex-state"
}

PAUSED='{"mode":"ship","stage":"review-plan","stage_index":5,"status":"paused","ask":"smart","retries":2}'

echo "Test: Claude hook resumes a paused ship pipeline on a plain reply"
P="$TMPROOT/claude-paused"; make_project "$P" "$PAUSED"
OUT=$(run_hook "$CLAUDE_HOOK" "$P" "fix #1 and continue")
assert_eq "status running" "running" "$(field "$P" status)"
assert_eq "retries reset" "0" "$(field "$P" retries)"
assert_eq "stage kept" "review-plan" "$(field "$P" stage)"
assert_eq "ask kept" "smart" "$(field "$P" ask)"
assert_eq "no stdout for a non-spex prompt" "" "$OUT"

echo "Test: resume also works from a subdirectory of the checkout"
P="$TMPROOT/claude-subdir"; make_project "$P" "$PAUSED"; mkdir -p "$P/src/deep"
run_hook "$CLAUDE_HOOK" "$P/src/deep" "go on" >/dev/null
assert_eq "status running" "running" "$(field "$P" status)"

echo "Test: Codex hook resumes a paused ship pipeline"
P="$TMPROOT/codex-paused"; make_project "$P" "$PAUSED"
run_hook "$CODEX_HOOK" "$P" "continue" >/dev/null
assert_eq "status running" "running" "$(field "$P" status)"

echo "Test: a running ship pipeline is left alone"
P="$TMPROOT/running"; make_project "$P" '{"mode":"ship","stage":"plan","stage_index":3,"status":"running","ask":"smart","retries":1}'
run_hook "$CLAUDE_HOOK" "$P" "hello" >/dev/null
assert_eq "status running" "running" "$(field "$P" status)"
assert_eq "retries untouched" "1" "$(field "$P" retries)"

echo "Test: a failed ship pipeline is left alone"
P="$TMPROOT/failed"; make_project "$P" '{"mode":"ship","stage":"implement","stage_index":6,"status":"failed","ask":"smart","retries":0}'
run_hook "$CLAUDE_HOOK" "$P" "hello" >/dev/null
assert_eq "status failed" "failed" "$(field "$P" status)"

echo "Test: flow state is left alone"
P="$TMPROOT/flow"; make_project "$P" '{"mode":"flow","feature_branch":"001-x","status":"paused"}'
run_hook "$CLAUDE_HOOK" "$P" "hello" >/dev/null
assert_eq "flow status untouched" "paused" "$(field "$P" status)"

echo "Test: no state file is fine"
P="$TMPROOT/none"; make_project "$P" ""
RC=0; run_hook "$CLAUDE_HOOK" "$P" "hello" >/dev/null || RC=$?
assert_eq "exit code" "0" "$RC"
if [ -e "$P/.specify/.spex-state" ]; then
  echo "  FAIL: state file created"; FAIL=$((FAIL + 1))
else
  echo "  PASS: no state file created"; PASS=$((PASS + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
