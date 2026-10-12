#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE="$REPO_ROOT/spex/scripts/spex-runbook-fixture.sh"

PASS=0
FAIL=0
TMPDIR=""

cleanup() {
  if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

new_scratch() {
  TMPDIR=$(mktemp -d)
  SCRATCH="$TMPDIR/.walkthrough"
  mkdir -p "$SCRATCH"
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

# ─── Test: start process ───
echo "=== Test: start process ==="
new_scratch
"$FIXTURE" start "$SCRATCH" --name proc1 --kind process -- sleep 30 >/dev/null
STATE_JSON=$(cat "$SCRATCH/fixtures.json")
assert_eq "tier quick" "quick" "$(echo "$STATE_JSON" | jq -r '.fixtures[0].tier')"
assert_eq "owner agent" "agent" "$(echo "$STATE_JSON" | jq -r '.fixtures[0].owner')"
assert_eq "state running" "running" "$(echo "$STATE_JSON" | jq -r '.fixtures[0].state')"
assert_eq "log path recorded" "yes" "$([ -n "$(echo "$STATE_JSON" | jq -r '.fixtures[0].log')" ] && echo yes || echo no)"
PID=$(echo "$STATE_JSON" | jq -r '.fixtures[0].pid')
assert_eq "pid alive" "alive" "$(kill -0 "$PID" 2>/dev/null && echo alive || echo dead)"

# ─── Test: starting the same name again exits 1 ───
echo "=== Test: duplicate name exits 1 ==="
EXIT=0
"$FIXTURE" start "$SCRATCH" --name proc1 --kind process -- sleep 30 >/dev/null 2>&1 || EXIT=$?
assert_eq "duplicate start exit 1" "1" "$EXIT"

# ─── Test: status refreshes state via kill -0 ───
echo "=== Test: status refresh ==="
kill "$PID" 2>/dev/null || true
sleep 0.3
"$FIXTURE" status "$SCRATCH" >/dev/null
assert_eq "state stopped after kill" "stopped" "$(jq -r '.fixtures[] | select(.name=="proc1") | .state' "$SCRATCH/fixtures.json")"
cleanup

# ─── Test: stop --name ends the process ───
echo "=== Test: stop --name ==="
new_scratch
"$FIXTURE" start "$SCRATCH" --name p1 --kind process -- sleep 30 >/dev/null
PID=$(jq -r '.fixtures[0].pid' "$SCRATCH/fixtures.json")
"$FIXTURE" stop "$SCRATCH" --name p1 >/dev/null
assert_eq "process killed after stop" "dead" "$(kill -0 "$PID" 2>/dev/null && echo alive || echo dead)"
assert_eq "state stopped after stop --name" "stopped" "$(jq -r '.fixtures[] | select(.name=="p1") | .state' "$SCRATCH/fixtures.json")"
cleanup

# ─── Test: stop --quick stops all quick fixtures ───
echo "=== Test: stop --quick ==="
new_scratch
"$FIXTURE" start "$SCRATCH" --name q1 --kind process -- sleep 30 >/dev/null
"$FIXTURE" start "$SCRATCH" --name q2 --kind process -- sleep 30 >/dev/null
PID1=$(jq -r '.fixtures[] | select(.name=="q1") | .pid' "$SCRATCH/fixtures.json")
PID2=$(jq -r '.fixtures[] | select(.name=="q2") | .pid' "$SCRATCH/fixtures.json")
"$FIXTURE" stop "$SCRATCH" --quick >/dev/null
assert_eq "q1 killed" "dead" "$(kill -0 "$PID1" 2>/dev/null && echo alive || echo dead)"
assert_eq "q2 killed" "dead" "$(kill -0 "$PID2" 2>/dev/null && echo alive || echo dead)"
assert_eq "q1 stopped" "stopped" "$(jq -r '.fixtures[] | select(.name=="q1") | .state' "$SCRATCH/fixtures.json")"
cleanup

# ─── Test: container lifecycle (skipped if podman unavailable) ───
echo "=== Test: container lifecycle ==="
new_scratch
if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
  "$FIXTURE" start "$SCRATCH" --name c1 --kind container -- podman run -d docker.io/library/alpine:3.20 sleep 30 >/dev/null
  CID=$(jq -r '.fixtures[] | select(.name=="c1") | .id' "$SCRATCH/fixtures.json")
  assert_eq "container id recorded" "yes" "$([ -n "$CID" ] && [ "$CID" != "null" ] && echo yes || echo no)"
  "$FIXTURE" status "$SCRATCH" >/dev/null
  assert_eq "container running" "running" "$(jq -r '.fixtures[] | select(.name=="c1") | .state' "$SCRATCH/fixtures.json")"
  "$FIXTURE" stop "$SCRATCH" --name c1 >/dev/null
  assert_eq "container removed" "gone" "$(podman inspect "$CID" >/dev/null 2>&1 && echo present || echo gone)"
else
  echo "  SKIP: podman not available, container lifecycle not tested"
fi
cleanup

# ─── Test: exit 4 when container kind used without a container runtime ───
echo "=== Test: exit 4 without runtime ==="
new_scratch
EXIT=0
SPEX_PODMAN="podman-does-not-exist-xyz" "$FIXTURE" start "$SCRATCH" --name c2 --kind container -- podman run -d docker.io/library/alpine:3.20 sleep 30 >/dev/null 2>&1 || EXIT=$?
assert_eq "container without runtime exit 4" "4" "$EXIT"
cleanup

# ─── Test: external fixtures via record/keep (US4) ───
echo "=== Test: external fixtures ==="
new_scratch
"$FIXTURE" record "$SCRATCH" --name cluster --tier remote --owner user --teardown "rosa delete cluster" --note "set up by hand" >/dev/null
assert_eq "record kind external" "external" "$(jq -r '.fixtures[] | select(.name=="cluster") | .kind' "$SCRATCH/fixtures.json")"
assert_eq "record tier remote" "remote" "$(jq -r '.fixtures[] | select(.name=="cluster") | .tier' "$SCRATCH/fixtures.json")"
assert_eq "record owner user" "user" "$(jq -r '.fixtures[] | select(.name=="cluster") | .owner' "$SCRATCH/fixtures.json")"
assert_eq "record teardown" "rosa delete cluster" "$(jq -r '.fixtures[] | select(.name=="cluster") | .teardown' "$SCRATCH/fixtures.json")"
"$FIXTURE" start "$SCRATCH" --name p1 --kind process -- sleep 30 >/dev/null
"$FIXTURE" stop "$SCRATCH" --quick >/dev/null
assert_eq "stop --quick leaves external alone" "unknown" "$(jq -r '.fixtures[] | select(.name=="cluster") | .state' "$SCRATCH/fixtures.json")"
assert_eq "stop --quick stops the quick fixture" "stopped" "$(jq -r '.fixtures[] | select(.name=="p1") | .state' "$SCRATCH/fixtures.json")"
"$FIXTURE" status "$SCRATCH" >/dev/null
assert_eq "status keeps external unknown" "unknown" "$(jq -r '.fixtures[] | select(.name=="cluster") | .state' "$SCRATCH/fixtures.json")"
"$FIXTURE" keep "$SCRATCH" --name cluster >/dev/null
assert_eq "keep marks kept" "kept" "$(jq -r '.fixtures[] | select(.name=="cluster") | .state' "$SCRATCH/fixtures.json")"
"$FIXTURE" status "$SCRATCH" >/dev/null
assert_eq "status leaves kept as kept" "kept" "$(jq -r '.fixtures[] | select(.name=="cluster") | .state' "$SCRATCH/fixtures.json")"
cleanup

# ─── Summary ───
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
