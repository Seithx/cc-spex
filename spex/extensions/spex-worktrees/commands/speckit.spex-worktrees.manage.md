---
name: speckit.spex-worktrees.worktree
description: Manage git worktrees for isolated feature development - create the worktree with the feature branch, list active worktrees, finish and cleanup
argument-hint: "[list|prepare|finalize|adopt|ensure|finish|cleanup]"
---

# Git Worktree Management for spex

## Overview

This command manages git worktrees to isolate feature development. The worktree is created **before** the feature branch and the spec, so the main checkout never switches branches. Other sessions working in the main checkout keep committing to the default branch.

It supports these actions:

- **prepare**: Called by the `before_specify` hook (priority 1). Creates a worktree at the default branch's tip and moves the session into it. The `git` extension's branch hook then creates the feature branch inside the worktree.
- **finalize**: Called by the `after_specify` hook. Confirms the worktree, branch, `feature.json` and flow state, and keeps the session in the worktree. Falls back to **adopt** when prepare did not run.
- **adopt** (alias: **create**): Legacy path. Moves a feature branch that is checked out in the main checkout into a new worktree.
- **ensure**: Called by the `before_implement` hook. Verifies worktree isolation exists. If already in a worktree, proceeds silently. If not, offers **adopt**.
- **list**: Shows all active feature worktrees with path, branch, and feature name.
- **finish**: Merges the current worktree's branch into the default branch and removes the worktree. Use when implementation is complete.
- **cleanup**: Detects worktrees whose branches are merged and offers removal.

The **prepare**, **finalize** and **adopt** actions delegate to a script. Do not re-implement its steps inline:

```bash
WORKTREE_SCRIPT=".specify/extensions/spex-worktrees/scripts/spex-worktree.sh"
```

The script prints a machine-readable status line first (`WORKTREE_<STATUS> key=value ...`), then human-readable lines (`NOTICE:`, `WARNING:`), and, when the session has to change directory, `cd <abs-path>` as the last line. Errors go to stderr and start with `ERROR:`. Exit code `0` is success (including `READY` and `SKIPPED`), `1` is a failure with nothing left behind, `2` is a usage error.

## Action Routing

Determine the action from the argument, and when there is no argument, from who invoked the command:

- If invoked with argument `prepare`: the action is **prepare**. Execute immediately, no confirmation needed.
- If invoked with argument `finalize`: the action is **finalize**. Execute immediately, no confirmation needed.
- If invoked with argument `adopt` or `create` (`create` is kept as an alias): the action is **adopt**. Execute immediately, no confirmation needed.
- If invoked with argument `ensure`: the action is **ensure**. See Action: Ensure below.
- If invoked with argument `finish`: the action is **finish**.
- If invoked with argument `cleanup`: the action is **cleanup**.
- If invoked with **no argument as the `before_specify` hook** (that is, `speckit-specify` is executing its pre-execution hooks): the action is **prepare**. Execute immediately, no confirmation needed.
- If invoked with **no argument as the `after_specify` hook** (that is, `speckit-specify` just ran and is executing its post-execution hooks): the action is **finalize**. Execute immediately, no confirmation needed.
- If invoked with **no argument as the `before_implement` hook**: the action is **ensure**.
- Otherwise (argument `list`, or invoked directly by the user with no argument): the action is **list**.

> The hook rules matter because the `args` declared in `extension.yml` are dropped when the `specify` CLI generates `.specify/extensions.yml`. A hook therefore reaches this command with no argument at all, and must not silently fall through to **list**. Never infer an action from repository state alone: a bare invocation typed by the user is always **list**.

> **Hook order.** Dispatch the `before_specify` hooks sorted by `priority` (lowest first, missing priority counts as 10). The **prepare** hook (priority 1) must run before the `git` extension's `speckit.git.feature` hook (priority 10), even though the `git` hook comes first in `.specify/extensions.yml`. If the order was wrong anyway, **prepare** repairs it (late mode, see below).

## Prerequisites

The project must be a git repository.

```bash
git rev-parse --git-dir >/dev/null 2>&1 || { echo "ERROR: Not a git repository"; exit 1; }
```

## Action: Prepare

Runs as the `before_specify` hook, before any spec content is written. It is also run directly by `/speckit-spex-ship` (stage 0) and by the brainstorm handoff before they invoke `/speckit-specify`. In those cases the hook finds the session already inside the prepared worktree and returns `WORKTREE_READY`.

### Step 1: Choose the short name once

