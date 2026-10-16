#!/bin/sh
# resume-paused.sh - Mark a paused ship pipeline as running again
#
# Called by the prompt-submit hooks on every user prompt. When the session's
# checkout holds a ship state with status "paused", the user's reply is the
# answer the pipeline paused for, so the pipeline continues. This keeps the
# status line from showing "paused" after the run has moved on, without
# relying on the agent to call `spex-ship-state.sh resume`.
#
# Known trade-off: a reply like "stop here" also flips the status to running.
# The next `/speckit-spex-ship --resume` or `/speckit-spex-clear` corrects it.
#
# Usage:
#   sh resume-paused.sh <cwd> <plugin_root>
#
# Prints nothing on stdout. Always exits 0 (fail open: a hook must never
# block the user's prompt).

CWD="${1:-.}"
PLUGIN_ROOT="${2:-.}"

command -v jq >/dev/null 2>&1 || exit 0

ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || ROOT="$CWD"
STATE_FILE="$ROOT/.specify/.spex-state"
[ -f "$STATE_FILE" ] || exit 0

MODE=$(jq -r '.mode // empty' "$STATE_FILE" 2>/dev/null) || exit 0
STATUS=$(jq -r '.status // empty' "$STATE_FILE" 2>/dev/null) || exit 0
[ "$MODE" = "ship" ] && [ "$STATUS" = "paused" ] || exit 0

# Use the plugin's own state script: a project's installed copy may predate
# the `resume` command.
STATE_SCRIPT="$PLUGIN_ROOT/scripts/spex-ship-state.py"
[ -f "$STATE_SCRIPT" ] || exit 0

for py in python3 py python; do
  if command -v "$py" >/dev/null 2>&1; then
    SHIP_STATE_FILE="$STATE_FILE" "$py" "$STATE_SCRIPT" resume >/dev/null 2>&1 || true
    break
  fi
done
exit 0
