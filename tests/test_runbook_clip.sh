#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLIP="$REPO_ROOT/spex/scripts/spex-runbook-clip.sh"

PASS=0
FAIL=0
TMPDIR=$(mktemp -d)

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
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected to contain '$needle', got: $haystack)"
    FAIL=$((FAIL + 1))
  fi
}

# ─── Test: copies via a fake pbcopy first on PATH ───
echo "=== Test: pbcopy ==="
mkdir -p "$TMPDIR/bin"
cat > "$TMPDIR/bin/pbcopy" <<EOF
#!/bin/sh
cat > "$TMPDIR/clipped.txt"
EOF
chmod +x "$TMPDIR/bin/pbcopy"
OUT=$(printf '%s' 'mytool build --plan' | PATH="$TMPDIR/bin:$PATH" "$CLIP")
assert_contains "prints CLIP_OK tool=pbcopy" "CLIP_OK tool=pbcopy" "$OUT"
assert_eq "clipboard holds exact command" "mytool build --plan" "$(cat "$TMPDIR/clipped.txt")"

# ─── Test: no clipboard tool prints CLIP_UNAVAILABLE and exits 3 ───
echo "=== Test: no tool available ==="
mkdir -p "$TMPDIR/limited"
ln -sf "$(command -v cat)" "$TMPDIR/limited/cat"
EXIT=0
OUT=$(printf '%s' 'mytool build' | PATH="$TMPDIR/limited" "$CLIP" 2>&1) || EXIT=$?
assert_contains "prints CLIP_UNAVAILABLE" "CLIP_UNAVAILABLE" "$OUT"
assert_eq "no tool exit 3" "3" "$EXIT"

# ─── Test: empty stdin exits 2 ───
echo "=== Test: empty stdin ==="
EXIT=0
printf '' | "$CLIP" >/dev/null 2>&1 || EXIT=$?
assert_eq "empty stdin exit 2" "2" "$EXIT"

# ─── Summary ───
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
