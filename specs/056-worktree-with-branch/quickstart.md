# Quickstart: Validating Worktree-First Specify

## Automated

```bash
make test-worktree      # tests/test_worktree.sh: prepare/finalize/adopt in throwaway repos
make test-ship-state    # unchanged ship state behavior
make test-statusline    # main-checkout session shows no feature state
make sync-scripts-check # extension copies match spex/scripts/
```

`tests/test_worktree.sh` builds a temporary repository with a `main` branch, a fake `.specify/` (registry with `spex-worktrees` enabled, git extension config but no git extension scripts, since `prepare` never runs them) and a `.claude/` directory. `git.feature` is simulated with `git checkout -b 057-<short-name>` inside the worktree. It covers these cases (among others):

| Case | Expected |
|------|----------|
| `prepare` from clean `main` | `mode=early`, provisional path `.claude/worktrees/.pending-x-<6 hex>`, no `branch=` field. Main HEAD, `git reflog -1 HEAD` and `git status --porcelain` are unchanged. Worktree is detached at `main`'s tip and has `.specify/` and `.claude/` |
| `prepare` with uncommitted changes in main | Same as above. The changes are still uncommitted in main and absent from the worktree |
| `prepare` while main is on `other` | `NOTICE` line. Worktree is based on `main`'s tip, and main stays on `other` |
| `prepare` after a simulated `git.feature` (`git checkout -b 057-x` in main) | `mode=late`. Main is back on `main`, and the worktree is on `057-x` |
| `prepare` inside a worktree on a non-feature branch or a feature branch with commits | `WORKTREE_READY` plus nesting warning, nothing changed |
| `prepare` inside a prepared worktree after `git checkout -b 057-x` ran in it | `WORKTREE_READY`, no warning |
| `prepare` while main is on old-flow `055-foo` (no commits, uncommitted `specs/055-foo/`) | `mode=early` with `NOTICE`, main stays on `055-foo` |
| `prepare` inside a freshly prepared detached worktree | `WORKTREE_READY`, no warning |
| `prepare` while main is detached | `NOTICE`, base is `main`'s tip, main stays detached |
| late mode while main was on `other` | Main back on `other`, branch reset to `main`'s tip, worktree attached |
| late-mode failure (target path present) | Exit 1, main on previous ref, commit-less branch deleted |
| `--branch` naming an existing branch | Exit 1, no worktree |
| external `base_path` | Worktree at `<base>/<repo>@.pending-x-<6 hex>`, renamed to `<base>/<repo>@<branch>` by `finalize` |
| `finalize` after `git.feature` in a provisional worktree | Directory renamed after the branch, new `cd` line; an existing target path is left untouched |
| `finalize` in a prepared worktree that is still detached | `WORKTREE_SKIPPED reason=branch-not-created`, nothing changed |
| late mode with flow `create` state for the branch | State moved into the worktree |
| `prepare --branch 057-x` with target path already present | Exit 1. No worktree and no branch added, main unchanged |
| `prepare` with no resolvable default branch | Exit 1 with the `set-head` hint |
| flow state `running=specify` in main | Moved into the worktree, and main has no `.spex-state` |
| ship state `stage=plan` in main | Not moved |
| `finalize` with an existing valid `feature.json` | Kept unchanged |
| `finalize` with a timestamp-numbered spec directory | Resolved correctly |
| `finalize` in worktree, branch matches directory | `feature.json` and state fields set |
| `finalize` in worktree, branch differs from directory | Worktree moved to `<base>/<branch>`, and the new path is printed |
| `adopt` with uncommitted tracked change in main | Only the spec directory is committed on the feature branch, and the tracked change remains uncommitted on `main` |

## Manual end-to-end (requires an agent session)

1. In a test project with `spex-worktrees` enabled, note `git -C <main> rev-parse --abbrev-ref HEAD` and `git -C <main> reflog -1`.
2. In a second terminal, run a loop that commits to the main checkout every 5 seconds:
   ```bash
   while sleep 5; do date >> notes.txt; git add notes.txt; git commit -qm "concurrent $(date +%s)"; git rev-parse --abbrev-ref HEAD; done
   ```
3. In the agent session run `/speckit-spex-brainstorm` on "add a hello command" and pick "Specify step-by-step" (the brainstorm handoff path).
4. Expected:
   - The loop prints `main` every time (SC-002).
   - After the run, the main checkout's reflog has no entries from the run (SC-001). For a direct `/speckit-specify` whose agent used file order instead of priority, at most one switch and one restore appear, both before the spec is written, together with a `NOTICE` line, and `git status` is unchanged apart from the loop's file (SC-003).
   - The session's working directory is `.claude/worktrees/<NNN-...>`, the spec is there, and the completion message shows `cd <path> && claude` (FR-013).
5. Repeat with `/speckit-spex-ship` on a small brainstorm document and check the same points at the end of stage 0 (User Story 3).
6. Init check: in a scratch project, enable `spex-worktrees`, remove the `git` extension (`specify extension remove git`), and run `/spex:init --refresh`. Expected: a non-zero exit and an `ERROR:` message naming both fixes (User Story 4).