Generate the feature's short name now, with the same rules the `git` extension's `speckit.git.feature` command uses (2 to 4 words, lowercase, hyphen-separated, action-noun form, for example `user-auth` or `fix-payment-timeout`). Use only lowercase letters, digits and hyphens.

If `/speckit-specify` was invoked by ship or the brainstorm handoff with a short name already chosen, reuse that one. If `speckit.git.feature` already ran in this `/speckit-specify` run (hooks dispatched in file order), reuse the short name you passed to it: `prepare` takes over that branch only when its name ends with the same short name.

### Step 2: Run the script

```bash
"$WORKTREE_SCRIPT" prepare --short-name '<short-name>'
```

Pass the short name in single quotes, and never splice free text (titles, descriptions) into the command: double quotes would let backticks or `$(...)` in that text run as commands. If the user gave an exact branch name (`GIT_BRANCH_NAME`), add `--branch '<name>'`.

The branch name comes from the `git` extension's `create-new-feature.sh --dry-run`, so numbering rules (sequential or timestamp, `GIT_BRANCH_NAME` override) are the same as today. Nothing is created in the main checkout.

### Step 3: Act on the result

- **`WORKTREE_PREPARED ... mode=early`**: run `cd '<path>'` with the path from the last output line. From now on, every remaining hook (`speckit.git.feature`, the spex flow-state hook) and every spec write of this `/speckit-specify` run happens inside the worktree. Run `speckit.git.feature` with `GIT_BRANCH_NAME` set to the `branch=` value of the status line, so the branch matches the worktree directory exactly (this matters most for timestamp numbering). Show any `NOTICE:` line to the user (for example, the main checkout is not on the default branch, and the new branch starts from the default branch anyway).
- **`WORKTREE_PREPARED ... mode=late`**: `speckit.git.feature` already ran in the main checkout (hooks were dispatched in file order). The script restored the main checkout to its previous ref and attached the branch to the new worktree. Run `cd '<path>'`, show the `NOTICE: hook order ...` line, and continue `/speckit-specify` in the worktree. Do not run `speckit.git.feature` again.
- **`WORKTREE_READY`**: the session is already inside a worktree. Run `cd '<path>'` (usually a no-op) and continue. Show a `WARNING:` line if one was printed (nesting is not supported, the spec is written in the current worktree).
- **`WORKTREE_SKIPPED`**: the extension is disabled. Continue without a worktree.
- **Exit code 1 or 2**: **STOP `/speckit-specify`.** Show the `ERROR:` lines and the remedy. Do not fall back to creating the branch or writing the spec in the main checkout. Do not run `speckit.git.feature`. Inside a ship pipeline this is a blocker at every oversight level. Late mode is taken only for a feature branch that was created moments ago and matches this run's short name (or `--branch`). If the main checkout sits on a fresh feature branch of another run, or on one that already has commits, `prepare` stops with an `ERROR:` and changes nothing.

### Step 4: If `speckit.git.feature` fails inside the prepared worktree

If the branch hook fails after an early-mode prepare (for example, the branch name is taken), remove the worktree, and the branch too if the hook created it before failing and it has no commits of its own. The same applies when ship or the brainstorm handoff prepared the worktree and `/speckit-specify` then fails before the branch exists. First hand the flow or ship state back to the main checkout, because `prepare` moved it into the worktree and removing the worktree would delete the only copy. Then stop:

```bash
MAIN_WORKTREE=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')
if [ -f '<path>/.specify/.spex-state' ] && [ ! -f "$MAIN_WORKTREE/.specify/.spex-state" ]; then
  cp -p '<path>/.specify/.spex-state' "$MAIN_WORKTREE/.specify/.spex-state"
fi
cd "$MAIN_WORKTREE"
# In a ship pipeline, point the state file back at the main checkout before pausing.
[ -n "${SHIP_STATE_FILE:-}" ] && export SHIP_STATE_FILE="$MAIN_WORKTREE/.specify/.spex-state"
git worktree remove --force '<path>'
# Only a branch this run created: it exists, and has no commits beyond <base>
# (the base= value from the WORKTREE_PREPARED line).
if git show-ref --verify --quiet "refs/heads/<branch>" &&
   [ "$(git rev-list --count "<base>..<branch>")" = "0" ]; then
  git branch -D "<branch>"
fi
```

Skip the branch deletion when the hook failed because `<branch>` already existed before this run (the "already exists" error): that branch belongs to someone else. Then report the error and stop `/speckit-specify`. Never retry `speckit.git.feature` in the main checkout.

## Action: Finalize

