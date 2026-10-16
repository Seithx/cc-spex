#!/usr/bin/env bash
# spex-worktree.sh - Feature worktree lifecycle for the spex-worktrees extension
#
# Usage:
#   spex-worktree.sh prepare --short-name <name> [--description <text>] [--branch <exact-name>]
#       Create the feature worktree before the spec is written (before_specify).
#   spex-worktree.sh finalize
#       Confirm branch, worktree directory, feature.json and state (after_specify).
#   spex-worktree.sh adopt
#       Legacy path: move a feature branch checked out in the main checkout
#       into a new worktree (finalize fallback, ensure action).
#
# Output is line-oriented. The first stdout line is a machine-readable status
# line (`WORKTREE_<STATUS> key=value ...`). Human-readable lines follow, and
# when the caller has to change directory the last line is `cd <abs-path>`.
# Errors go to stderr and start with `ERROR:`.
#
# Exit codes: 0 success (including READY and SKIPPED), 1 failure (nothing
# changed, or every change rolled back), 2 usage error.
#
# Contract: specs/056-worktree-with-branch/contracts/spex-worktree-cli.md

set -euo pipefail

REGISTRY_REL=".specify/extensions/.registry"
WORKTREE_CONFIG_REL=".specify/extensions/spex-worktrees/worktree-config.yml"
GIT_FEATURE_SCRIPT_REL=".specify/extensions/git/scripts/bash/create-new-feature.sh"
STATE_REL=".specify/.spex-state"
DEFAULT_BASE_PATH=".claude/worktrees"
ADOPT_NOTE=""

