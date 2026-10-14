#!/usr/bin/env bash
# Tests for the pre-commit verification reminder hooks (spec 055):
# spex/scripts/hooks/shared/verify-gate.sh and spex/scripts/hooks/pretool-gate.py
# both read the shared verification record (spex-verify-record.sh).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$REPO_ROOT/spex/scripts/hooks/shared/verify-gate.sh"
PRETOOL="$REPO_ROOT/spex/scripts/hooks/pretool-gate.py"
RECORD="$REPO_ROOT/spex/scripts/spex-verify-record.sh"

REMINDER="spex verify reminder: No verification is recorded for the current code."

# Isolate from the developer's git config (global ignores, signing, hooks)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

PASS=0
FAIL=0
WORKDIR=""

cleanup() {
  cd "$REPO_ROOT" || true
  if [ -n "$WORKDIR" ] && [ -d "$WORKDIR" ]; then
    rm -rf "$WORKDIR"
  fi
  WORKDIR=""
}
trap cleanup EXIT

setup_test_repo() {
  WORKDIR=$(mktemp -d)
  cd "$WORKDIR" || exit 1
  git init -q test-repo
  cd test-repo || exit 1
  git config user.email test@example.com
  git config user.name "Test User"
  git commit --allow-empty -m "initial" -q
  mkdir -p .specify src
  echo 'echo hi' > src/app.sh
  git add src/app.sh
  REPO="$(pwd -P)"
  HOOK_TMP="$WORKDIR/tmp"
  mkdir -p "$HOOK_TMP"
}

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
  if printf '%s\n' "$haystack" | grep -qF -- "$needle"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected to contain '$needle', got '$haystack')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s\n' "$haystack" | grep -qF -- "$needle"; then
    echo "  FAIL: $desc (did not expect '$needle', got '$haystack')"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

# run_gate: run the shared gate, set OUT and ELAPSED (whole seconds)
run_gate() {
  local start end
  start=$(date +%s)
  OUT=$(TMPDIR="$HOOK_TMP" sh "$GATE" Bash "git commit -m x" sid "$REPO" 2>&1)
  end=$(date +%s)
  ELAPSED=$((end - start))
}

run_pretool() {
  OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"session_id":"sid","cwd":"%s"}' "$REPO" \
    | TMPDIR="$HOOK_TMP" python3 "$PRETOOL" 2>&1)
}

echo "=== Test: shared verify-gate.sh ==="
setup_test_repo
run_gate
assert_contains "no record: reminder shown" "context:$REMINDER" "$OUT"
assert_contains "reminder names /speckit-spex-gates-verify" "/speckit-spex-gates-verify" "$OUT"
assert_contains "reminder names /speckit-spex-finish" "/speckit-spex-finish" "$OUT"
assert_not_contains "reminder does not mention stamp" "stamp" "$OUT"
assert_eq "no record: completes in under 5s" "true" "$([ "$ELAPSED" -lt 5 ] && echo true || echo false)"
touch "$HOOK_TMP/.claude-spex-verified-sid"
run_gate
assert_contains "legacy session marker is ignored" "context:$REMINDER" "$OUT"
"$RECORD" record >/dev/null
run_gate
assert_eq "with record: allow" "allow" "$OUT"
assert_eq "with record: completes in under 5s" "true" "$([ "$ELAPSED" -lt 5 ] && echo true || echo false)"
echo 'echo changed' >> src/app.sh
run_gate
assert_contains "after code edit: reminder again" "context:$REMINDER" "$OUT"
assert_eq "after code edit: completes in under 5s" "true" "$([ "$ELAPSED" -lt 5 ] && echo true || echo false)"
cleanup

echo "=== Test: pretool-gate.py ==="
setup_test_repo
run_pretool
assert_contains "no record: reminder shown" "$REMINDER" "$OUT"
assert_contains "reminder names /speckit-spex-gates-verify" "/speckit-spex-gates-verify" "$OUT"
assert_contains "reminder names /speckit-spex-finish" "/speckit-spex-finish" "$OUT"
assert_not_contains "reminder does not mention stamp" "stamp" "$OUT"
touch "$HOOK_TMP/.claude-spex-verified-sid"
run_pretool
assert_contains "legacy session marker is ignored" "$REMINDER" "$OUT"
"$RECORD" record >/dev/null
run_pretool
assert_eq "with record: no output" "" "$OUT"
echo 'echo changed' >> src/app.sh
run_pretool
assert_contains "after code edit: reminder again" "$REMINDER" "$OUT"
cleanup

echo "=== Test: pretool-gate.py timeout kills the record check ==="
setup_test_repo
# Copy the hook next to a stub record script that hangs, as in a huge repo.
mkdir -p "$WORKDIR/plugin/scripts/hooks"
cp "$PRETOOL" "$WORKDIR/plugin/scripts/hooks/pretool-gate.py"
HANG="29.$(( $$ % 1000 + 100 ))"   # unique sleep argument to find leftovers
printf '#!/bin/sh\nsleep %s\n' "$HANG" > "$WORKDIR/plugin/scripts/spex-verify-record.sh"
START=$(date +%s)
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"session_id":"sid","cwd":"%s"}' "$REPO" \
  | TMPDIR="$HOOK_TMP" python3 "$WORKDIR/plugin/scripts/hooks/pretool-gate.py" 2>&1)
ELAPSED=$(( $(date +%s) - START ))
assert_contains "timeout: reminder shown" "$REMINDER" "$OUT"
assert_eq "timeout: returns within 9s" "true" "$([ "$ELAPSED" -lt 9 ] && echo true || echo false)"
LEFT=$(ps -eo args | grep -F "sleep $HANG" | grep -v grep | wc -l | tr -d ' ')
assert_eq "timeout: no child process left running" "0" "$LEFT"
cleanup

echo "=== Test: pretool-gate.py timeout leaves no temp index behind ==="
setup_test_repo
mkdir -p "$WORKDIR/plugin/scripts/hooks" "$WORKDIR/bin"
cp "$PRETOOL" "$WORKDIR/plugin/scripts/hooks/pretool-gate.py"
cp "$RECORD" "$REPO_ROOT/spex/scripts/spex-runbook-status.sh" "$REPO_ROOT/spex/scripts/spex-runbook-status.py" "$WORKDIR/plugin/scripts/"
REAL_GIT=$(command -v git)
# git shim: `git add` (the fingerprint's temp-index build) hangs past the timeout
cat > "$WORKDIR/bin/git" <<SHIM
#!/bin/sh
[ "\$1" = add ] && sleep 20
exec "$REAL_GIT" "\$@"
SHIM
chmod +x "$WORKDIR/bin/git"
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"session_id":"sid","cwd":"%s"}' "$REPO" \
  | PATH="$WORKDIR/bin:$PATH" TMPDIR="$HOOK_TMP" python3 "$WORKDIR/plugin/scripts/hooks/pretool-gate.py" 2>&1)
assert_contains "slow fingerprint: reminder shown" "$REMINDER" "$OUT"
sleep 1
LEFT=$(find "$HOOK_TMP" -mindepth 1 -maxdepth 1 -name 'tmp*' | wc -l | tr -d ' ')
assert_eq "slow fingerprint: temp index directory removed" "0" "$LEFT"
cleanup

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
