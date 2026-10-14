#!/usr/bin/env bash
# Tests for spex/scripts/spex-verify-record.sh (the verification record, spec 055).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RECORD="$REPO_ROOT/spex/scripts/spex-verify-record.sh"
STATUS="$REPO_ROOT/spex/scripts/spex-runbook-status.sh"

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
  mkdir -p src specs/x brainstorm
  echo 'echo hi' > src/app.sh
  echo '# spec' > specs/x/spec.md
  echo '# idea' > brainstorm/01-idea.md
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

# check_state: run `check` with optional args, set STATE and RC
check_state() {
  local out
  out=$("$RECORD" check "$@" 2>/dev/null)
  RC=$?
  STATE=$(printf '%s' "$out" | jq -r '.state' 2>/dev/null || echo "")
}

echo "=== Test: missing record ==="
setup_test_repo
check_state
assert_eq "check without record is missing" "missing" "$STATE"
assert_eq "check without record exits 1" "1" "$RC"
cleanup

echo "=== Test: record then check ==="
setup_test_repo
OUT=$("$RECORD" record --feature specs/x 2>&1)
assert_contains "record prints VERIFY_RECORDED" "VERIFY_RECORDED" "$OUT"
assert_contains "record prints feature" "feature=specs/x" "$OUT"
check_state
assert_eq "check after record is verified" "verified" "$STATE"
assert_eq "check after record exits 0" "0" "$RC"
check_state --feature specs/x
assert_eq "check --feature matching is verified" "verified" "$STATE"
assert_eq "check --feature matching exits 0" "0" "$RC"
check_state --feature "./specs/x/"
assert_eq "check --feature with ./ and trailing slash is verified" "verified" "$STATE"
check_state --feature "$PWD/specs/x"
assert_eq "check --feature with absolute path is verified" "verified" "$STATE"
FIELDS=$(jq -r '[.version, (.fingerprint|length>0), (.head|length>0), .feature, (.verified_at|length>0)] | map(tostring) | join(",")' "$("$RECORD" path)")
assert_eq "record has version/fingerprint/head/feature/verified_at" "1,true,true,specs/x,true" "$FIELDS"
cleanup

echo "=== Test: commit keeps verified ==="
setup_test_repo
"$RECORD" record --feature specs/x >/dev/null
git add -A && git commit -q -m "add content"
assert_eq "precondition: commit happened" "2" "$(git rev-list --count HEAD)"
assert_eq "precondition: tree is clean" "" "$(git status --porcelain)"
check_state --feature specs/x
assert_eq "committing recorded content keeps verified" "verified" "$STATE"
cleanup

echo "=== Test: spec and brainstorm edits keep verified ==="
setup_test_repo
"$RECORD" record --feature specs/x >/dev/null
echo 'more' >> specs/x/spec.md
check_state
assert_eq "editing specs/ keeps verified" "verified" "$STATE"
echo 'more' >> brainstorm/01-idea.md
check_state
assert_eq "editing brainstorm/ keeps verified" "verified" "$STATE"
cleanup

echo "=== Test: code edit makes stale ==="
setup_test_repo
"$RECORD" record --feature specs/x >/dev/null
echo 'echo changed' >> src/app.sh
check_state
assert_eq "editing code makes stale" "stale" "$STATE"
assert_eq "stale exits 1" "1" "$RC"
cleanup

echo "=== Test: committed, untracked, and deleted code changes make stale ==="
setup_test_repo
git add -A && git commit -q -m "base"
"$RECORD" record --feature specs/x >/dev/null
echo 'echo committed' >> src/app.sh
git add -A && git commit -q -m "code change"
check_state
assert_eq "committed code change makes stale" "stale" "$STATE"
"$RECORD" record --feature specs/x >/dev/null
echo 'echo new' > src/new.sh
check_state
assert_eq "new untracked code file makes stale" "stale" "$STATE"
rm src/new.sh
check_state
assert_eq "removing the untracked file restores verified" "verified" "$STATE"
rm src/app.sh
check_state
assert_eq "deleted code file makes stale" "stale" "$STATE"
cleanup

