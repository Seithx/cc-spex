#!/bin/sh
# verify-gate.sh - Verify-before-commit enforcement
#
# Reminds about verification before git commit in spex projects.
# Non-blocking (returns context, not deny).
#
# Usage:
#   result=$(sh verify-gate.sh <tool_name> <command> <session_id> <cwd>)
#   # result is "context:<text>" or "allow"
#
# Reads .specify/.spex-state and the shared verification record via
# spex-verify-record.sh check (the same record finish reads; it is tied to the
# code state, not the session, so it survives /clear and new sessions).

set -eu

TOOL_NAME="${1:-}"
COMMAND="${2:-}"
SESSION_ID="${3:-unknown}"  # unused; kept for the adapter call interface
CWD="${4:-.}"

# Only applies to Bash tool
if [ "$TOOL_NAME" != "Bash" ]; then
  echo "allow"
  exit 0
fi

# Only applies to git commit commands
case "$COMMAND" in
  *git\ commit*|*git\ \ commit*) ;;
  *)
    echo "allow"
    exit 0
    ;;
esac

# Only applies in spex projects
if [ ! -d "$CWD/.specify" ]; then
  echo "allow"
  exit 0
fi

# Skip reminder during pre-implementation phases
STATE_FILE="$CWD/.specify/.spex-state"
if [ -f "$STATE_FILE" ] && command -v jq >/dev/null 2>&1; then
  MODE=$(jq -r '.mode // ""' "$STATE_FILE" 2>/dev/null || echo "")
  IMPLEMENTED=$(jq -r '.implemented // false' "$STATE_FILE" 2>/dev/null || echo "false")
  if [ "$MODE" = "flow" ] && [ "$IMPLEMENTED" != "true" ]; then
    echo "allow"
    exit 0
  fi
fi

# Check if this is a spec-only commit (no code to verify)
if command -v git >/dev/null 2>&1; then
  STAGED=$(git -C "$CWD" diff --cached --name-only 2>/dev/null || echo "")
  if [ -n "$STAGED" ]; then
    SPEC_ONLY=true
    for f in $STAGED; do
      case "$f" in
        specs/*|brainstorm/*|docs/*|.specify/*|*.md) continue ;;
        *) SPEC_ONLY=false; break ;;
      esac
    done
    if [ "$SPEC_ONLY" = "true" ]; then
      echo "allow"
      exit 0
    fi
  fi
fi

# Skip if a verification pass is recorded for the current code state.
# Runs last because it hashes the working tree; the cheap skips above go
# first. Missing script or any error means "not verified" (the reminder fires).
RECORD="$(dirname "$0")/../../spex-verify-record.sh"
[ -f "$RECORD" ] || RECORD="$CWD/.specify/extensions/spex-gates/scripts/spex-verify-record.sh"
if [ -f "$RECORD" ] && (cd "$CWD" && sh "$RECORD" check >/dev/null 2>&1); then
  echo "allow"
  exit 0
fi

echo "context:spex verify reminder: No verification is recorded for the current code. Consider running /speckit-spex-gates-verify or /speckit-spex-finish first, or confirm with the user that they want to proceed without the final gate."
