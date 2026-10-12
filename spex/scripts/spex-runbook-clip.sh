#!/bin/sh
# spex-runbook-clip.sh - Copy a command read from stdin to the system clipboard
# (research R7). Tries pbcopy, wl-copy, xclip, xsel in order.
#
# Output: CLIP_OK tool=<name> (exit 0), or CLIP_UNAVAILABLE (exit 3).
# Exit 2 when stdin is empty.

input=$(cat)
if [ -z "$input" ]; then
  echo "usage: pipe a command into spex-runbook-clip.sh" >&2
  exit 2
fi

try() { # bin  full-command...
  bin="$1"; shift
  if command -v "$bin" >/dev/null 2>&1; then
    if printf '%s' "$input" | "$@" >/dev/null 2>&1; then
      echo "CLIP_OK tool=$bin"
      exit 0
    fi
  fi
}

try pbcopy pbcopy
try wl-copy wl-copy
try xclip xclip -selection clipboard
try xsel xsel --clipboard --input

echo "CLIP_UNAVAILABLE"
exit 3
