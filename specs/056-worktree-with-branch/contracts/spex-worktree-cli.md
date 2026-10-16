# Contract: `spex-worktree.sh`

Location: `spex/scripts/spex-worktree.sh` (canonical), synced to `spex/extensions/spex-worktrees/scripts/spex-worktree.sh`. Installed at `.specify/extensions/spex-worktrees/scripts/spex-worktree.sh`.

All subcommands run from the session's current directory, which is the main checkout for `prepare` and `adopt` and normally the worktree for `finalize`. Output is line-oriented. The first line is always a machine-readable status line (`KEY key=value ...`). Human-readable lines follow. Errors go to stderr and start with `ERROR:`.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success (including the no-op `READY` and `SKIPPED` results) |
| 1 | Failure. Nothing was changed, or every change was rolled back |
| 2 | Usage error |

## `prepare`

Creates the feature worktree before the spec is written.

```
spex-worktree.sh prepare --short-name <name> [--description <text>] [--branch <exact-name>]
```

- `--branch` (or the `GIT_BRANCH_NAME` environment variable) sets the exact branch name. Otherwise the name comes from `.specify/extensions/git/scripts/bash/create-new-feature.sh --dry-run --json`.
- `--description` is optional (the dry run falls back to the short name). Callers never splice free text into the command line.
- Every worktree `prepare` creates gets a marker file in its own git dir (`spex-prepared`, holding the planned branch name) and a content manifest of the untracked files it copied (`spex-prepared-files`). `finalize` renames the marker to `spex-finalized`. Only marked worktrees are ever moved by `finalize` or removed by the main-checkout repair below.

**Outcomes** (first stdout line):

| Status line | When | Effect |
|-------------|------|--------|
| `WORKTREE_PREPARED path=<abs> branch=<name> base=<default-branch> mode=early` | Run in the main checkout before `git.feature` | Detached worktree at the default branch tip, config copied, matching state moved in. Main checkout untouched |
| `WORKTREE_PREPARED path=<abs> branch=<name> base=<default-branch> mode=late` | Run in the main checkout after `git.feature` already created and checked out `<name>` there | Main checkout restored to its previous ref, the commit-less branch reset to the default branch tip (`git branch -f`), branch attached to the new worktree, config copied, matching state moved in |
| `WORKTREE_READY path=<abs>` | Already inside a linked worktree | Nothing changed. Prints a nesting `WARNING:` unless the worktree was just prepared on purpose: HEAD detached, or a feature-pattern branch with no commits beyond the default branch and no `specs/<branch>/spec.md` yet |
| `WORKTREE_SKIPPED reason=<text>` | `spex-worktrees` disabled in the registry | Nothing changed |

Additional lines:
- `NOTICE: main checkout is on '<ref>', new branch starts from '<default-branch>'` when the main checkout is not on the default branch (FR-017).
- `NOTICE: hook order: git.feature ran before the worktree step; main checkout was restored to '<ref>'` in `late` mode.
- `cd <abs-path>` as the last line: the caller changes into this directory.

**Evaluation order**: the `SKIPPED` check for a disabled extension first (so a disabled extension can never fail, FR-012), then default-branch resolution (inside a worktree, failure here only means the nesting warning plus `READY`), then the `READY` check, then late-mode detection, then the early path (dry run, branch-exists check, worktree creation). Late mode takes the branch name from the main checkout's current branch and never runs the dry run.