Runs as the `after_specify` hook, inside the worktree prepared above.

### Step 1: Run the script

```bash
"$WORKTREE_SCRIPT" finalize
```

It confirms the branch, moves the worktree directory if the branch name differs from it (the agent chose a different short name for `speckit.git.feature`), writes `.specify/feature.json` only if it points elsewhere, and sets `feature_branch` and `spec_dir` in `.specify/.spex-state`. It never creates, switches or commits anything when the worktree already exists.

### Step 2: Act on the result

- **`WORKTREE_FINALIZED`**: run `cd '<path>'` with the path from the last output line (the path changes when the directory was moved; only worktrees that `prepare` created are ever moved). The session stays in the worktree.
- **`WORKTREE_ADOPTED`**: the feature branch was checked out in the main checkout, either because prepare did not run, or because `speckit.git.feature` ran in the main checkout after prepare (a `NOTICE:` line says so; the unused prepared worktree was removed). The script ran the legacy **adopt** path. Run `cd '<path>'`.
- **`WORKTREE_SKIPPED reason=prepared-worktree-exists`**: finalize ran in the main checkout (for example after a working-directory reset) while a prepared, not yet finalized worktree exists. The main checkout was left alone. Follow the `WARNING:` lines: usually `cd` into this feature's worktree (listed in the output) and run finalize again there.
- **`WORKTREE_SKIPPED`** (any other reason): nothing to do. There is no `cd` line.
- **Exit code 1**: show the `ERROR:` lines and stop. In particular, finalize fails inside a prepared worktree that has no branch (`speckit.git.feature` did not run there or failed); do not continue writing the spec there.

### Step 3: Completion message

If `.specify/.spex-state` in the worktree has `status == "running"` (ship pipeline), print one line (`Worktree ready at <path> (pipeline mode, continuing)`) and return. Do not show a box and do not stop the pipeline.

Otherwise (interactive), the session stays in the worktree, so `/speckit-clarify` or `/speckit-plan` can run next in the same session. Show:

```
┌─────────────────────────────────────────────────────────────┐
│ Spec written in worktree <display-path>                     │
│                                                             │
│ This session now works in the worktree. Continue here with  │
│ /speckit-clarify or /speckit-plan.                          │
│                                                             │
│ To open a new session in the worktree instead:              │
│   cd <worktree-path> && claude                              │
│                                                             │
│ The main checkout was not switched. Config (.claude/ and    │
│ .specify/) has been copied into the worktree.               │
└─────────────────────────────────────────────────────────────┘
```

Where `<display-path>` is `.claude/worktrees/<branch>` for inside-project worktrees, or the full absolute path for external worktrees, and `<worktree-path>` is the absolute path from the `cd` line.

## Action: Adopt

Legacy path for a feature branch that is checked out in the main checkout (a feature specified before worktree-first specify existed, or `spex-worktrees` enabled afterwards). Used by **finalize** as a fallback and by **ensure**. The argument `create` is an alias.

```bash
"$WORKTREE_SCRIPT" adopt
```

The script commits only the feature's spec directory to the feature branch (never `git add -u`, never `brainstorm/`), switches the main checkout back to the default branch, creates the worktree, copies `.specify/` and `.claude/` (plus in-repo symlink targets), and moves the flow state into the worktree.

- **`WORKTREE_CREATED path=<abs> branch=<name>`**: run `cd <path>` with the path from the last line. Show the completion box from Action: Finalize Step 3 (or the one-line pipeline message when `status == "running"`).
- **`WORKTREE_READY`** or **`WORKTREE_SKIPPED`**: nothing to do. Show any `WARNING:` line.
- **Exit code 1**: show the `ERROR:` lines and stop. Do not switch branches by hand.

Do NOT write spex-detach exclude entries for the new worktree. Git's `.git/info/exclude` is shared across all worktrees via `git-common-dir`, so the worktree already sees exactly the stealth mode state of the main checkout. Stealth mode is toggled only through `/speckit-spex-detach-detach`.

## Action: Ensure

Called by the `before_implement` hook to verify worktree isolation before implementation starts. This closes the gap in multi-session workflows where `specify` and `implement` run in different conversations.

### Step 1: Check if Already in a Worktree

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
GIT_DIR=$(git rev-parse --git-dir)

if [ "$GIT_DIR" != "$REPO_ROOT/.git" ] && [ "$GIT_DIR" != ".git" ]; then
  # Already in a worktree: isolation exists, nothing to do
  exit 0
