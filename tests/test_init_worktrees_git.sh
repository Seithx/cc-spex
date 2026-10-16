#!/usr/bin/env bash
# Tests for the spex-worktrees / git extension check in spex-init.sh (FR-014).
#
# A stub `specify` CLI on PATH records registry changes the way specify-cli
# does (remove deletes the entry, add re-registers it as enabled), and can be
# told to fail enabling or adding the git extension.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_SCRIPT="$REPO_ROOT/spex/scripts/spex-init.sh"

PASS=0
FAIL=0
TMPROOT=""

cleanup() {
  if [ -n "$TMPROOT" ] && [ -d "$TMPROOT" ]; then
    rm -rf "$TMPROOT"
  fi
  TMPROOT=""
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

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (missing '$needle' in output:"; printf '%s\n' "$haystack" | sed 's/^/      /'; echo "    )"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if ! printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (unexpected '$needle' in output)"; FAIL=$((FAIL + 1))
  fi
}

# make_project <worktrees-enabled: true|false> <git-available: yes|no>
make_project() {
  cleanup
  TMPROOT=$(cd "$(mktemp -d)" && pwd -P)
  PROJ="$TMPROOT/proj"
  mkdir -p "$PROJ/.specify/extensions" "$TMPROOT/bin"
  jq -n --argjson wt "$1" '{schema_version: "1.0", extensions: {"spex-worktrees": {enabled: $wt}, "spex": {enabled: true}}}' \
    > "$PROJ/.specify/extensions/.registry"
  echo "$2" > "$TMPROOT/git-available"

  cat > "$TMPROOT/bin/specify" <<'EOF'
#!/usr/bin/env bash
REG=".specify/extensions/.registry"
GIT_OK=$(cat "$STUB_ROOT/git-available")
set_enabled() {
  jq --arg id "$1" --argjson v "$2" '.extensions[$id] = ((.extensions[$id] // {}) + {enabled: $v})' "$REG" > "$REG.tmp" && mv "$REG.tmp" "$REG"
}
case "$1 $2" in
  "init "*) exit 0 ;;
  "extension remove")
    jq --arg id "$3" 'del(.extensions[$id])' "$REG" > "$REG.tmp" && mv "$REG.tmp" "$REG"
    exit 0 ;;
  "extension add")
    if [ "$3" = "git" ]; then
      [ "$GIT_OK" = yes ] || exit 1
      set_enabled git true; exit 0
    fi
    id=$(basename "$3"); mkdir -p ".specify/extensions/$id"; set_enabled "$id" true; exit 0 ;;
  "extension enable")
    if [ "$3" = "git" ] && [ "$GIT_OK" != yes ]; then exit 1; fi
    set_enabled "$3" true; exit 0 ;;
  "extension disable")
    set_enabled "$3" false; exit 0 ;;
esac
exit 0
EOF
  chmod +x "$TMPROOT/bin/specify"
  # No network in tests: check_update returns early without curl.
  printf '#!/bin/sh\nexit 1\n' > "$TMPROOT/bin/curl"; chmod +x "$TMPROOT/bin/curl"
}

run_refresh() {
  RC=0
  # Never run init outside the fixture (an empty PROJ would mean the caller's
  # directory), and never with the real specify CLI.
  [ -n "${PROJ:-}" ] && [ -d "$PROJ/.specify" ] || { echo "fixture missing" >&2; exit 1; }
  [ "$(PATH="$TMPROOT/bin:$PATH" command -v specify)" = "$TMPROOT/bin/specify" ] || { echo "specify stub not first on PATH" >&2; exit 1; }
  OUT=$(cd "$PROJ" && STUB_ROOT="$TMPROOT" PATH="$TMPROOT/bin:$PATH" bash "$INIT_SCRIPT" --refresh 2>&1) || RC=$?
}

registry_enabled() {
  jq -r --arg id "$1" '.extensions[$id] | if . == null then "absent" else (.enabled | tostring) end' "$PROJ/.specify/extensions/.registry"
}

echo "Test: refresh fails when spex-worktrees is enabled and git cannot be enabled"
make_project true no
run_refresh
assert_eq "exit code 1" "1" "$RC"
assert_contains "names the missing git extension" "ERROR: spex-worktrees requires the spec-kit git extension" "$OUT"
assert_contains "remedy: add git" "specify extension add git" "$OUT"
assert_contains "remedy: disable spex-worktrees" "specify extension disable spex-worktrees" "$OUT"
assert_not_contains "no restart advice" "RESTART_REQUIRED" "$OUT"

echo "Test: refresh enables git when spex-worktrees is enabled and git is available"
make_project true yes
run_refresh
assert_eq "exit code 3 (restart required)" "3" "$RC"
assert_not_contains "no error" "ERROR:" "$OUT"
assert_eq "git enabled" "true" "$(registry_enabled git)"

echo "Test: refresh keeps working when spex-worktrees is disabled and git is unavailable"
make_project false no
run_refresh
assert_eq "exit code 3 (restart required)" "3" "$RC"
assert_not_contains "no error" "ERROR:" "$OUT"
assert_eq "spex-worktrees stays disabled" "false" "$(registry_enabled spex-worktrees)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
