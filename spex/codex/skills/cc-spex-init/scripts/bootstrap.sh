#!/usr/bin/env sh
# bootstrap.sh - Run the Spex setup workflow from the Spex source bundled with
# the cc-spex Codex plugin (FR-008 to FR-011).
#
# Run from the project root. The source is resolved in this order:
#   1. SPEX_SOURCE (an explicit local Spex source)
#   2. ./spex (the cc-spex repository itself)
#   3. the bundled plugin tree, four directories above this script
# Nothing is cloned or downloaded, and no temporary directory is created.
#
# Exit codes: 0 success, 1 missing prerequisite or invalid source, 2 usage
# error. The exit code of `specify workflow run` is passed through.
set -eu

integration=codex
extensions=""
security=""
extensions_given=false
security_given=false

usage() {
  cat <<'EOF'
Usage: bootstrap.sh [OPTIONS]

Runs the Spex setup workflow from the Spex source bundled with the cc-spex
plugin (or from SPEX_SOURCE, or from ./spex in the cc-spex repository).

Options and defaults:
  --integration VALUE  codex (default), claude, opencode, auto
  --extensions VALUE   recommended (default), all, interactive, or NAME,NAME
  --security VALUE     safe (default), autonomous, yolo, interactive
  -h, --help           show this help

The extensions and security defaults apply only when the project has no
.specify/spex.json. With a declaration, its stored selection and security are
applied unless you pass --extensions or --security explicitly.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --integration|--extensions|--security)
      [ "$#" -ge 2 ] || { echo "ERROR: $1 requires a value" >&2; exit 2; }
      option=$1
      value=$2
      shift 2
      case "$option" in
        --integration) integration=$value ;;
        --extensions) extensions=$value; extensions_given=true ;;
        --security) security=$value; security_given=true ;;
      esac
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$integration" in codex|claude|opencode|auto) ;; *) echo "ERROR: invalid integration: $integration" >&2; exit 2 ;; esac
if [ "$security_given" = true ]; then
  case "$security" in safe|autonomous|yolo|interactive) ;; *) echo "ERROR: invalid security: $security" >&2; exit 2 ;; esac
fi
if [ "$extensions_given" = true ]; then
  case "$extensions" in
    recommended|all|interactive) ;;
    *)
      old_ifs=$IFS
      IFS=,
      set -f
      # shellcheck disable=SC2086
      set -- $extensions
      set +f
      IFS=$old_ifs
      [ "$#" -gt 0 ] || { echo "ERROR: invalid extensions: $extensions" >&2; exit 2; }
      for extension in "$@"; do
        case "$extension" in
          spex|spex-gates|spex-worktrees|spex-deep-review|spex-teams|spex-collab|spex-detach) ;;
          *) echo "ERROR: invalid extension: $extension" >&2; exit 2 ;;
        esac
      done
      ;;
  esac
fi

command -v specify >/dev/null 2>&1 || {
  echo "ERROR: specify CLI is required." >&2
  echo "Install it from https://github.com/github/spec-kit and retry." >&2
  exit 1
}
for tool in jq python3; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "ERROR: $tool is required by the Spex setup workflow. Install it and retry." >&2
    exit 1
  }
done

# --- Resolve the Spex source (FR-009, FR-010) ---
if [ -n "${SPEX_SOURCE:-}" ]; then
  if [ ! -f "$SPEX_SOURCE/setup.yml" ] || [ ! -d "$SPEX_SOURCE/extensions/spex" ]; then
    echo "ERROR: SPEX_SOURCE does not contain a Spex source tree: $SPEX_SOURCE" >&2
    echo "It must contain setup.yml and extensions/spex/." >&2
    exit 1
  fi
  source_dir=$(CDPATH='' cd -- "$SPEX_SOURCE" && pwd -P)
  source_kind=SPEX_SOURCE
elif [ -f "spex/setup.yml" ] && [ -d "spex/extensions/spex" ]; then
  source_dir=$(CDPATH='' cd -- spex && pwd -P)
  source_kind=repository
else
  script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P) || {
    echo "ERROR: cannot resolve the cc-spex plugin directory from $0." >&2
    echo "Set SPEX_SOURCE to a local Spex source (the spex/ directory of cc-spex) and retry." >&2
    exit 1
  }
  # <root>/codex/skills/cc-spex-init/scripts/bootstrap.sh
  source_dir=$(CDPATH='' cd -- "$script_dir/../../../.." && pwd -P) || {
    echo "ERROR: cannot resolve the cc-spex plugin root above $script_dir." >&2
    echo "Set SPEX_SOURCE to a local Spex source (the spex/ directory of cc-spex) and retry." >&2
    exit 1
  }
  for required in setup.yml extensions/spex/extension.yml; do
    if [ ! -f "$source_dir/$required" ]; then
      echo "ERROR: the bundled Spex source is incomplete: $source_dir/$required is missing." >&2
      echo "Reinstall or update the cc-spex plugin, or set SPEX_SOURCE to a local Spex source." >&2
      exit 1
    fi
  done
  source_kind=bundled
fi

# --- Workflow inputs (FR-011) ---
# integration is always passed. extensions and security are passed when given
# explicitly, or with their defaults when the project has no declaration.
set -- -i "integration=$integration"
summary="integration=$integration"
if [ "$extensions_given" = true ] || [ ! -f .specify/spex.json ]; then
  [ "$extensions_given" = true ] || extensions=recommended
  set -- "$@" -i "extensions=$extensions"
  summary="$summary extensions=$extensions"
else
  summary="$summary extensions=(from .specify/spex.json)"
fi
if [ "$security_given" = true ] || [ ! -f .specify/spex.json ]; then
  [ "$security_given" = true ] || security=safe
  set -- "$@" -i "security=$security"
  summary="$summary security=$security"
else
  # The declaration may be shared through the repository, so say which
  # security level it applies before anything is written.
  declared_security=$(jq -r '.security // "unknown"' .specify/spex.json 2>/dev/null || echo unknown)
  summary="$summary security=$declared_security (from .specify/spex.json)"
  case "$declared_security" in
    safe) ;;
    *) echo "NOTE: .specify/spex.json requests security=$declared_security; pass --security safe to keep the host policy." >&2 ;;
  esac
fi

echo "Initializing Spex from $source_kind source $source_dir: $summary" >&2
rc=0
result=$(SPEX_SOURCE="$source_dir" specify workflow run "$source_dir/setup.yml" --json "$@") || rc=$?
[ -z "$result" ] || printf '%s\n' "$result"

# The workflow engine keeps step messages in the run state. Print the
# extension changes and a failed step's error (FR-018, FR-019) on stderr.
report="$source_dir/scripts/spex-setup-report.sh"
if [ -n "$result" ] && [ -f "$report" ] && command -v jq >/dev/null 2>&1; then
  run_id=$(printf '%s' "$result" | jq -r '.run_id // empty' 2>/dev/null || true)
  case "$run_id" in
    ""|*/*|.*) ;;
    *) sh "$report" "$run_id" || true ;;
  esac
fi
exit "$rc"
