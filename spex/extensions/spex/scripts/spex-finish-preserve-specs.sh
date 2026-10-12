#!/bin/sh
# spex-finish-preserve-specs.sh - Copy a feature's spec dir back to the main
# checkout before a worktree is removed, when detach mode is on (research R9).
#
# In detach mode the spec artifacts are excluded from git and exist only on
# disk; worktree creation copies them in, but nothing copies them back. This
# guards against that data loss before `finish` removes the worktree.
#
# Usage: spex-finish-preserve-specs.sh <worktree-path> <main-worktree> <feature-dir>
# Prints PRESERVED <feature-dir>, or PRESERVE_SKIPPED reason=<detach-off|no-spec-dir>.
# Exit 0 in both cases, 1 if the copy failed, 2 usage.

WORKTREE="${1:-}"
MAIN="${2:-}"
FEATURE_DIR="${3:-}"

if [ -z "$WORKTREE" ] || [ -z "$MAIN" ] || [ -z "$FEATURE_DIR" ]; then
  echo "usage: spex-finish-preserve-specs.sh <worktree-path> <main-worktree> <feature-dir>" >&2
  exit 2
fi

DETACH="$WORKTREE/.specify/extensions/spex-detach/scripts/spex-detach.sh"
enabled=false
if [ -f "$DETACH" ]; then
  if (cd "$WORKTREE" && sh "$DETACH" is-enabled) >/dev/null 2>&1; then
    enabled=true
  fi
fi

if [ "$enabled" != true ]; then
  echo "PRESERVE_SKIPPED reason=detach-off"
  exit 0
fi

SRC="$WORKTREE/$FEATURE_DIR"
if [ ! -d "$SRC" ]; then
  echo "PRESERVE_SKIPPED reason=no-spec-dir"
  exit 0
fi

DEST="$MAIN/$FEATURE_DIR"
mkdir -p "$DEST"
# --checksum so content changes always transfer, even when size and mtime happen
# to match; no --delete so files that exist only in main are preserved.
if rsync -a --checksum "$SRC/" "$DEST/"; then
  echo "PRESERVED $FEATURE_DIR"
  exit 0
fi
echo "preserve: copy failed" >&2
exit 1
