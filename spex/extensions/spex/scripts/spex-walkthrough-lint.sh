#!/bin/bash
# spex-walkthrough-lint.sh - Fail if any presented/reported command contains a placeholder.
#
# Usage:
#   spex-walkthrough-lint.sh <file-or-dir>
#
# Enforces FR-010 (every command is complete and runnable, no placeholders) as a
# mechanical gate (FR-025, SC-003). Scans the target for placeholder tokens:
#   - angle-bracket placeholders like <scratch>, <path>, <store>, <feature>
#   - the literal path stub /path/to/
#   - the words TODO and PLACEHOLDER
#
# Output (stdout):
#   WALKTHROUGH_LINT_PASS                      no placeholders found
#   WALKTHROUGH_LINT_FAIL token=<matched>      one line per finding
#
# Exit codes:
#   0   Clean
#   1   Placeholder found
#   2   Usage error

set -euo pipefail

usage() {
  echo "Usage: spex-walkthrough-lint.sh <file-or-dir>" >&2
  exit 2
}

if [ $# -lt 1 ] || [ -z "${1:-}" ]; then
  usage
fi

TARGET="$1"

if [ ! -e "$TARGET" ]; then
  echo "Target not found: $TARGET" >&2
  exit 2
fi

# Placeholder patterns (extended regex). Angle-bracket placeholders are limited to
# lowercase single tokens so real content (e.g. "HTTP 200", comparisons) is not flagged.
PATTERNS='(<[a-z][a-z0-9_./-]*>|/path/to/|TODO|PLACEHOLDER)'

# Collect matches across the target (file or directory).
if [ -d "$TARGET" ]; then
  MATCHES=$(grep -rhoE "$PATTERNS" "$TARGET" 2>/dev/null || true)
else
  MATCHES=$(grep -hoE "$PATTERNS" "$TARGET" 2>/dev/null || true)
fi

if [ -z "$MATCHES" ]; then
  echo "WALKTHROUGH_LINT_PASS"
  exit 0
fi

# Report each distinct placeholder token once.
echo "$MATCHES" | sort -u | while IFS= read -r tok; do
  [ -n "$tok" ] && echo "WALKTHROUGH_LINT_FAIL token=$tok"
done

exit 1
