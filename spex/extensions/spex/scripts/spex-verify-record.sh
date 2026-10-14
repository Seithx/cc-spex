#!/bin/sh
# spex-verify-record.sh - Read and write the verification record (spec 055).
#
# The record is evidence that verify passed for a specific code state. The code
# state is the walkthrough content fingerprint (spex-runbook-status.sh
# fingerprint): a hash of the working tree content excluding specs/ and
# brainstorm/. The record lives in the worktree's git dir, so it is never
# tracked, never part of the fingerprinted content, and survives
# /speckit-spex-clear and pipeline state cleanup.
#
# Usage:
#   spex-verify-record.sh fingerprint
#   spex-verify-record.sh begin
#   spex-verify-record.sh record [--feature <spec-dir>] [--expect <fingerprint>]
#   spex-verify-record.sh check  [--feature <spec-dir>]
#   spex-verify-record.sh path
#   spex-verify-record.sh clear
#
# Verify runs `begin` before its first gate: it stores the current fingerprint
# in the git dir (spex-verify-start), so it survives separate shell calls.
# `record` compares against it (or against an explicit --expect), so a pass is
# never recorded for code that changed while the gates were running. `record`
# removes the start file afterwards.
#
# Exit codes:
#   fingerprint: 0 printed; 2 not a git repository or fingerprint unavailable
#   begin: 0 stored; 2 not a git repository or fingerprint unavailable
#   record: 0 written; 1 code changed since begin/--expect (nothing written);
#           2 not a git repository or fingerprint unavailable
#   check:  0 verified; 1 stale, missing, or unreadable; 2 error
#   path:   0; 2 not a git repository
#   clear:  0 (test and maintenance helper; /speckit-spex-clear must not call it,
#           the record has to survive state cleanup)
#   usage errors: 2

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATUS="$SCRIPT_DIR/spex-runbook-status.sh"
RECORD_NAME="spex-verified.json"
START_NAME="spex-verify-start"
RECORD_VERSION=1
ALLOW_EXPECT=false

usage() {
  cat >&2 <<'EOF'
Usage: spex-verify-record.sh <command> [options]

Commands:
  fingerprint                    Print the current code-state fingerprint
  begin                          Store the current fingerprint as the start of a
                                 verify run (record compares against it)
  record [--feature <spec-dir>] [--expect <fp>]
                                 Record a verification pass for the current code
                                 (refuses when the code no longer matches <fp>)
  check  [--feature <spec-dir>]  Report whether the current code is verified
  path                           Print the absolute path of the record file
  clear                          Remove the record file
EOF
  exit 2
}

# Absolute path of a file in the git dir, or exit 2 outside a git repository.
git_file_path() {
  rel=$(git rev-parse --git-path "$1" 2>/dev/null) || return 2
  [ -n "$rel" ] || return 2
  dir=$(dirname "$rel")
  abs_dir=$(cd "$dir" 2>/dev/null && pwd -P) || return 2
  printf '%s/%s\n' "$abs_dir" "$(basename "$rel")"
}

record_path() {
  git_file_path "$RECORD_NAME"
}

start_path() {
  git_file_path "$START_NAME"
}