fi
```

If already in a worktree, stop here (success). Implementation can proceed.

### Step 2: Check if on a Feature Branch

```bash
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
```

If the branch does NOT match the `NNN-feature-name` pattern, skip silently. This is not a feature branch, so worktree isolation does not apply.

### Step 3: Check if a Worktree Already Exists for This Branch

```bash
WORKTREE_CONFIG=".specify/extensions/spex-worktrees/worktree-config.yml"
BASE_PATH=$(yq -r '.worktrees.base_path // ".claude/worktrees"' "$WORKTREE_CONFIG" 2>/dev/null || echo ".claude/worktrees")
WORKTREE_PATH="$REPO_ROOT/$BASE_PATH/$BRANCH_NAME"

if git worktree list --porcelain | grep -q "worktree.*$BRANCH_NAME"; then
  echo "WARNING: A worktree for branch $BRANCH_NAME already exists but you are not in it."
  echo "Switch to the worktree before implementing:"
  echo "  cd $WORKTREE_PATH && claude"
  # Stop here. Do not create a duplicate worktree.
fi
```

### Step 4: Offer to Create a Worktree

Present a single-select question to the user:
- header: "Worktree"
- question: "Implementation is about to start without worktree isolation. Create a worktree now?"
- options:
  - "Create worktree (Recommended)": "Isolate implementation in a git worktree"
  - "Continue without worktree": "Implement directly on the current branch (no isolation)"

If the user selects "Create worktree", execute **Action: Adopt** above (`"$WORKTREE_SCRIPT" adopt`), then `cd` into the printed path. The adopt commit holds only the feature's spec directory; other uncommitted changes stay in the main checkout.

If the user selects "Continue without worktree", proceed without isolation.

## Action: List

Show all active feature worktrees for the project.

### Step 1: Get Worktree List

```bash
git worktree list --porcelain
```

Parse the output. Each worktree entry has:
- `worktree <path>`
- `HEAD <commit>`
- `branch refs/heads/<branch-name>`

### Step 2: Filter Feature Branches

Only show worktrees whose branch matches the `NNN-*` feature branch pattern (three-digit prefix followed by a hyphen).

Skip the main worktree (the original repo).

### Step 3: Format Output

Display a table with worktree directory names (`@` separator):

```
Active Feature Worktrees:

  Path                              Branch              Feature
  ─────────────────────────────────────────────────────────────
  .claude/worktrees/004-user-auth   004-user-auth       user-auth
  .claude/worktrees/007-worktrees   007-worktrees-trait  worktrees-trait
```

For inside-project worktrees, show the relative path (`.claude/worktrees/<branch>`). For external worktrees, show the last path component (`repo@branch`).

If no feature worktrees exist:

```
No active feature worktrees found.

Create one by running /speckit-specify with the worktrees extension enabled.
```

## Action: Finish

Merges the current worktree's feature branch into the default branch and removes the worktree. This is the recommended way to complete work in a spex worktree.

{harness:worktree-isolation}
Spex worktrees are managed via `git worktree add` and `git worktree remove` commands directly.
Do NOT use harness-specific worktree tools, as spex worktrees are created independently.
Always use git commands for worktree operations.
{/harness:worktree-isolation}

### Step 1: Verify We're in a Worktree

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
GIT_DIR=$(git rev-parse --git-dir)

# A worktree has a .git file (not directory) pointing to the main repo
if [ "$GIT_DIR" = "$REPO_ROOT/.git" ] || [ "$GIT_DIR" = ".git" ]; then
  echo "ERROR: Not inside a git worktree. Use 'finish' from within a spex worktree."
  # Stop here.
fi
```

### Step 2: Get Branch and Main Worktree Info

```bash
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
WORKTREE_PATH=$(git rev-parse --show-toplevel)

# Find the main worktree (first entry in worktree list)
MAIN_WORKTREE=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')

# Detect default branch
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [ -z "$DEFAULT_BRANCH" ]; then
  for candidate in main master; do
    if git rev-parse --verify "$candidate" >/dev/null 2>&1; then
      DEFAULT_BRANCH="$candidate"
      break
    fi
  done
fi
DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}
```

### Step 3: Ensure All Changes Are Committed

```bash
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: Uncommitted changes in worktree. Commit or stash before finishing."
  # Stop here.
fi
```

### Step 4: Ask User How to Proceed

{harness:interactive-choice} (single-select, header: "Finish"):
- "Merge and remove (Recommended)": "Fast-forward merge branch into default, remove worktree and branch"
- "Remove only": "Remove worktree and branch without merging (changes stay in git reflog)"
- "Cancel": "Keep worktree as-is"

