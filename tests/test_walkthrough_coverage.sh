#!/usr/bin/env bash
set -euo pipefail

# Tests for spex-walkthrough-coverage.py (FR-003, FR-004, FR-006)
# Asserts stories parsed in priority order, FR->story coverage, orphan FRs,
# and that skip is true only when there are no stories AND no scenarios.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COV_SCRIPT="$REPO_ROOT/spex/scripts/spex-walkthrough-coverage.py"

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

# ─── A full-featured spec with two stories referencing FRs + an orphan FR ───
write_full_spec() {
  TMPDIR=$(mktemp -d)
  cat > "$TMPDIR/spec.md" <<'EOF'
# Feature Specification: Sample

## User Scenarios & Testing

### User Story 2 - Second thing (Priority: P2)

Body mentioning FR-003.

**Acceptance Scenarios**:

1. **Given** a thing, **When** acted, **Then** observed (FR-003).

### User Story 1 - First thing (Priority: P1)

Body mentioning FR-001 and FR-002.

**Acceptance Scenarios**:

1. **Given** setup, **When** run, **Then** see output (FR-001).
2. **Given** state, **When** poked, **Then** result (FR-002).

## Requirements

### Functional Requirements

- **FR-001**: The system MUST do one.
- **FR-002**: The system MUST do two.
- **FR-003**: The system MUST do three.
- **FR-030**: The system MUST do an uncovered thing.
EOF
}

echo "=== Test: coverage parses stories in priority order ==="
write_full_spec
JSON=$(python3 -I "$COV_SCRIPT" "$TMPDIR/spec.md" --json)
assert_eq "skip is false" "false" "$(echo "$JSON" | jq -r '.skip')"
assert_eq "two stories" "2" "$(echo "$JSON" | jq -r '.stories | length')"
assert_eq "P1 story first" "US1" "$(echo "$JSON" | jq -r '.stories[0].id')"
assert_eq "P2 story second" "US2" "$(echo "$JSON" | jq -r '.stories[1].id')"
assert_eq "US1 priority P1" "P1" "$(echo "$JSON" | jq -r '.stories[0].priority')"
assert_eq "US1 title" "First thing" "$(echo "$JSON" | jq -r '.stories[0].title')"
assert_eq "US1 has 2 scenarios" "2" "$(echo "$JSON" | jq -r '.stories[0].scenarios | length')"
cleanup

echo "=== Test: FR coverage and orphans ==="
write_full_spec
JSON=$(python3 -I "$COV_SCRIPT" "$TMPDIR/spec.md" --json)
assert_eq "FR-001 covered by US1" "US1" "$(echo "$JSON" | jq -r '.fr_coverage["FR-001"][0]')"
assert_eq "FR-003 covered by US2" "US2" "$(echo "$JSON" | jq -r '.fr_coverage["FR-003"][0]')"
assert_eq "one orphan FR" "1" "$(echo "$JSON" | jq -r '.orphan_frs | length')"
assert_eq "FR-030 is the orphan" "FR-030" "$(echo "$JSON" | jq -r '.orphan_frs[0]')"
cleanup

echo "=== Test: skip only when no stories AND no scenarios ==="
TMPDIR=$(mktemp -d)
cat > "$TMPDIR/spec.md" <<'EOF'
# Feature Specification: Empty

## Requirements

### Functional Requirements

- **FR-001**: Internal invariant with no user story.
EOF
JSON=$(python3 -I "$COV_SCRIPT" "$TMPDIR/spec.md" --json)
assert_eq "skip true with no stories/scenarios" "true" "$(echo "$JSON" | jq -r '.skip')"
assert_eq "FR-001 is orphan" "FR-001" "$(echo "$JSON" | jq -r '.orphan_frs[0]')"
cleanup

echo "=== Test: stories present but NO acceptance scenarios -> skip false ==="
TMPDIR=$(mktemp -d)
cat > "$TMPDIR/spec.md" <<'EOF'
# Feature Specification: Stories only

## User Scenarios & Testing

### User Story 1 - A thing (Priority: P1)

A story with no acceptance scenarios block.

## Requirements

### Functional Requirements

- **FR-001**: The system MUST do one.
EOF
JSON=$(python3 -I "$COV_SCRIPT" "$TMPDIR/spec.md" --json)
assert_eq "skip false when a story exists" "false" "$(echo "$JSON" | jq -r '.skip')"
assert_eq "one story parsed" "1" "$(echo "$JSON" | jq -r '.stories | length')"
cleanup

echo "=== Test: standalone acceptance scenarios, NO user stories -> skip false ==="
TMPDIR=$(mktemp -d)
cat > "$TMPDIR/spec.md" <<'EOF'
# Feature Specification: Flat scenarios

## Acceptance Scenarios

**Acceptance Scenarios**:

1. **Given** a flat spec, **When** run, **Then** it works.

## Requirements

### Functional Requirements

- **FR-001**: The system MUST do one.
EOF
JSON=$(python3 -I "$COV_SCRIPT" "$TMPDIR/spec.md" --json)
assert_eq "skip false with standalone scenarios" "false" "$(echo "$JSON" | jq -r '.skip')"
assert_eq "no stories parsed" "0" "$(echo "$JSON" | jq -r '.stories | length')"
cleanup

echo "=== Test: suffixed FR ids (FR-011a) are distinct and sorted ==="
TMPDIR=$(mktemp -d)
cat > "$TMPDIR/spec.md" <<'EOF'
# Feature Specification: Suffixed

## User Scenarios & Testing

### User Story 1 - Suffix handling (Priority: P1)

Exercises FR-011, FR-011a and FR-012.

**Acceptance Scenarios**:

1. **Given** x, **When** y, **Then** z (FR-011, FR-011a, FR-012).

## Requirements

### Functional Requirements

- **FR-011**: One.
- **FR-011a**: One-a (a distinct, suffixed requirement).
- **FR-012**: Two.
EOF
JSON=$(python3 -I "$COV_SCRIPT" "$TMPDIR/spec.md" --json)
assert_eq "FR-011 and FR-011a are distinct coverage keys" "US1" "$(echo "$JSON" | jq -r '.fr_coverage["FR-011a"][0]')"
assert_eq "story frs ordered 011 < 011a < 012" "FR-011 FR-011a FR-012" "$(echo "$JSON" | jq -r '.stories[0].frs | join(" ")')"
assert_eq "no orphans" "0" "$(echo "$JSON" | jq -r '.orphan_frs | length')"
cleanup

echo "=== Test: usage error exits 2 ==="
set +e
python3 -I "$COV_SCRIPT" >/dev/null 2>&1
RC=$?
set -e
assert_eq "exit 2 on no args" "2" "$RC"

echo "=== Test: missing file exits 1 ==="
set +e
python3 -I "$COV_SCRIPT" /no/such/spec.md --json >/dev/null 2>&1
RC=$?
set -e
assert_eq "exit 1 on missing file" "1" "$RC"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