echo "=== Test: fingerprint and record --expect ==="
setup_test_repo
FP=$("$RECORD" fingerprint)
assert_eq "fingerprint is a 64-char hash" "64" "${#FP}"
assert_eq "fingerprint matches runbook status fingerprint" "$("$STATUS" fingerprint)" "$FP"
OUT=$("$RECORD" record --feature specs/x --expect "$FP" 2>/dev/null)
RC=$?
assert_eq "record --expect matching exits 0" "0" "$RC"
assert_contains "record --expect matching records" "VERIFY_RECORDED" "$OUT"
"$RECORD" clear >/dev/null
echo 'echo edited during verify' >> src/app.sh
OUT=$("$RECORD" record --feature specs/x --expect "$FP" 2>/dev/null)
RC=$?
assert_eq "record --expect after code change exits 1" "1" "$RC"
assert_contains "record --expect after code change reports it" "VERIFY_NOT_RECORDED" "$OUT"
check_state
assert_eq "record --expect after code change writes nothing" "missing" "$STATE"
"$RECORD" check --expect "$FP" >/dev/null 2>&1
assert_eq "check rejects --expect" "2" "$?"
cleanup

echo "=== Test: begin stores the start state across shells ==="
setup_test_repo
OUT=$("$RECORD" begin)
assert_contains "begin prints VERIFY_BEGIN" "VERIFY_BEGIN fingerprint=" "$OUT"
OUT=$("$RECORD" record --feature specs/x 2>/dev/null)
assert_eq "record after begin on unchanged code exits 0" "0" "$?"
assert_eq "record removes the start file" "no" "$([ -f "$(git rev-parse --git-path spex-verify-start)" ] && echo yes || echo no)"
"$RECORD" clear >/dev/null
"$RECORD" begin >/dev/null
echo 'echo edited mid-run' >> src/app.sh
OUT=$("$RECORD" record --feature specs/x 2>/dev/null)
assert_eq "record after begin and a code edit exits 1" "1" "$?"
check_state
assert_eq "nothing recorded after a mid-run edit" "missing" "$STATE"
OUT=$("$RECORD" record --feature specs/x 2>/dev/null)
assert_eq "start file is consumed: next record succeeds" "0" "$?"
cleanup

echo "=== Test: fingerprint equals the empty-index tree for flagged entries ==="
# The fingerprint seeds its temporary index from the real one for speed. These
# index states must not change the result versus an empty-index build.
unseeded_fp() {
  local tmpidx tree
  tmpidx=$(mktemp -d)
  GIT_INDEX_FILE="$tmpidx/index" git add -A >/dev/null 2>&1
  tree=$(GIT_INDEX_FILE="$tmpidx/index" git write-tree)
  rm -rf "$tmpidx"
  git ls-tree -r "$tree" | awk -F'\t' '$2 !~ /^(specs|brainstorm)\// {split($1, m, " "); print m[3] " " $2}' \
    | LC_ALL=C sort | python3 -c 'import sys,hashlib; print(hashlib.sha256(sys.stdin.read().rstrip("\n").encode()).hexdigest())'
}
setup_test_repo
echo 'b' > src/b.sh
echo 'ign' > ign.txt
git add -A && git commit -q -m base
assert_eq "plain index: seeded equals empty-index" "$(unseeded_fp)" "$("$RECORD" fingerprint)"
git update-index --assume-unchanged src/app.sh
echo 'edit' >> src/app.sh
assert_eq "assume-unchanged edit: seeded equals empty-index" "$(unseeded_fp)" "$("$RECORD" fingerprint)"
git update-index --no-assume-unchanged src/app.sh
git checkout -q -- src/app.sh
git update-index --skip-worktree src/b.sh
echo 'edit' >> src/b.sh
assert_eq "skip-worktree edit: seeded equals empty-index" "$(unseeded_fp)" "$("$RECORD" fingerprint)"
git update-index --no-skip-worktree src/b.sh
git checkout -q -- src/b.sh
echo 'ign.txt' > .gitignore
echo 'edit' >> ign.txt
assert_eq "tracked-ignored file: seeded equals empty-index" "$(unseeded_fp)" "$("$RECORD" fingerprint)"
rm .gitignore
git checkout -q -- ign.txt
git update-index --assume-unchanged src/b.sh
echo 'edit' >> src/b.sh
mkdir -p docs
EXPECTED=$(unseeded_fp)
GOT=$(cd docs && python3 "$REPO_ROOT/spex/scripts/spex-runbook-status.py" fingerprint)
assert_eq "flag outside cwd subdir: seeded equals empty-index" "$EXPECTED" "$GOT"
git update-index --no-assume-unchanged src/b.sh
git checkout -q -- src/b.sh
git update-index --add --cacheinfo "160000,$(git rev-parse HEAD),vendor/mod"
mkdir -p vendor/mod
assert_eq "uninitialized submodule: seeded equals empty-index" "$(unseeded_fp)" "$("$RECORD" fingerprint)"
cleanup

