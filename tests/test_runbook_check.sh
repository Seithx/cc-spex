#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$REPO_ROOT/spex/scripts/spex-runbook-check.sh"

PASS=0
FAIL=0
TMPDIR=""

cleanup() {
  if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT
TMPDIR=$(mktemp -d)

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

# A complete runbook that should pass every check.
base_runbook() {
  cat <<'EOF'
---
runbook_version: 1
feature: 054-x
status: drafted
mode: light
steps_total: 2
step_results: pending,pending
drafted_at: abc1234
drafted_fingerprint: deadbeefcafe0011
tested_at:
tested_fingerprint:
updated: 2026-10-11
---

# Try it: Thing

<!-- runbook-status -->
> **Status:** drafted
<!-- /runbook-status -->

## What you're testing

An overview of the journey.

## Steps

### Step 1 of 2: Build the plan (US1)

**Why this step:** It produces the plan file.

**Run:**

```
mytool build --plan
```

**What you should see:** A line saying the plan was written.

**If you see something else:** A non-zero exit means the tool failed.

**Result:**

### Step 2 of 2: Open the page (US1)

**Why this step:** It confirms the page renders.

**Do:**

- Open the app in a browser
- Click the Build button

**What you should see:** The page loads without errors.

**If you see something else:** A blank page means the server is down.

**Result:**

## Coverage

US1 covered.
EOF
}

run_check() {
  local file="$1"
  CHECK_OUT=""
  CHECK_EXIT=0
  CHECK_OUT=$("$CHECK" "$file" 2>&1) || CHECK_EXIT=$?
}

# ─── Test: complete runbook passes ───
echo "=== Test: complete runbook passes ==="
base_runbook > "$TMPDIR/complete.md"
run_check "$TMPDIR/complete.md"
assert_eq "complete runbook exit 0" "0" "$CHECK_EXIT"
assert_contains "complete runbook prints PASS" "RUNBOOK_CHECK_PASS" "$CHECK_OUT"

# ─── Test: step missing 'What you should see' fails structure ───
echo "=== Test: missing What you should see ==="
base_runbook | grep -v "A line saying the plan was written" > "$TMPDIR/nosee.md"
run_check "$TMPDIR/nosee.md"
assert_eq "missing section exit 1" "1" "$CHECK_EXIT"
assert_contains "missing section reports structure" "RUNBOOK_CHECK_FAIL structure" "$CHECK_OUT"

# ─── Test: Do instead of Run passes ───
echo "=== Test: Do step passes ==="
# Base already has a Do step (step 2); isolate that it is accepted by making both steps Do-style.
base_runbook | sed 's/\*\*Run:\*\*/\*\*Do:\*\*/' > "$TMPDIR/do.md"
# The former Run fenced block remains but the step now has a Do marker; it must still pass structure.
run_check "$TMPDIR/do.md"
assert_eq "Do step exit 0" "0" "$CHECK_EXIT"
assert_contains "Do step passes" "RUNBOOK_CHECK_PASS" "$CHECK_OUT"

# ─── Test: steps_total mismatch fails frontmatter ───
echo "=== Test: steps_total mismatch ==="
base_runbook | sed 's/steps_total: 2/steps_total: 3/' > "$TMPDIR/mismatch.md"
run_check "$TMPDIR/mismatch.md"
assert_eq "mismatch exit 1" "1" "$CHECK_EXIT"
assert_contains "mismatch reports frontmatter" "RUNBOOK_CHECK_FAIL frontmatter" "$CHECK_OUT"

# ─── Test: placeholder inside a fenced command block fails ───
echo "=== Test: placeholder in fence ==="
base_runbook | sed 's|mytool build --plan|mytool build <path>|' > "$TMPDIR/placeholder.md"
run_check "$TMPDIR/placeholder.md"
assert_eq "placeholder exit 1" "1" "$CHECK_EXIT"
assert_contains "placeholder reports placeholder" "RUNBOOK_CHECK_FAIL placeholder" "$CHECK_OUT"

# ─── Test: same placeholder token in prose passes ───
echo "=== Test: placeholder in prose passes ==="
base_runbook | sed 's|It produces the plan file.|It writes to <path> on disk.|' > "$TMPDIR/prose.md"
run_check "$TMPDIR/prose.md"
assert_eq "prose placeholder exit 0" "0" "$CHECK_EXIT"
assert_contains "prose placeholder passes" "RUNBOOK_CHECK_PASS" "$CHECK_OUT"

# ─── Test: placeholder token in a non-command (output) fence passes (FR-036) ───
# FR-036 limits placeholder checks to command blocks; real command output recorded
# into a ```text fence may legitimately contain /path/to/ or <...> tokens.
echo "=== Test: placeholder in output fence passes ==="
{ base_runbook; printf '\n## Notes\n\n```text\nWrote config to /path/to/out.yaml (id <generated-id>)\n```\n'; } > "$TMPDIR/outfence.md"
run_check "$TMPDIR/outfence.md"
assert_eq "output-fence placeholder exit 0" "0" "$CHECK_EXIT"
assert_contains "output-fence placeholder passes" "RUNBOOK_CHECK_PASS" "$CHECK_OUT"

# ─── Test: unredacted secrets fail ───
echo "=== Test: secrets ==="
for secret in \
  "ghp_abcdefghijklmnopqrstuvwxyz0123456789" \
  "gho_abcdefghijklmnopqrstuvwxyz0123456789" \
  "github_pat_abcdefghijklmnopqrstuvwxyz0123456789" \
  "glpat-abcdefghijklmnopqrstuvwxyz012345" \
  "sk-abcdefghijklmnopqrstuvwxyz0123456789" \
  "sk-proj-abcdefghijklmnopqrstuvwxyz0123456789" \
  "AKIAIOSFODNN7EXAMPLE" \
  "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTYifQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c" \
  "-----BEGIN RSA PRIVATE KEY-----" \
  "Bearer abcdefghijklmnopqrstuvwxyz0123" \
  "password=hunter2supersecret"; do
  base_runbook > "$TMPDIR/secret.md"
  printf '\nLeaked value: %s\n' "$secret" >> "$TMPDIR/secret.md"
  run_check "$TMPDIR/secret.md"
  assert_eq "secret '${secret:0:12}...' exit 1" "1" "$CHECK_EXIT"
  assert_contains "secret '${secret:0:12}...' reports secret" "RUNBOOK_CHECK_FAIL secret" "$CHECK_OUT"
done

# ─── Test: redacted value passes ───
echo "=== Test: redacted passes ==="
base_runbook > "$TMPDIR/redacted.md"
printf '\nThe token was shown as password=[redacted] in the output.\n' >> "$TMPDIR/redacted.md"
run_check "$TMPDIR/redacted.md"
assert_eq "redacted exit 0" "0" "$CHECK_EXIT"
assert_contains "redacted passes" "RUNBOOK_CHECK_PASS" "$CHECK_OUT"

# ─── Test: missing file exits 2 ───
echo "=== Test: missing file ==="
run_check "$TMPDIR/does-not-exist.md"
assert_eq "missing file exit 2" "2" "$CHECK_EXIT"

# ─── Summary ───
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