# Normalize a spec dir to a repo-relative path without trailing slash.
normalize_feature() {
  f="$1"
  [ -n "$f" ] || { printf ''; return; }
  top=$(git rev-parse --show-toplevel 2>/dev/null)
  top_p=""
  [ -n "$top" ] && top_p=$(cd "$top" 2>/dev/null && pwd -P)
  while :; do
    case "$f" in
      */) f=${f%/} ;;
      ./*) f=${f#./} ;;
      *) break ;;
    esac
  done
  # Resolve existing directories (absolute, or relative to the caller's cwd)
  # to a physical path, so the stored value is repo-relative regardless of
  # where the caller ran from.
  if [ -d "$f" ]; then
    f=$(cd "$f" 2>/dev/null && pwd -P) || f="$1"
  fi
  if [ -n "$top" ]; then
    case "$f" in
      "$top"/*) f=${f#"$top"/} ;;
      "$top_p"/*) f=${f#"$top_p"/} ;;
    esac
  fi
  printf '%s' "$f"
}

current_fingerprint() {
  top=$(git rev-parse --show-toplevel 2>/dev/null) || return 2
  (cd "$top" && "$STATUS" fingerprint 2>/dev/null)
}

parse_feature_opt() {
  FEATURE=""
  FEATURE_SET=false
  EXPECT=""
  EXPECT_SET=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --expect)
        [ "$ALLOW_EXPECT" = true ] || usage
        [ $# -ge 2 ] || usage
        EXPECT="$2"
        EXPECT_SET=true
        shift 2
        ;;
      --expect=*)
        [ "$ALLOW_EXPECT" = true ] || usage
        EXPECT="${1#--expect=}"
        EXPECT_SET=true
        shift
        ;;
      --feature)
        [ $# -ge 2 ] || usage
        FEATURE="$2"
        FEATURE_SET=true
        shift 2
        ;;
      --feature=*)
        FEATURE="${1#--feature=}"
        FEATURE_SET=true
        shift
        ;;
      *) usage ;;
    esac
  done
}

require_git() {
  git rev-parse --git-dir >/dev/null 2>&1 || {
    echo "spex-verify-record: not a git repository" >&2
    exit 2
  }
}

require_jq() {
  command -v jq >/dev/null 2>&1 || {
    echo "spex-verify-record: jq is required" >&2
    exit 2
  }
}

cmd_record() {
  ALLOW_EXPECT=true
  parse_feature_opt "$@"
  require_git
  require_jq
  path=$(record_path) || exit 2
  fp=$(current_fingerprint)
  if [ -z "$fp" ]; then
    echo "spex-verify-record: cannot compute fingerprint" >&2
    exit 2
  fi
  start=$(start_path) || start=""
  if [ "$EXPECT_SET" != true ] && [ -n "$start" ] && [ -f "$start" ]; then
    EXPECT=$(head -n 1 "$start" 2>/dev/null)
    EXPECT_SET=true
  fi
  [ -n "$start" ] && rm -f "$start"
  if [ "$EXPECT_SET" = true ] && [ "$EXPECT" != "$fp" ]; then
    echo "spex-verify-record: code changed during verification; pass not recorded (rerun verify)" >&2
    echo "VERIFY_NOT_RECORDED reason=code-changed expected=$EXPECT current=$fp"
    exit 1
  fi
  feature=$(normalize_feature "$FEATURE")
  head=$(git rev-parse --short HEAD 2>/dev/null || true)
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  tmp="$path.tmp.$$"
  if ! jq -n \
      --argjson version "$RECORD_VERSION" \
      --arg fingerprint "$fp" \
      --arg head "$head" \
      --arg feature "$feature" \
      --arg verified_at "$now" \
      '{version: $version, fingerprint: $fingerprint, head: $head, feature: $feature, verified_at: $verified_at}' \
      > "$tmp"; then
    rm -f "$tmp"
    echo "spex-verify-record: cannot write record" >&2
    exit 2
  fi
  mv -f "$tmp" "$path" || { rm -f "$tmp"; exit 2; }
  echo "VERIFY_RECORDED fingerprint=$fp feature=$feature"
}

# Print the check result JSON and exit with the matching code.
emit_check() {
  state="$1" recorded="$2" verified_at="$3" rec_feature="$4"
  jq -n \
    --arg state "$state" \
    --arg fingerprint "$fp" \
    --arg recorded "$recorded" \
    --arg verified_at "$verified_at" \
    --arg feature "$rec_feature" \
    '{state: $state,
      fingerprint: $fingerprint,
      recorded: (if $recorded == "" then null else $recorded end),
      verified_at: (if $verified_at == "" then null else $verified_at end),
      feature: (if $feature == "" then null else $feature end)}'
  if [ "$state" = "verified" ]; then
    exit 0
  fi
  exit 1
}

cmd_check() {
  parse_feature_opt "$@"
  require_git
  require_jq
  path=$(record_path) || exit 2
  fp=$(current_fingerprint)
  if [ -z "$fp" ]; then
    echo "spex-verify-record: cannot compute fingerprint" >&2
    exit 2
  fi
  if [ ! -f "$path" ]; then
    emit_check missing "" "" ""
  fi
  if ! fields=$(jq -er '
        if type == "object" and .version == 1 and (.fingerprint | type) == "string"
        then [.fingerprint, (.verified_at // ""), (.feature // "")] | map(tostring) | join("\t")
        else error("bad record") end' "$path" 2>/dev/null); then
    emit_check unreadable "" "" ""
  fi
  tab=$(printf '\t')
  rec_fp=${fields%%"$tab"*}
  rest=${fields#*"$tab"}
  rec_at=${rest%%"$tab"*}
  rec_feature=${rest#*"$tab"}
  if [ "$rec_fp" != "$fp" ]; then
    emit_check stale "$rec_fp" "$rec_at" "$rec_feature"
  fi
  if [ "$FEATURE_SET" = true ] && [ -n "$rec_feature" ]; then
    want=$(normalize_feature "$FEATURE")
    if [ "$want" != "$rec_feature" ]; then
      emit_check stale "$rec_fp" "$rec_at" "$rec_feature"
    fi
  fi
  emit_check verified "$rec_fp" "$rec_at" "$rec_feature"
}

cmd_fingerprint() {
  [ $# -eq 0 ] || usage
  require_git
  fp=$(current_fingerprint)
  if [ -z "$fp" ]; then
    echo "spex-verify-record: cannot compute fingerprint" >&2
    exit 2
  fi
  printf '%s\n' "$fp"
}

cmd_begin() {
  [ $# -eq 0 ] || usage
  require_git
  start=$(start_path) || exit 2
  fp=$(current_fingerprint)
  if [ -z "$fp" ]; then
    echo "spex-verify-record: cannot compute fingerprint" >&2
    exit 2
  fi
  printf '%s\n' "$fp" > "$start" || exit 2
  echo "VERIFY_BEGIN fingerprint=$fp"
}

cmd_path() {
  [ $# -eq 0 ] || usage
  require_git
  record_path || exit 2
}

cmd_clear() {
  [ $# -eq 0 ] || usage
  if path=$(record_path 2>/dev/null); then
    rm -f "$path"
  fi
  if start=$(start_path 2>/dev/null); then
    rm -f "$start"
  fi
  echo "VERIFY_CLEARED"
}

[ $# -ge 1 ] || usage
cmd="$1"
shift
case "$cmd" in
  fingerprint) cmd_fingerprint "$@" ;;
  begin) cmd_begin "$@" ;;
  record) cmd_record "$@" ;;
  check) cmd_check "$@" ;;
  path) cmd_path "$@" ;;
  clear) cmd_clear "$@" ;;
  -h|--help|help) usage ;;
  *) usage ;;
esac