usage() {
  cat >&2 <<'EOF'
Usage:
  spex-worktree.sh prepare --short-name <name> [--description <text>] [--branch <exact-name>]
  spex-worktree.sh finalize
  spex-worktree.sh adopt
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

# Absolute, symlink-free path of the current checkout's top level.
current_root() {
  local top
  top=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  (cd "$top" && pwd -P)
}

# Absolute path of the main checkout (first entry of `git worktree list`).
main_root() {
  local top
  top=$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
  [ -n "$top" ] || return 1
  (cd "$top" && pwd -P)
}

# True when spex-worktrees is enabled in the registry of the current checkout
# (or of the main checkout, for a worktree that has no copied config).
worktrees_enabled() {
  local root registry
  root=$(current_root) || return 1
  registry="$root/$REGISTRY_REL"
  if [ ! -f "$registry" ]; then
    root=$(main_root) || return 1
    registry="$root/$REGISTRY_REL"
  fi
  [ -f "$registry" ] || return 1
  jq -e '(.extensions["spex-worktrees"] // null) as $e | $e != null and $e.enabled != false' \
    "$registry" >/dev/null 2>&1
}

# Print the default branch name: origin/HEAD, then a local main, then master.
# Returns 1 when none resolves.
resolve_default_branch() {
  local b candidate
  b=$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)
  if [ -n "$b" ] && { git show-ref --verify --quiet "refs/heads/$b" || git show-ref --verify --quiet "refs/remotes/origin/$b"; }; then
    echo "$b"
    return 0
  fi
  for candidate in main master; do
    if git show-ref --verify --quiet "refs/heads/$candidate"; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

# Commit of the default branch's local tip (falls back to origin/<name> when
# only the remote-tracking branch exists).
default_tip() {
  local b="$1"
  git rev-parse -q --verify "refs/heads/$b^{commit}" 2>/dev/null ||
    git rev-parse -q --verify "refs/remotes/origin/$b^{commit}" 2>/dev/null
}

default_branch_error() {
  echo "ERROR: cannot determine the default branch" >&2
  echo "Set it with 'git remote set-head origin --auto', or create a local 'main' or 'master' branch." >&2
}

# Configured worktree base path (default .claude/worktrees).
read_base_path() {
  local root="$1" cfg base=""
  cfg="$root/$WORKTREE_CONFIG_REL"
  if [ -f "$cfg" ] && command -v yq >/dev/null 2>&1; then
    base=$(yq -r '.worktrees.base_path // ""' "$cfg" 2>/dev/null || true)
  fi
  if [ -z "$base" ] || [ "$base" = "null" ]; then
    base="$DEFAULT_BASE_PATH"
  fi
  echo "$base"
}

# True for names that are safe to splice into the `cd <path>` line the
# agent runs: no shell metacharacters, no whitespace.
safe_path_chars() {
  [[ "$1" =~ ^[A-Za-z0-9._/@+-]+$ ]]
}

# validate_base_path <base>: reject values that would reach the agent's
# shell unquoted, and `..` components below .claude/worktrees (that prefix
# is joined without resolving, so `..` could lead back into the repo).
# External base paths are resolved with `pwd -P` and checked afterwards.
validate_base_path() {
  local base="$1"
  if ! safe_path_chars "$base"; then
    echo "ERROR: worktrees.base_path '$base' contains unsupported characters (allowed: letters, digits, . _ / @ + -)" >&2
    return 1
  fi
  case "$base" in
    .claude/worktrees/*)
      case "/$base/" in
        */../*|*/./*)
          echo "ERROR: worktrees.base_path '$base' must not contain '.' or '..' components below .claude/worktrees" >&2
          return 1
          ;;
      esac
      ;;
  esac
  return 0
}

# compute_worktree_path <branch>: print the worktree path for a branch,
# relative to the main checkout. Inside-project base paths (.claude/worktrees)
# give <repo>/<base>/<branch>; any other base gives <base>/<repo>@<branch>.
compute_worktree_path() {
  local branch="$1" root base resolved path
  root=$(main_root) || { echo "ERROR: cannot locate the main checkout" >&2; return 1; }
  base=$(read_base_path "$root")
  base="${base%/}"
  validate_base_path "$base" || {
    echo "Fix worktrees.base_path in $WORKTREE_CONFIG_REL" >&2
    return 1
  }
  if ! safe_path_chars "$branch"; then
    echo "ERROR: branch name '$branch' contains unsupported characters for a worktree path" >&2
    return 1
  fi

  case "$base" in
    .claude/worktrees|.claude/worktrees/*)
      path="$root/$base/$branch"
      ;;
    *)
      if [[ "$base" = /* ]]; then
        resolved=$(cd "$base" 2>/dev/null && pwd -P) || resolved=""
      else
        resolved=$(cd "$root/$base" 2>/dev/null && pwd -P) || resolved=""
      fi
      if [ -z "$resolved" ]; then
        echo "ERROR: base_path '$base' does not resolve to a valid directory" >&2
        echo "Check worktrees.base_path in $WORKTREE_CONFIG_REL" >&2
        return 1
      fi
      path="$resolved/$(basename "$root")@$branch"
      ;;
  esac

  case "$path" in
    "$root"/.claude/worktrees/*) ;;
    "$root"/*)
      echo "ERROR: worktree path is inside the main repository: $path" >&2
      echo "Set base_path to '.claude/worktrees' or a directory outside the repo" >&2
      return 1
      ;;
  esac
  echo "$path"
}

# True when the current directory belongs to a linked worktree (not the main
# checkout).
in_linked_worktree() {
  local git_dir common_dir
  git_dir=$(cd "$(git rev-parse --git-dir 2>/dev/null)" 2>/dev/null && pwd -P) || return 1
  common_dir=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P) || return 1
  [ "$git_dir" != "$common_dir" ]
}

# True for sequential (NNN-) and timestamp (YYYYMMDD-HHMMSS-) feature branches.
is_feature_branch() {
  local name="${1:-}"
  [[ "$name" =~ ^[0-9]{3}- ]] || [[ "$name" =~ ^[0-9]{8}-[0-9]{6}- ]]
}

# Current branch name, empty when HEAD is detached.
current_branch() {
  git symbolic-ref -q --short HEAD 2>/dev/null || true
}

# Human-readable name of the checked-out ref.
describe_head() {
  local b
  b=$(current_branch)
  if [ -n "$b" ]; then
    echo "$b"
  else
    echo "detached HEAD at $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  fi
}

# Path shown to the user: relative for inside-project worktrees.
display_path() {
  local path="$1" root
  root=$(main_root 2>/dev/null || echo "")
  case "$path" in
    "$root"/*) echo "${path#"$root"/}" ;;
    *) echo "$path" ;;
  esac
}

# copy_config <src-root> <dst-root>: copy the gitignored configuration a
# worktree needs. Per-session state files are excluded: only state that
# belongs to the running specify is moved in (move_matching_state).
copy_config() {
  local src="$1" dst="$2"
  command -v rsync >/dev/null 2>&1 || { echo "ERROR: rsync is required to copy configuration" >&2; return 1; }

  if [ -d "$src/.specify" ]; then
    rsync -a --exclude='.git' \
      --exclude='/.spex-state' --exclude='/.pr-triage-state.json' --exclude='/.*-state*' \
      "$src/.specify/" "$dst/.specify/" || return 1
  fi
  if [ -d "$src/.claude" ]; then
    rsync -a --exclude='/worktrees/' "$src/.claude/" "$dst/.claude/" || return 1
  fi

  # Only gitignored configuration comes from the source checkout. Tracked
  # files under .specify/ and .claude/ go back to the worktree's own commit,
  # so uncommitted edits in the main checkout (possibly another session's)
  # never reach the feature branch.
  local dir
  for dir in .specify .claude; do
    if [ -n "$(git -C "$dst" ls-files -- "$dir" 2>/dev/null | head -1)" ]; then
      git -C "$dst" checkout -q -- "$dir" || return 1
    fi
  done

  # Symlinks under .claude/ and .specify/ that point elsewhere inside the repo
  # (for example .claude/skills -> ../.agents/skills/) dangle in a fresh
  # worktree when their target is gitignored. Copy such targets.
  local link target rel
  while IFS= read -r link; do
    [ -n "$link" ] || continue
    target=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$src/$link" 2>/dev/null) || continue
    [ -d "$target" ] || continue
    case "$target" in
      "$src"/*) rel="${target#"$src"/}" ;;
      *) continue ;;
    esac
    case "$rel" in
      .claude/*|.specify/*) continue ;;
    esac
    [ -e "$dst/$rel" ] && continue
    mkdir -p "$dst/$(dirname "$rel")" || return 1
    rsync -a "$target/" "$dst/$rel/" || return 1
  done < <(cd "$src" && find .claude .specify -path '.claude/worktrees' -prune -o -type l -print 2>/dev/null || true)
  return 0
}

# move_matching_state <src-root> <dst-root> [<late-branch>]: move
# .specify/.spex-state into the worktree only when it belongs to the specify
# run in progress. Any other state may belong to another session and stays.
# Copies first and removes the source only after the copy succeeded, so a
# failure never loses the state. Returns 1 on failure.
move_matching_state() {
  local src="$1" dst="$2" late_branch="${3:-}" state
  state="$src/$STATE_REL"
  [ -f "$state" ] || return 0
  if jq -e --arg lb "$late_branch" '
      (.mode == "flow" and .running == "specify")
      or (.mode == "ship" and .stage == "specify")
      or ($lb != "" and .mode == "flow" and .feature_branch == $lb)
    ' "$state" >/dev/null 2>&1; then
    mkdir -p "$dst/.specify" || return 1
    cp -p "$state" "$dst/$STATE_REL" || { rm -f "$dst/$STATE_REL"; return 1; }
    rm -f "$state" || return 1
    echo "Moved $STATE_REL into the worktree."
  fi
  return 0
}

# Branch numbering mode of the git extension: git-config.yml, then
# init-options.json, default sequential (same order as speckit.git.feature).
branch_numbering() {
  local root="$1" mode=""
  if [ -f "$root/.specify/extensions/git/git-config.yml" ] && command -v yq >/dev/null 2>&1; then
    mode=$(yq -r '.branch_numbering // ""' "$root/.specify/extensions/git/git-config.yml" 2>/dev/null || true)
  fi
  if { [ -z "$mode" ] || [ "$mode" = "null" ]; } && [ -f "$root/.specify/init-options.json" ]; then
    mode=$(jq -r '.branch_numbering // ""' "$root/.specify/init-options.json" 2>/dev/null || true)
  fi
  case "$mode" in
    timestamp) echo "timestamp" ;;
    *) echo "sequential" ;;
  esac
}

# Marker files in a linked worktree's own git dir (never tracked, never
# shared with other worktrees). `spex-prepared` holds the planned branch name
# and is written by prepare; finalize renames it to `spex-finalized`. Only
# worktrees carrying one of them were created by this script.
MARKER_PREPARED="spex-prepared"
MARKER_FINALIZED="spex-finalized"
# Content hashes of the untracked files prepare put into the worktree.
MARKER_MANIFEST="spex-prepared-files"

# worktree_git_dir <path>: absolute git dir of a worktree.
worktree_git_dir() {
  git -C "$1" rev-parse --absolute-git-dir 2>/dev/null
}

# write_prepared_marker <path> <branch>
write_prepared_marker() {
  local gd
  gd=$(worktree_git_dir "$1") || return 1
  printf '%s\n' "$2" > "$gd/$MARKER_PREPARED"
}

# untracked_manifest <path>: "<blob-hash>\t<path>" for every untracked file
# (ignored ones included) except symlinks and the moved state, sorted.
untracked_manifest() {
  local wt="$1" list hashes
  list=$(cd "$wt" && git ls-files --others 2>/dev/null | while IFS= read -r f; do
    [ "$f" = "$STATE_REL" ] && continue
    [ -L "$f" ] && continue
    printf '%s\n' "$f"
  done) || return 1
  [ -n "$list" ] || return 0
  hashes=$(cd "$wt" && printf '%s\n' "$list" | git hash-object --stdin-paths) || return 1
  paste <(printf '%s\n' "$hashes") <(printf '%s\n' "$list") | LC_ALL=C sort
}

# write_prepared_manifest <path>: record what prepare copied into the
# worktree, so finalize can tell later whether anything else was added.
write_prepared_manifest() {
  local gd
  gd=$(worktree_git_dir "$1") || return 1
  untracked_manifest "$1" > "$gd/$MARKER_MANIFEST"
}

# True when the worktree at <path> was created by prepare (finalized or not).
created_by_prepare() {
  local gd
  gd=$(worktree_git_dir "$1") || return 1
  [ -f "$gd/$MARKER_PREPARED" ] || [ -f "$gd/$MARKER_FINALIZED" ]
}

# Linked worktrees created by prepare and not finalized yet. Prints
# `<path>\t<planned-branch>` per line.
list_prepared_worktrees() {
  local line path gd first=yes
  while IFS= read -r line; do
    case "$line" in
      "worktree "*)
        path="${line#worktree }"
        if [ "$first" = yes ]; then first=no; continue; fi
        gd=$(worktree_git_dir "$path") || continue
        [ -f "$gd/$MARKER_PREPARED" ] || continue
        printf '%s\t%s\n' "$path" "$(head -1 "$gd/$MARKER_PREPARED")"
        ;;
    esac
  done < <(git worktree list --porcelain 2>/dev/null)
}

# clean_short_name <text>: the git extension's short-name normalization
# (lowercase, non-alphanumerics to '-', squeezed and trimmed).
clean_short_name() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g; s/^-//; s/-$//'
}

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

# Remove a partly created worktree. Never touches the main checkout.
remove_partial_worktree() {
  local path="$1"
  if git worktree list --porcelain 2>/dev/null | grep -qxF "worktree $path"; then
    git worktree remove --force "$path" >/dev/null 2>&1 || true
  fi
  git worktree prune >/dev/null 2>&1 || true
}

# True when a linked worktree looks like it was just prepared on purpose by
# prepare (ship, brainstorm handoff, or the before_specify hook): HEAD is
# detached, or HEAD is a feature branch without commits beyond the default
# branch and without a written spec.
prepared_on_purpose() {
  local default="$1" branch tip count gd
  gd=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
  [ -n "$gd" ] && [ -f "$gd/$MARKER_PREPARED" ] && return 0
  branch=$(current_branch)
  [ -z "$branch" ] && return 0
  is_feature_branch "$branch" || return 1
  [ -n "$default" ] || return 1
  tip=$(default_tip "$default") || return 1
  count=$(git rev-list --count "$tip..HEAD" 2>/dev/null) || return 1
  [ "$count" = "0" ] || return 1
  [ ! -f "$(current_root)/specs/$branch/spec.md" ]
}

# A branch created longer ago than this (seconds, from its reflog) is never
# taken for the branch git.feature just created in this run.
LATE_WINDOW_SECONDS=600

# detect_late_branch <default> <wanted-branch> <short-name>
# Late mode applies when git.feature already created and checked out this
# run's feature branch in the main checkout. Sets LATE_BRANCH when it does.
# Sets LATE_ERROR when the main checkout sits on a feature branch that was
# created moments ago but cannot safely be taken over (another run's branch,
# or commits on it); the caller must stop then. Otherwise both stay empty and
# the early path runs.
detect_late_branch() {
  local default="$1" want="$2" short="$3" root branch prev_tip created now suffix match
  LATE_BRANCH=""
  LATE_ERROR=""
  root=$(current_root) || return 0
  branch=$(current_branch)
  [ -n "$branch" ] || return 0
  [ ! -e "$root/specs/$branch" ] || return 0
  # An exact --branch / GIT_BRANCH_NAME may use any valid name.
  if [ -z "$want" ] || [ "$branch" != "$want" ]; then
    is_feature_branch "$branch" || return 0
  fi
  [ "$branch" != "$default" ] || return 0
  # No other worktree has the branch checked out.
  [ "$(git worktree list --porcelain | grep -cxF "branch refs/heads/$branch")" = "1" ] || return 0
  # Created moments ago (oldest reflog entry). A stale branch, for example
  # one made by hand long ago, is left alone. Without a reflog, skip this.
  created=$(git reflog show --date=unix --format=%gd "refs/heads/$branch" -- 2>/dev/null | tail -1 || true)
  created="${created##*@\{}"
  created="${created%\}}"
  if [[ "$created" =~ ^[0-9]+$ ]]; then
    now=$(date +%s)
    [ $((now - created)) -le "$LATE_WINDOW_SECONDS" ] || return 0
  fi
  # It must be the branch this run asked for.
  match=yes
  if [ -n "$want" ]; then
    [ "$branch" = "$want" ] || match=no
  elif [ -n "$short" ]; then
    suffix=$(clean_short_name "$short")
    case "$branch" in
      *-"$suffix") ;;
      *) match=no ;;
    esac
  fi
  if [ "$match" = no ]; then
    LATE_ERROR="the main checkout is on '$branch', a feature branch created moments ago that does not match this run (${want:-short name '$short'}). Another session may be specifying it right now, so it is left alone. Retry in a moment, or switch the main checkout back to its previous branch and run /speckit-specify again."
    return 0
  fi
  # No commits of its own: the tip equals the previously checked-out ref.
  prev_tip=$(git rev-parse -q --verify '@{-1}^{commit}' 2>/dev/null) || return 0
  if [ "$prev_tip" != "$(git rev-parse HEAD)" ]; then
    LATE_ERROR="the main checkout is on '$branch', created by this run's git.feature, but it already has commits of its own (another session may have committed onto it). Nothing was changed. Move those commits to the right branch, switch the main checkout back with 'git checkout -', delete '$branch', then run /speckit-specify again."
    return 0
  fi
  LATE_BRANCH="$branch"
}

prepare_late() {
  local branch="$1" default="$2" root prev_name prev_sha path tip created=""
  root=$(current_root)
  prev_name=$(git rev-parse --abbrev-ref '@{-1}' 2>/dev/null || true)
  prev_sha=$(git rev-parse '@{-1}^{commit}')
  tip=$(default_tip "$default")

  # Restore the main checkout first, so it is switched for as short a time
  # as possible. The branch has no commits, so this never touches changes.
  if [ -n "$prev_name" ]; then
    git checkout -q "$prev_name" -- || die "could not restore the main checkout to '$prev_name'"
  else
    git checkout -q --detach "$prev_sha" || die "could not restore the main checkout to $prev_sha"
    prev_name="detached HEAD at $(git rev-parse --short "$prev_sha")"
  fi

  # From here on, a failure deletes the commit-less branch created by
  # git.feature and never checks it out in the main checkout again. Only a
  # worktree this run created is removed; an existing path is never touched.
  late_fail() {
    if [ -n "$created" ]; then
      remove_partial_worktree "$path"
    fi
    git branch -D "$branch" >/dev/null 2>&1 || true
    echo "The main checkout stays on '$prev_name'. The commit-less branch '$branch' was deleted." >&2
    exit 1
  }

  path=$(compute_worktree_path "$branch") || late_fail
  if [ -e "$path" ]; then
    echo "ERROR: target path already exists: $path" >&2
    echo "Remove it, or set a different worktrees.base_path in $WORKTREE_CONFIG_REL, then run /speckit-specify again." >&2
    late_fail
  fi

  # Keep FR-017: the branch starts from the default branch tip even when
  # git.feature branched from another ref. Safe: the branch has no commits.
  git branch -f "$branch" "$tip" >/dev/null 2>&1 || {
    echo "ERROR: could not reset '$branch' to the '$default' tip" >&2
    late_fail
  }

  mkdir -p "$(dirname "$path")" || late_fail
  if ! git worktree add -q "$path" "$branch" >&2; then
    echo "ERROR: git worktree add failed for $path" >&2
    # A failed add may still have registered or created the path.
    created=yes
    late_fail
  fi
  created=yes
  if ! write_prepared_marker "$path" "$branch"; then
    echo "ERROR: could not mark $path as prepared" >&2
    late_fail
  fi
  if ! copy_config "$root" "$path"; then
    echo "ERROR: copying configuration into $path failed" >&2
    late_fail
  fi
  local moved_msg
  if ! moved_msg=$(move_matching_state "$root" "$path" "$branch"); then
    echo "ERROR: moving $STATE_REL into $path failed" >&2
    late_fail
  fi
  # Best effort: without a manifest, finalize never removes this worktree.
  write_prepared_manifest "$path" || true

  echo "WORKTREE_PREPARED path=$path branch=$branch base=$default mode=late"
  echo "NOTICE: hook order: git.feature ran before the worktree step; main checkout was restored to '$prev_name'"
  if [ "$(current_branch)" != "$default" ]; then
    echo "NOTICE: main checkout is on '$prev_name', new branch starts from '$default'"
  fi
  [ -z "$moved_msg" ] || echo "$moved_msg"
  echo "Worktree ready at $(display_path "$path") on branch $branch. Continue /speckit-specify there."
  echo "cd $path"
}

cmd_prepare() {
  local short_name="" description="" branch=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --short-name) [ $# -ge 2 ] || { usage; exit 2; }; short_name="$2"; shift 2 ;;
      --description) [ $# -ge 2 ] || { usage; exit 2; }; description="$2"; shift 2 ;;
      --branch) [ $# -ge 2 ] || { usage; exit 2; }; branch="$2"; shift 2 ;;
      *) echo "ERROR: unknown argument: $1" >&2; usage; exit 2 ;;
    esac
  done
  branch="${branch:-${GIT_BRANCH_NAME:-}}"

  local root default=""
  root=$(current_root) || die "not inside a git working tree"

  # A disabled extension never fails, whatever the repository state (FR-012).
  if ! worktrees_enabled; then
    echo "WORKTREE_SKIPPED reason=spex-worktrees-disabled"
    return 0
  fi

  # 1. Default branch. Inside a worktree a failure here only means the
  #    nesting warning plus READY.
  if ! default=$(resolve_default_branch); then
    default=""
    if in_linked_worktree; then
      echo "WORKTREE_READY path=$root"
      echo "WARNING: already inside a worktree, nesting is not supported; using the current worktree"
      echo "cd $root"
      return 0
    fi
    default_branch_error
    exit 1
  fi

  # 2. Already inside a worktree: use it.
  if in_linked_worktree; then
    echo "WORKTREE_READY path=$root"
    if ! prepared_on_purpose "$default"; then
      echo "WARNING: already inside a worktree, nesting is not supported; using the current worktree"
    fi
    echo "cd $root"
    return 0
  fi

  # 3. Late mode: git.feature already switched the main checkout.
  detect_late_branch "$default" "$branch" "$short_name"
  if [ -n "$LATE_ERROR" ]; then
    echo "ERROR: $LATE_ERROR" >&2
    exit 1
  fi
  if [ -n "$LATE_BRANCH" ]; then
    prepare_late "$LATE_BRANCH" "$default"
    return 0
  fi

  # 4. Early mode.
  if [ -z "$branch" ]; then
    [ -n "$short_name" ] || { echo "ERROR: --short-name or --branch is required" >&2; usage; exit 2; }
    local feature_script="$root/$GIT_FEATURE_SCRIPT_REL" json err
    if [ ! -f "$feature_script" ]; then
      echo "ERROR: $GIT_FEATURE_SCRIPT_REL not found; spex-worktrees requires the spec-kit git extension" >&2
      echo "Fix: run 'specify extension add git' (or 'specify extension enable git'), or disable spex-worktrees." >&2
      exit 1
    fi
    # Same numbering mode as speckit.git.feature. A timestamp computed now
    # can differ by a few seconds from the one git.feature computes later;
    # finalize then moves the worktree directory to match the branch.
    local numbering_flag=()
    if [ "$(branch_numbering "$root")" = "timestamp" ]; then
      numbering_flag=(--timestamp)
    fi
    err=$(mktemp)
    if ! json=$(cd "$root" && bash "$feature_script" --dry-run --json ${numbering_flag[@]+"${numbering_flag[@]}"} --short-name "$short_name" "${description:-$short_name}" 2>"$err"); then
      echo "ERROR: computing the branch name failed:" >&2
      cat "$err" >&2
      rm -f "$err"
      exit 1
    fi
    rm -f "$err"
    branch=$(printf '%s\n' "$json" | grep '^{' | tail -1 | jq -r '.BRANCH_NAME // empty' 2>/dev/null || true)
    [ -n "$branch" ] || die "the git extension's dry run returned no BRANCH_NAME"
  fi

  git check-ref-format --branch "$branch" >/dev/null 2>&1 || die "invalid branch name '$branch'"
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    echo "ERROR: branch '$branch' already exists" >&2
    echo "Pick a different short name, or remove the branch if it is left over from an earlier run." >&2
    exit 1
  fi

  local tip path notice=""
  tip=$(default_tip "$default") || { default_branch_error; exit 1; }
  if [ "$(current_branch)" != "$default" ]; then
    notice="NOTICE: main checkout is on '$(describe_head)', new branch starts from '$default'"
  fi

  path=$(compute_worktree_path "$branch") || exit 1
  if [ -e "$path" ]; then
    echo "ERROR: target path already exists: $path" >&2
    echo "Remove it, or set a different worktrees.base_path in $WORKTREE_CONFIG_REL." >&2
    exit 1
  fi

  mkdir -p "$(dirname "$path")"
  if ! git worktree add -q --detach "$path" "$tip" >&2; then
    remove_partial_worktree "$path"
    echo "ERROR: git worktree add failed for $path" >&2
    exit 1
  fi
  if ! write_prepared_marker "$path" "$branch"; then
    remove_partial_worktree "$path"
    echo "ERROR: could not mark $path as prepared; the worktree was removed" >&2
    exit 1
  fi
  if ! copy_config "$root" "$path"; then
    remove_partial_worktree "$path"
    echo "ERROR: copying configuration into $path failed; the worktree was removed" >&2
    exit 1
  fi
  local moved_msg
  if ! moved_msg=$(move_matching_state "$root" "$path"); then
    remove_partial_worktree "$path"
    echo "ERROR: moving $STATE_REL into $path failed; the worktree was removed" >&2
    exit 1
  fi
  # Best effort: without a manifest, finalize never removes this worktree.
  write_prepared_manifest "$path" || true

  echo "WORKTREE_PREPARED path=$path branch=$branch base=$default mode=early"
  [ -z "$notice" ] || echo "$notice"
  [ -z "$moved_msg" ] || echo "$moved_msg"
  echo "Worktree prepared at $(display_path "$path") (detached at the '$default' tip)."
  echo "Run the rest of /speckit-specify there; git.feature creates '$branch' inside the worktree."
  echo "cd $path"
}

# Resolve the spec directory for finalize (relative to the worktree root).
resolve_spec_dir() {
  local root="$1" branch="$2" fj="" candidate
  if [ -f "$root/.specify/feature.json" ]; then
    fj=$(jq -r '.feature_directory // empty' "$root/.specify/feature.json" 2>/dev/null || true)
    fj="${fj%/}"
    fj="${fj#"$root"/}"
  fi
  if [ -n "$fj" ] && [ -f "$root/$fj/spec.md" ]; then
    echo "$fj"
    return 0
  fi
  if [ -f "$root/specs/$branch/spec.md" ]; then
    echo "specs/$branch"
    return 0
  fi
  # Newest feature spec directory (by spec.md modification time).
  # shellcheck disable=SC2012
  candidate=$(cd "$root" && ls -t specs/*/spec.md 2>/dev/null |
    grep -E '^specs/([0-9]{3}|[0-9]{8}-[0-9]{6})-[^/]+/spec\.md$' | head -1 || true)
  if [ -n "$candidate" ]; then
    echo "${candidate%/spec.md}"
    return 0
  fi
  return 1
}