**Late-mode detection**: A candidate is the main checkout's current branch when all of these hold: no `specs/<branch>/` directory exists in the main checkout (the spec has not been written yet), it matches the feature pattern (`^[0-9]{3}-` or the timestamp form), it is not the default branch, no other worktree has it checked out, and its reflog says it was created within the last 10 minutes (a branch without a reflog skips this check). A stale branch is not a candidate and is handled by the early path like any other non-default ref: the main checkout stays on it, the new worktree starts from the default branch tip, and the FR-017 `NOTICE` names the branch. For a candidate:
- It must belong to this run: equal to `--branch`/`GIT_BRANCH_NAME` when given, otherwise end with `-<short-name>` (normalized like the git extension does). Otherwise `prepare` fails with `ERROR: the main checkout is on '<branch>', a feature branch created moments ago that does not match this run ...` and changes nothing (it may be another session's run in progress).
- It must have no commits of its own (its tip equals the tip of `@{-1}`). Otherwise `prepare` fails with an `ERROR:` naming the commits and changes nothing. A feature branch with commits is never rewound or deleted.
- Then late mode runs, and the previous ref is `@{-1}`.

**Failure** (exit 1, nothing left behind):
- Default branch cannot be resolved: `ERROR: cannot determine the default branch` plus a `git remote set-head origin --auto` hint.
- Branch already exists (early mode, from `--branch`, `GIT_BRANCH_NAME` or the dry run): `ERROR: branch '<name>' already exists`. No worktree is created.
- Target path exists, `git worktree add` fails, or config copy fails: `ERROR:` with the cause and a remedy. A worktree created by this invocation is removed with `git worktree remove --force`; an existing path is never removed. In `late` mode the main checkout stays on its restored previous ref and the commit-less branch created by `git.feature` is deleted. The feature branch is never checked out in the main checkout again.
- `worktrees.base_path` or the branch name contains characters outside `[A-Za-z0-9._/@+-]`, or a `.claude/worktrees/...` base path contains `.` or `..` components: `ERROR:` naming the setting. External base paths are resolved with `pwd -P` and must not land inside the repository (outside `.claude/worktrees/`).
- Never falls back to working in the main checkout (FR-011).

**Guarantees**: Never stages, commits, stashes or checks out anything in the main checkout in `early` mode (FR-002, FR-004). In `late` mode the main-checkout operations are limited to the restoring `git checkout <previous-ref>` plus ref updates on the commit-less feature branch (`git branch -f` to the default tip, and `git branch -D` on failure). Uncommitted changes are never touched.

## `finalize`

Runs as the `after_specify` worktree hook.

```
spex-worktree.sh finalize
```

| Status line | When | Effect |
|-------------|------|--------|
| `WORKTREE_FINALIZED path=<abs> branch=<name>` | Inside a linked worktree on a feature branch, or on any branch in a worktree `prepare` created | Resolves the spec directory: the existing `.specify/feature.json` value if that directory holds a `spec.md`, else `specs/<branch>`, else the newest `specs/NNN-*` or `specs/YYYYMMDD-HHMMSS-*` directory with a `spec.md`. Writes `feature.json` only if it differs. Sets `feature_branch` and `spec_dir` in `.specify/.spex-state`. If the worktree was created by `prepare` and its directory name differs from the branch, runs `git worktree move` and prints the new path. Idempotent |
| `WORKTREE_ADOPTED path=<abs> branch=<name>` | In the main checkout on a feature branch, when no prepared worktree exists (prepare was skipped), or when one was prepared for exactly this branch (other prepared worktrees are ignored then) and holds only what prepare put there: no tracked changes, no spec content (ignored files included), symlinks identical to the main checkout's, and every other untracked file is the moved state or recorded with the same content in the manifest `prepare` writes next to the marker (`spex-prepared-files`) (git.feature ran in the main checkout after prepare). A flow state in the main checkout counts as this run's only when its `feature_branch` is empty or equals the branch. In the second case the worktree's state is copied back (a flow state for this branch that the hooks wrote in the main checkout is kept as `.spex-state.bak-<branch>`), the unused prepared worktree is removed, and a `NOTICE:` follows the status line | Delegates to `adopt` |
| `WORKTREE_SKIPPED reason=prepared-worktree-exists` | In the main checkout on a feature branch while a prepared, not yet finalized worktree exists that cannot be repaired as above: it was prepared for another branch, it has changes, or both it and the main checkout hold an unrelated state | Nothing changed. `WARNING:` lines explain the case; for another branch they list the worktrees |
| `WORKTREE_SKIPPED reason=<text>` | Not on a feature branch, or extension disabled | Nothing changed |
| Exit 1, `ERROR: this worktree was prepared ... but no feature branch was created` | Inside a worktree `prepare` created that is still detached | Nothing changed |

The last line is `cd <abs-path>` for `FINALIZED` and `ADOPTED`. `SKIPPED` prints no `cd` line.

## `adopt`

Legacy path: moves an already-checked-out feature branch from the main checkout into a new worktree. Used by `finalize` (fallback) and by the `ensure` action.

```
spex-worktree.sh adopt
```

Same as today's `create` action, with one difference: before switching the main checkout back to the default branch it commits only the feature's spec directory (from `.specify/feature.json` or `specs/<branch>`). It never runs `git add -u` and never stages `brainstorm/`.

Status line: `WORKTREE_CREATED path=<abs> branch=<name>` (kept for compatibility with ship and existing docs), then `cd <abs-path>`.

## Configuration copied into the worktree (all subcommands that create one)

- `.specify/` (rsync, excluding `.git` and per-session state files such as `.spex-state` and `.pr-triage-state.json`; only state that belongs to the running specify is moved in separately)
- `.claude/` (rsync, excluding `worktrees/`)
- Tracked files under `.specify/` and `.claude/` are then restored to the worktree's own commit, so uncommitted edits in the main checkout never reach the feature branch
- Directories outside `.claude/` and `.specify/` that symlinks under them point to inside the repo, when the target is missing from the checkout

The base path comes from `worktrees.base_path` in `.specify/extensions/spex-worktrees/worktree-config.yml` (default `.claude/worktrees`). External base paths use the `<repo>@<branch>` directory name as today.