If "Cancel": stop.

### Step 5: Switch CWD to Main Worktree

**CRITICAL:** Switch the working directory to the main worktree BEFORE doing anything destructive. If cwd is inside the worktree being removed, all subsequent Bash commands will fail with "path does not exist".

```bash
cd "$MAIN_WORKTREE"
```

### Step 6: Merge (if selected)

If the user chose "Merge and remove":

```bash
cd "$MAIN_WORKTREE"
git checkout "$DEFAULT_BRANCH"
git merge --ff-only "$BRANCH_NAME" 2>&1
```

If fast-forward merge fails (branches diverged), ask the user:

{harness:interactive-choice} (single-select, header: "Merge"):
- "Create merge commit": "Merge with a merge commit (branches have diverged)"
- "Abort": "Keep worktree, resolve manually"

If "Create merge commit":
```bash
git merge "$BRANCH_NAME" -m "Merge branch '$BRANCH_NAME'

Assisted-By: 🤖 Claude Code" 2>&1
```

If "Abort": stop. The cwd is already at the main worktree, so the user can navigate back.

### Step 7: Remove Worktree and Branch

```bash
# Remove worktree (cwd is already at main worktree from Step 5)
git worktree remove "$WORKTREE_PATH" 2>&1

# Delete the feature branch (it's merged or user chose remove-only)
git branch -d "$BRANCH_NAME" 2>&1 || git branch -D "$BRANCH_NAME" 2>&1
```

### Step 8: Clear Flow State

```bash
STATE_FILE=".specify/.spex-state"
if [ -f "$STATE_FILE" ]; then
  rm -f "$STATE_FILE"
fi
```

### Step 9: Report

```
┌─────────────────────────────────────────────────────────┐
│ Feature branch <branch> finished.                       │
│                                                         │
│ - Merged to <default-branch> (if selected)              │
│ - Worktree removed: <worktree-path>                     │
│ - Branch deleted: <branch>                              │
│ - Flow state cleared                                    │
│                                                         │
│ You are now in the main repo on <default-branch>.       │
└─────────────────────────────────────────────────────────┘
```

If the user wants to push: `git push origin $DEFAULT_BRANCH`

## Action: Cleanup

Detect worktrees whose branches are merged and offer removal.

### Step 1: Get Merged Branches

```bash
# Detect default branch with fallback chain
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [ -z "$DEFAULT_BRANCH" ]; then
  for candidate in main master; do
    if git rev-parse --verify "$candidate" >/dev/null 2>&1; then
      DEFAULT_BRANCH="$candidate"
      break
    fi
  done
fi
DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}

# Get all feature branches merged into the default branch
MERGED_BRANCHES=$(git branch --merged "$DEFAULT_BRANCH" | sed 's/^[+* ]*//' | grep -E '^[0-9]{3}-')
```

### Step 2: Cross-Reference with Worktrees

For each worktree with a feature branch, check if its branch appears in the merged list.

### Step 3: Handle Merged Worktrees

For each merged worktree, present it to the user and ask for confirmation:

```
Worktree cc-spex@004-user-auth (branch 004-user-auth) is merged into main.
Remove this worktree? (yes/no)
```

If the user confirms, first switch to the main repo root (to avoid cwd pointing at the deleted directory), then remove the worktree:

```bash
# Switch cwd to the main worktree BEFORE removing the feature worktree.
# If cwd is inside the worktree being removed, all subsequent commands will
# fail with "Path does not exist" because the Bash tool persists cwd.
MAIN_WORKTREE=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')
cd "$MAIN_WORKTREE"
git worktree remove <path>
git branch -d <branch-name>
```

### Step 4: Handle Unmerged Worktrees

For worktrees with unmerged branches, warn the user:

```
Worktree cc-spex@007-worktrees-trait (branch 007-worktrees-trait) has NOT been merged.
Skipping. Use --force to remove unmerged worktrees (data may be lost).
```

Only remove unmerged worktrees if the user explicitly confirms after seeing the warning.

---

## Worktree Context for Downstream Commands

When running in a worktree created by this extension, downstream spec-kit commands should be aware of the worktree context:

### Planning Context

You are likely running in a worktree created by the `worktrees` extension. The spec file in this worktree contains all decisions from the brainstorm/specify session. No separate handoff file is needed.

### Implementation Context

You are likely running in a worktree created by the `worktrees` extension. The spec and plan files in this worktree contain all context needed for implementation. No separate handoff file is needed.
