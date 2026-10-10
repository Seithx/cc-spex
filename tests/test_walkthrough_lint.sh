#!/usr/bin/env bash
set -euo pipefail

# Tests for spex-walkthrough-lint.sh (FR-010, FR-025)
# Asserts non-zero exit on a doc containing placeholder tokens
# (<scratch>, TODO, /path/to/) and zero on a clean doc.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINT_SCRIPT="$REPO_ROOT/spex/scripts/spex-walkthrough-lint.sh"

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

echo "=== Test: clean doc passes (exit 0) ==="
TMPDIR=$(mktemp -d)
cat > "$TMPDIR/clean.md" <<'EOF'
# Walkthrough Report

**Workspace**: /Users/dev/proj/specs/001-x/.walkthrough/20260101-120000

## Scenario 1: Start CLI (P1, from US1)
- Command: `python3 -I spex/scripts/spex-walkthrough-coverage.py specs/001-x/spec.md --json`
- Ran by: agent
- Expected: JSON with stories
- Actual: printed stories in priority order
EOF
set +e
OUT=$(bash "$LINT_SCRIPT" "$TMPDIR/clean.md")
RC=$?
set -e
assert_eq "clean doc exits 0" "0" "$RC"
assert_contains "prints PASS token" "WALKTHROUGH_LINT_PASS" "$OUT"
cleanup

echo "=== Test: <scratch> placeholder fails ==="
TMPDIR=$(mktemp -d)
printf '# Report\n- Command: `cat <scratch>/out.txt`\n' > "$TMPDIR/bad1.md"
set +e
OUT=$(bash "$LINT_SCRIPT" "$TMPDIR/bad1.md")
RC=$?
set -e
assert_eq "<scratch> exits 1" "1" "$RC"
assert_contains "prints FAIL token" "WALKTHROUGH_LINT_FAIL" "$OUT"
cleanup

echo "=== Test: TODO placeholder fails and reports the token ==="
TMPDIR=$(mktemp -d)
printf '# Report\n- Command: `run TODO fill in`\n' > "$TMPDIR/bad2.md"
set +e
OUT=$(bash "$LINT_SCRIPT" "$TMPDIR/bad2.md")
RC=$?
set -e
assert_eq "TODO exits 1" "1" "$RC"
assert_contains "reports TODO token" "WALKTHROUGH_LINT_FAIL token=TODO" "$OUT"
cleanup

echo "=== Test: /path/to/ placeholder fails and reports the token ==="
TMPDIR=$(mktemp -d)
printf '# Report\n- Command: `cat /path/to/output.log`\n' > "$TMPDIR/bad3.md"
set +e
OUT=$(bash "$LINT_SCRIPT" "$TMPDIR/bad3.md")
RC=$?
set -e
assert_eq "/path/to/ exits 1" "1" "$RC"
assert_contains "reports /path/to/ token" "WALKTHROUGH_LINT_FAIL token=/path/to/" "$OUT"
cleanup

echo "=== Test: PLACEHOLDER token fails ==="
TMPDIR=$(mktemp -d)
printf '# Report\n- Command: `run PLACEHOLDER`\n' > "$TMPDIR/bad4.md"
set +e
OUT=$(bash "$LINT_SCRIPT" "$TMPDIR/bad4.md")
RC=$?
set -e
assert_eq "PLACEHOLDER exits 1" "1" "$RC"
assert_contains "reports PLACEHOLDER token" "WALKTHROUGH_LINT_FAIL token=PLACEHOLDER" "$OUT"
cleanup

echo "=== Test: near-miss content is NOT flagged (no false positives) ==="
TMPDIR=$(mktemp -d)
# Uppercase <Foo> and a <= comparison must not trip the lowercase-only angle rule.
printf '# Report\n- Command: `test $count <= 200 && echo <Foo>`\n' > "$TMPDIR/clean2.md"
set +e
OUT=$(bash "$LINT_SCRIPT" "$TMPDIR/clean2.md")
RC=$?
set -e
assert_eq "near-miss content exits 0" "0" "$RC"
assert_contains "near-miss content passes" "WALKTHROUGH_LINT_PASS" "$OUT"
cleanup

echo "=== Test: usage error exits 2 ==="
set +e
bash "$LINT_SCRIPT" >/dev/null 2>&1
RC=$?
set -e
assert_eq "exit 2 on no args" "2" "$RC"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
