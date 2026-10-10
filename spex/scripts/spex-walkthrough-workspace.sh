#!/bin/bash
# spex-walkthrough-workspace.sh - Create or resolve the persistent walkthrough run workspace.
#
# Usage:
#   spex-walkthrough-workspace.sh <spec-dir> [--new]
#
# Arguments:
#   spec-dir    Feature spec directory (e.g. specs/053-guided-walkthrough)
#   --new       Force a fresh timestamped workspace. Without it, resolve the
#               most recent existing workspace if one is present, otherwise create one.
#
# Behavior:
#   Creates specs/<feature>/.walkthrough/<timestamp>/ and NEVER deletes anything
#   (FR-007, FR-008, FR-009). The directory is gitignored via `specs/**/.walkthrough/`.
#
# Output (stdout):
#   WORKSPACE_PATH <absolute-path>
#
# Exit codes:
#   0   Success
#   2   Usage error

set -euo pipefail

usage() {
  echo "Usage: spex-walkthrough-workspace.sh <spec-dir> [--new]" >&2
  exit 2
}

SPEC_DIR=""
FORCE_NEW=false

while [ $# -gt 0 ]; do
  case "$1" in
    --new) FORCE_NEW=true ;;
    -h|--help) usage ;;
    -*) echo "Unknown option: $1" >&2; usage ;;
    *)
      if [ -z "$SPEC_DIR" ]; then
        SPEC_DIR="$1"
      else
        echo "Unexpected argument: $1" >&2
        usage
      fi
      ;;
  esac
  shift
done

if [ -z "$SPEC_DIR" ]; then
  usage
fi

if [ ! -d "$SPEC_DIR" ]; then
  echo "Spec directory not found: $SPEC_DIR" >&2
  exit 2
fi

WALK_ROOT="$SPEC_DIR/.walkthrough"

# Resolve the most recent existing workspace unless --new was requested.
if [ "$FORCE_NEW" = false ] && [ -d "$WALK_ROOT" ]; then
  LATEST=$(find "$WALK_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -1)
  if [ -n "$LATEST" ]; then
    ABS=$(cd "$LATEST" && pwd)
    echo "WORKSPACE_PATH $ABS"
    exit 0
  fi
fi

# Create a fresh, uniquely named workspace. Append the PID (and a counter if
# needed) so two creations within the same second never collide.
mkdir -p "$WALK_ROOT"
TS=$(date +%Y%m%d-%H%M%S)
CANDIDATE="$WALK_ROOT/${TS}-$$"
SUFFIX=0
while [ -e "$CANDIDATE" ]; do
  SUFFIX=$((SUFFIX + 1))
  CANDIDATE="$WALK_ROOT/${TS}-$$-${SUFFIX}"
done

mkdir -p "$CANDIDATE"
ABS=$(cd "$CANDIDATE" && pwd)
echo "WORKSPACE_PATH $ABS"
exit 0