echo "=== Test: relative feature path from a subdirectory ==="
setup_test_repo
(cd src && "$RECORD" record --feature ../specs/x/ >/dev/null)
FEAT=$(jq -r '.feature' "$("$RECORD" path)")
assert_eq "relative path from subdir is stored repo-relative" "specs/x" "$FEAT"
check_state --feature specs/x
assert_eq "check from root with repo-relative path is verified" "verified" "$STATE"
cleanup

echo "=== Test: record without feature matches any feature ==="
setup_test_repo
"$RECORD" record >/dev/null
check_state --feature specs/other
assert_eq "record without --feature is verified for any feature" "verified" "$STATE"
cleanup

echo "=== Test: feature mismatch is stale ==="
setup_test_repo
"$RECORD" record --feature specs/x >/dev/null
check_state --feature specs/other
assert_eq "check --feature other is stale" "stale" "$STATE"
assert_eq "feature mismatch exits 1" "1" "$RC"
cleanup

echo "=== Test: unreadable record ==="
setup_test_repo
P=$("$RECORD" path)
echo 'not json {' > "$P"
check_state
assert_eq "garbage JSON is unreadable" "unreadable" "$STATE"
assert_eq "unreadable exits 1" "1" "$RC"
echo '{"version": 99, "fingerprint": "x"}' > "$P"
check_state
assert_eq "unknown version is unreadable" "unreadable" "$STATE"
cleanup

echo "=== Test: path lives in the git dir ==="
setup_test_repo
P=$("$RECORD" path)
GITDIR=$(cd "$(git rev-parse --git-dir)" && pwd -P)
case "$P" in
  "$GITDIR"/*) IN_GITDIR=yes ;;
  *) IN_GITDIR=no ;;
esac
assert_eq "path is inside git dir" "yes" "$IN_GITDIR"
case "$P" in
  /*) ABS=yes ;;
  *) ABS=no ;;
esac
assert_eq "path is absolute" "yes" "$ABS"
git worktree add -q ../linked -b linked-branch 2>/dev/null
cd ../linked || exit 1
LP=$("$RECORD" path)
case "$LP" in
  */.git/worktrees/linked/*) IN_WT=yes ;;
  *) IN_WT=no ;;
esac
assert_eq "linked worktree path is under .git/worktrees/<name>/" "yes" "$IN_WT"
cd ../test-repo || exit 1
cleanup

echo "=== Test: writing the record does not change the fingerprint ==="
setup_test_repo
FP1=$("$STATUS" fingerprint)
"$RECORD" record >/dev/null
FP2=$("$STATUS" fingerprint)
assert_eq "precondition: fingerprint is non-empty" "true" "$([ -n "$FP1" ] && echo true || echo false)"
assert_eq "fingerprint unchanged by record write" "$FP1" "$FP2"
cleanup

echo "=== Test: clear ==="
setup_test_repo
"$RECORD" record >/dev/null
OUT=$("$RECORD" clear)
assert_eq "clear prints VERIFY_CLEARED" "VERIFY_CLEARED" "$OUT"
check_state
assert_eq "check after clear is missing" "missing" "$STATE"
OUT=$("$RECORD" clear)
assert_eq "clear without record still prints VERIFY_CLEARED" "VERIFY_CLEARED" "$OUT"
cleanup

echo "=== Test: usage errors ==="
setup_test_repo
"$RECORD" bogus >/dev/null 2>&1
assert_eq "unknown subcommand exits 2" "2" "$?"
"$RECORD" >/dev/null 2>&1
assert_eq "no subcommand exits 2" "2" "$?"
"$RECORD" check --feature >/dev/null 2>&1
assert_eq "missing option value exits 2" "2" "$?"
cleanup

echo "=== Test: outside a git repo ==="
WORKDIR=$(mktemp -d)
cd "$WORKDIR" || exit 1
"$RECORD" check >/dev/null 2>&1
assert_eq "check outside git repo exits 2" "2" "$?"
"$RECORD" path >/dev/null 2>&1
assert_eq "path outside git repo exits 2" "2" "$?"
"$RECORD" record >/dev/null 2>&1
assert_eq "record outside git repo exits 2" "2" "$?"
"$RECORD" fingerprint >/dev/null 2>&1
assert_eq "fingerprint outside git repo exits 2" "2" "$?"
OUT=$("$RECORD" clear 2>/dev/null)
assert_eq "clear outside git repo exits 0" "0" "$?"
cleanup

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
