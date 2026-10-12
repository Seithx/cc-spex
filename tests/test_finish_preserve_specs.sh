#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PRESERVE="$REPO_ROOT/spex/scripts/spex-finish-preserve-specs.sh"

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
  WT="$TMPDIR/worktree"
  MAIN="$TMPDIR/main"
  mkdir -p "$WT/.specify/extensions/spex-detach/scripts" "$MAIN"
  cat > "$WT/.specify/extensions/spex-detach/scripts/spex-detach.sh" <<'EOF'
#!/bin/sh
if [ "$1" = "is-enabled" ]; then exit "${DETACH_RC:-1}"; fi
exit 0
EOF
  chmod +x "$WT/.specify/extensions/spex-detach/scripts/spex-detach.sh"
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"; FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected to contain '$needle', got: $haystack)"; FAIL=$((FAIL + 1))
  fi
}

# ─── Test: detach enabled copies the feature dir, preserving extra files ───
echo "=== Test: preserve copies ==="
setup
mkdir -p "$WT/specs/foo"
echo "new spec" > "$WT/specs/foo/spec.md"
echo "new plan" > "$WT/specs/foo/plan.md"
# A detach-relocated runbook lives inside the self-ignoring .walkthrough scratch
# dir; the copy-back must carry it along (US6 scenario 2, FR-039, SC-007).
mkdir -p "$WT/specs/foo/.walkthrough"
echo "runbook body" > "$WT/specs/foo/.walkthrough/RUNBOOK.md"
mkdir -p "$MAIN/specs/foo"
echo "old spec" > "$MAIN/specs/foo/spec.md"
echo "keep me" > "$MAIN/specs/foo/local-only.md"
OUT=$(DETACH_RC=0 "$PRESERVE" "$WT" "$MAIN" specs/foo)
assert_contains "prints PRESERVED" "PRESERVED specs/foo" "$OUT"
assert_eq "existing file updated" "new spec" "$(cat "$MAIN/specs/foo/spec.md")"
assert_eq "new file copied" "new plan" "$(cat "$MAIN/specs/foo/plan.md")"
assert_eq "relocated runbook copied" "runbook body" "$(cat "$MAIN/specs/foo/.walkthrough/RUNBOOK.md")"
assert_eq "extra file in main kept" "keep me" "$(cat "$MAIN/specs/foo/local-only.md")"
cleanup

# ─── Test: detach disabled skips ───
echo "=== Test: detach disabled ==="
setup
mkdir -p "$WT/specs/foo"
echo "x" > "$WT/specs/foo/spec.md"
OUT=$(DETACH_RC=1 "$PRESERVE" "$WT" "$MAIN" specs/foo)
assert_contains "prints PRESERVE_SKIPPED detach-off" "PRESERVE_SKIPPED reason=detach-off" "$OUT"
assert_eq "nothing copied" "no" "$([ -e "$MAIN/specs/foo" ] && echo yes || echo no)"
cleanup

# ─── Test: missing feature dir skips ───
echo "=== Test: missing feature dir ==="
setup
OUT=$(DETACH_RC=0 "$PRESERVE" "$WT" "$MAIN" specs/missing)
assert_contains "prints PRESERVE_SKIPPED no-spec-dir" "PRESERVE_SKIPPED reason=no-spec-dir" "$OUT"
cleanup

# ─── Test: missing arguments exit 2 ───
echo "=== Test: usage ==="
setup
EXIT=0
"$PRESERVE" "$WT" >/dev/null 2>&1 || EXIT=$?
assert_eq "missing arguments exit 2" "2" "$EXIT"
cleanup

# ─── Summary ───
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
