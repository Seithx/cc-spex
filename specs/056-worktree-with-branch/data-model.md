# Data Model: Create the Worktree Together with the Feature Branch

No new persistent data. The feature changes where existing files are written and when.

## Main checkout

The repository's primary working directory.

| Attribute | Rule |
|-----------|------|
| Checked-out ref | Unchanged by `prepare` in `early` mode. In `late` mode it is restored to `@{-1}` right away |
| Uncommitted changes | Never staged, committed or stashed by `prepare` or `finalize` |
| `.specify/.spex-state` | Must not hold the new feature's state after `prepare` |
| `.specify/feature.json` | Gitignored. Not written for the new feature |

## Feature worktree

| Attribute | Rule |
|-----------|------|
| Path | `<repo>/<base_path>/<branch>` (default `.claude/worktrees/<branch>`), or `<base>/<repo>@<branch>` for external base paths |
| HEAD lifecycle | `detached@<default-tip>` (after `prepare`, early) → `<branch>` (after `git.feature` runs inside it) |
| Config | Copy of `.specify/`, `.claude/` (without `worktrees/`), plus in-repo symlink targets |
| `.specify/feature.json` | `{"feature_directory": "specs/<NNN-name>"}`, written by core specify and confirmed by `finalize` |
| `.specify/.spex-state` | Moved in by `prepare` when it belongs to the running specify. `feature_branch` and `spec_dir` are set by `finalize` |

### State transitions

```
(none)
  └─ prepare (early) ─────────────► detached worktree, session cd'd in
        └─ git.feature (inside) ───► worktree on <branch>
              └─ specify writes spec, checklist, feature.json
                    └─ finalize ───► name check (+ git worktree move), state fields set
(main on <branch>, no commits)
  └─ prepare (late) ──────────────► main restored to @{-1}; worktree on <branch>
(main on <branch>, prepare skipped by the agent)
  └─ finalize → adopt ────────────► legacy move, spec dir commit only
```

## Flow / ship state (`.specify/.spex-state`)

Existing JSON. No schema change. `prepare` moves it when it belongs to the running specify:

| Mode | Condition for moving |
|------|----------------------|
| `flow` | `running == "specify"` |
| `ship` | `stage == "specify"` |
| `flow` (late mode) | `feature_branch == <late-mode branch>` (the flow-state hook ran without args and wrote plain `create` output) |
| other | never moved |

## Hook registrations (manifests)

| Extension | Event | Command | Priority |
|-----------|-------|---------|----------|
| spex-worktrees | `before_specify` (new) | `speckit.spex-worktrees.manage` (action `prepare`) | 1 |
| spex | `before_specify` | `speckit.spex.flow-state` | 2 (was 1) |
| git (upstream, unchanged) | `before_specify` | `speckit.git.feature` | default 10 |
| spex-worktrees | `after_specify` | `speckit.spex-worktrees.manage` (action `finalize`, was `create`) | 10 |
| spex-worktrees | `before_implement` | `speckit.spex-worktrees.manage` (action `ensure`) | 10 |