# prepared_worktree_unused <worktree> <main-root>: true when the worktree
# holds nothing but what prepare put there. No tracked changes, no spec
# content, symlinks identical to the main checkout's, and every other
# untracked file (ignored ones included) recorded with the same content in
# the manifest prepare wrote. Anything else would be lost when the worktree
# is removed. Fails closed: no manifest or an unreadable worktree means used.
prepared_worktree_unused() {
  local wt="$1" root="$2" gd manifest tracked current f
  gd=$(worktree_git_dir "$wt") || return 1
  manifest="$gd/$MARKER_MANIFEST"
  [ -f "$gd/$MARKER_PREPARED" ] && [ -f "$manifest" ] || return 1
  tracked=$(git -C "$wt" status --porcelain --untracked-files=no 2>/dev/null) || return 1
  [ -z "$tracked" ] || return 1
  while IFS= read -r -d '' f; do
    case "$f" in
      specs/*) return 1 ;;
    esac
    if [ -L "$wt/$f" ]; then
      [ -L "$root/$f" ] && [ "$(readlink "$wt/$f")" = "$(readlink "$root/$f")" ] || return 1
    fi
  done < <(git -C "$wt" ls-files --others -z 2>/dev/null)
  current=$(untracked_manifest "$wt") || return 1
  [ -z "$current" ] && return 0
  [ -z "$(printf '%s\n' "$current" | grep -vxF -f "$manifest")" ]
}

# finalize run in the main checkout while it is on feature branch <branch>.
finalize_from_main() {
  local root="$1" branch="$2" prepared own_path
  prepared=$(list_prepared_worktrees)
  own_path=$(printf '%s\n' "$prepared" | awk -F'\t' -v b="$branch" '$2 == b { print $1; exit }')

  if [ -n "$own_path" ]; then
    # prepare created a worktree for exactly this branch, but git.feature
    # then ran in the main checkout (for example after a working-directory
    # reset). The worktree is detached (the branch is checked out here) and
    # holds only copied configuration and state. When it is otherwise clean,
    # hand the state back, remove it, and move the branch with adopt.
    if ! prepared_worktree_unused "$own_path" "$root"; then
      echo "WORKTREE_SKIPPED reason=prepared-worktree-exists"
      echo "WARNING: finalize ran in the main checkout on '$branch', and the worktree prepared for it at $own_path has changes. Nothing was changed."
      echo "Move the work into one place by hand: either commit the spec on '$branch' here, or remove $own_path."
      return 0
    fi
    if [ -f "$own_path/$STATE_REL" ] && [ -f "$root/$STATE_REL" ]; then
      # Two states. The flow-state hooks that ran in the main checkout after
      # the reset write a flow state for this branch there; the worktree's
      # state (possibly a ship state) is the original and wins. The main
      # checkout's copy is kept as a backup. Any other state may belong to
      # another session, and removing the worktree would delete this run's
      # only copy, so stop.
      if jq -e --arg b "$branch" '.mode == "flow" and ((.feature_branch // "") == "" or .feature_branch == $b)' \
           "$root/$STATE_REL" >/dev/null 2>&1; then
        mv -f "$root/$STATE_REL" "$root/$STATE_REL.bak-$(printf '%s' "$branch" | tr '/' '_')" ||
          die "could not back up $STATE_REL in the main checkout"
      else
        echo "WORKTREE_SKIPPED reason=prepared-worktree-exists"
        echo "WARNING: finalize ran in the main checkout on '$branch'. The worktree prepared for it at $own_path holds this run's $STATE_REL, and the main checkout has a different one. Nothing was changed."
        echo "Decide which state belongs to this feature, remove the other, then run finalize again."
        return 0
      fi
    fi
    if [ -f "$own_path/$STATE_REL" ]; then
      mkdir -p "$root/.specify"
      cp -p "$own_path/$STATE_REL" "$root/$STATE_REL" || die "could not copy $STATE_REL back from $own_path"
    fi
    git worktree remove --force "$own_path" >&2 || die "could not remove the unused prepared worktree $own_path"
    ADOPT_NOTE="NOTICE: speckit.git.feature ran in the main checkout instead of the prepared worktree; the unused worktree was removed and '$branch' was moved into a new one."
    adopt_impl "WORKTREE_ADOPTED"
    return 0
  fi

  if [ -n "$prepared" ]; then
    # Another prepared worktree exists, so prepare ran and this finalize was
    # started from the main checkout by mistake. The main checkout may sit
    # on an unrelated old-flow feature branch then, so never adopt it.
    echo "WORKTREE_SKIPPED reason=prepared-worktree-exists"
    echo "WARNING: finalize ran in the main checkout, but a prepared feature worktree exists. The main checkout was left alone."
    echo "Change into the worktree of this feature and run finalize there:"
    printf '%s\n' "$prepared" | cut -f1 | sed 's/^/  /'
    return 0
  fi

  # prepare was skipped: fall back to the legacy move.
  adopt_impl "WORKTREE_ADOPTED"
}

cmd_finalize() {
  [ $# -eq 0 ] || { usage; exit 2; }
  local root branch
  root=$(current_root) || die "not inside a git working tree"

  if ! worktrees_enabled; then
    echo "WORKTREE_SKIPPED reason=spex-worktrees-disabled"
    return 0
  fi

  branch=$(current_branch)
  if ! in_linked_worktree; then
    if is_feature_branch "$branch"; then
      finalize_from_main "$root" "$branch"
      return 0
    fi
    echo "WORKTREE_SKIPPED reason=not-on-a-feature-branch"
    return 0
  fi

  local ours=""
  created_by_prepare "$root" && ours=yes
  if [ -z "$branch" ]; then
    if [ -n "$ours" ]; then
      echo "ERROR: this worktree was prepared for /speckit-specify, but no feature branch was created in it (speckit.git.feature did not run here, or failed)" >&2
      echo "Run speckit.git.feature inside $root, or remove the worktree (git worktree remove --force $root) and run /speckit-specify again." >&2
      exit 1
    fi
    echo "WORKTREE_SKIPPED reason=not-on-a-feature-branch"
    return 0
  fi
  # A worktree prepare created is finalized whatever the branch name looks
  # like (GIT_BRANCH_NAME / --branch may name any valid branch).
  if ! is_feature_branch "$branch" && [ -z "$ours" ]; then
    echo "WORKTREE_SKIPPED reason=not-on-a-feature-branch"
    return 0
  fi

  # Keep the directory name in line with the branch (the agent may have
  # chosen a different short name for git.feature than for prepare). Only
  # worktrees created by prepare are moved; a worktree made by the user or
  # the harness stays where it is.
  local expected="$root" path="$root" moved=""
  if [ -n "$ours" ]; then
    expected=$(compute_worktree_path "$branch") || exit 1
  fi
  if [ "$expected" != "$root" ]; then
    if [ -e "$expected" ]; then
      echo "WARNING: cannot move the worktree to $expected (path exists); keeping $root" >&2
    else
      mkdir -p "$(dirname "$expected")"
      if git -C "$(main_root)" worktree move "$root" "$expected" >&2; then
        path="$expected"
        moved="yes"
        cd "$path"
      else
        echo "WARNING: git worktree move to $expected failed; keeping $root" >&2
      fi
    fi
  fi

  local spec_dir="" fj_file="$path/.specify/feature.json" current="" tmp
  if spec_dir=$(resolve_spec_dir "$path" "$branch"); then
    if [ -f "$fj_file" ]; then
      current=$(jq -r '.feature_directory // empty' "$fj_file" 2>/dev/null || true)
    fi
    if [ "$current" != "$spec_dir" ]; then
      mkdir -p "$path/.specify"
      tmp=$(mktemp)
      if [ -f "$fj_file" ] && jq -e 'type == "object"' "$fj_file" >/dev/null 2>&1; then
        jq --arg d "$spec_dir" '.feature_directory = $d' "$fj_file" > "$tmp"
      else
        jq -n --arg d "$spec_dir" '{feature_directory: $d}' > "$tmp"
      fi
      mv "$tmp" "$fj_file"
    fi
  else
    spec_dir="specs/$branch"
    echo "WARNING: no spec directory found for $branch; feature.json left as is" >&2
  fi

  local state="$path/$STATE_REL"
  if [ -f "$state" ]; then
    tmp=$(mktemp)
    if jq --arg b "$branch" --arg d "$spec_dir" '.feature_branch = $b | .spec_dir = $d' "$state" > "$tmp"; then
      mv "$tmp" "$state"
    else
      rm -f "$tmp"
      echo "WARNING: could not update $STATE_REL" >&2
    fi
  fi

  if [ -n "$ours" ]; then
    local gd
    if gd=$(worktree_git_dir "$path") && [ -f "$gd/$MARKER_PREPARED" ]; then
      mv -f "$gd/$MARKER_PREPARED" "$gd/$MARKER_FINALIZED" || true
    fi
  fi

  echo "WORKTREE_FINALIZED path=$path branch=$branch"
  [ -z "$moved" ] || echo "Worktree moved from $(display_path "$root") to $(display_path "$path") to match the branch."
  echo "Spec directory: $spec_dir"
  echo "cd $path"
}

# Legacy move of a feature branch checked out in the main checkout into a
# new worktree. Commits only the feature's spec directory before switching
# the main checkout back to the default branch.
adopt_impl() {
  local status_word="$1" root branch default path
  root=$(current_root) || die "not inside a git working tree"
  branch=$(current_branch)

  if ! is_feature_branch "$branch"; then
    echo "WORKTREE_SKIPPED reason=not-on-a-feature-branch"
    return 0
  fi
  if in_linked_worktree; then
    echo "WORKTREE_READY path=$root"
    echo "WARNING: already inside a worktree, nesting is not supported; using the current worktree"
    echo "cd $root"
    return 0
  fi

  default=$(resolve_default_branch) || { default_branch_error; exit 1; }
  path=$(compute_worktree_path "$branch") || exit 1
  if [ -e "$path" ]; then
    echo "ERROR: target path already exists: $path" >&2
    echo "Remove it manually or choose a different base_path in $WORKTREE_CONFIG_REL" >&2
    exit 1
  fi

  # Spec directory from feature.json, else specs/<branch>.
  local spec_dir=""
  if [ -f "$root/.specify/feature.json" ]; then
    spec_dir=$(jq -r '.feature_directory // empty' "$root/.specify/feature.json" 2>/dev/null || true)
    spec_dir="${spec_dir%/}"
    spec_dir="${spec_dir#"$root"/}"
  fi
  spec_dir="${spec_dir:-specs/$branch}"

  # Commit only the spec directory. `git commit -- <path>` commits just that
  # path, so changes other sessions staged or left in the tree stay put.
  if [ -d "$root/$spec_dir" ]; then
    (cd "$root" && git add -- "$spec_dir" >/dev/null 2>&1) || true
    if ! (cd "$root" && git diff --cached --quiet -- "$spec_dir"); then
      (cd "$root" && git commit -q -m "feat: Add spec for $branch

Assisted-By: 🤖 Claude Code" -- "$spec_dir") || die "committing $spec_dir to $branch failed"
    fi
  fi

  # Capture the flow state (gitignored) before switching branches.
  local state_content=""
  if [ -f "$root/$STATE_REL" ]; then
    state_content=$(cat "$root/$STATE_REL")
  fi

  # Projects that track .specify/feature.json would otherwise carry this
  # feature's pointer over to the default branch as an uncommitted change.
  # Reset it only when it holds exactly this feature's pointer; the value is
  # written into the worktree below.
  local fj_rel=".specify/feature.json" fj_val=""
  if (cd "$root" && git ls-files --error-unmatch -- "$fj_rel" >/dev/null 2>&1) &&
     ! (cd "$root" && git diff --quiet HEAD -- "$fj_rel"); then
    fj_val=$(jq -r '.feature_directory // empty' "$root/$fj_rel" 2>/dev/null || true)
    fj_val="${fj_val%/}"
    fj_val="${fj_val#"$root"/}"
    if [ "$fj_val" = "$spec_dir" ]; then
      # Reset index and working tree (the pointer may be staged too).
      (cd "$root" && git checkout -q HEAD -- "$fj_rel") || true
    fi
  fi

  if ! git checkout -q "$default" >&2; then
    echo "ERROR: could not switch the main checkout back to $default" >&2
    echo "The repository remains on branch $branch. Resolve the conflict and retry." >&2
    exit 1
  fi

  mkdir -p "$(dirname "$path")"
  if ! git worktree add -q "$path" "$branch" >&2; then
    remove_partial_worktree "$path"
    echo "ERROR: failed to create worktree at $path" >&2
    echo "The repository is on $default. The feature branch $branch still exists." >&2
    exit 1
  fi
  if ! copy_config "$root" "$path"; then
    echo "WARNING: copying configuration into $path failed; run /spex:init there if commands are missing" >&2
  fi

  # The spec directory may be absent from the worktree when specs are
  # gitignored (stealth mode) or could not be committed.
  if [ -d "$root/$spec_dir" ] && [ ! -d "$path/$spec_dir" ]; then
    mkdir -p "$path/$(dirname "$spec_dir")"
    rsync -a "$root/$spec_dir/" "$path/$spec_dir/"
  fi

  mkdir -p "$path/.specify"
  jq -n --arg d "$spec_dir" '{feature_directory: $d}' > "$path/.specify/feature.json"
  if [ -n "$state_content" ]; then
    printf '%s\n' "$state_content" | jq --arg b "$branch" --arg d "$spec_dir" \
      '.feature_branch = $b | .spec_dir = $d' > "$path/$STATE_REL" || true
  fi
  rm -f "$root/$STATE_REL"

  echo "$status_word path=$path branch=$branch"
  [ -z "${ADOPT_NOTE:-}" ] || echo "$ADOPT_NOTE"
  if [ -n "$state_content" ] && printf '%s' "$state_content" | jq -e '.status == "running"' >/dev/null 2>&1; then
    echo "Worktree created at $(display_path "$path") (pipeline mode, continuing)"
  else
    echo "Worktree created at $(display_path "$path"). The main checkout is back on $default."
  fi
  echo "cd $path"
}

cmd_adopt() {
  [ $# -eq 0 ] || { usage; exit 2; }
  adopt_impl "WORKTREE_CREATED"
}

main() {
  local sub="${1:-}"
  case "$sub" in
    prepare|finalize|adopt) ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
  shift
  git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
  case "$sub" in
    prepare) cmd_prepare "$@" ;;
    finalize) cmd_finalize "$@" ;;
    adopt) cmd_adopt "$@" ;;
  esac
}

main "$@"
