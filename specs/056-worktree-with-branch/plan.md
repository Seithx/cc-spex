# Implementation Plan: Create the Worktree Together with the Feature Branch

**Branch**: `056-worktree-with-branch` | **Date**: 2026-10-16 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/056-worktree-with-branch/spec.md`

## Summary

Move worktree creation in front of branch creation. A new `before_specify` hook in `spex-worktrees` (priority 1) runs `spex-worktree.sh prepare`. That command computes the branch name with the `git` extension's dry run, creates a detached worktree at the default branch's tip, copies the config into it, moves the running flow or ship state into it, and moves the session into it. The unchanged upstream `git.feature` hook then creates the branch inside the worktree, so the main checkout never moves.

Agents may run hooks in file order instead of priority order, so `prepare` also has a `late` mode. If `git.feature` already switched the main checkout, it restores the main checkout at once and attaches the branch to the new worktree. The `after_specify` hook switches from `create` to `finalize`, which only confirms the name, `feature.json` and state. Ship and the brainstorm handoff run `prepare` themselves before `/speckit-specify`, so they do not depend on hook order. The spex methodology skill tells agents to dispatch hooks by priority. Init fails when `spex-worktrees` is enabled without the `git` extension. The legacy `adopt` path stops sweeping `git add -u` and `brainstorm/`.

## Technical Context

**Language/Version**: Bash (POSIX-leaning, `#!/usr/bin/env bash`), Markdown command files, YAML manifests

**Primary Dependencies**: `git` (worktree, `rev-parse`, `checkout`), `jq`, `yq`, `rsync`, `python3` (`realpath` for symlink targets, as today), the spec-kit `git` extension's `create-new-feature.sh --dry-run --json`

**Storage**: Files only (`.specify/.spex-state`, `.specify/feature.json`, the git worktree metadata)

**Testing**: Bash test scripts under `tests/` using throwaway git repositories (pattern of `tests/test_ship_state.sh`), plus Makefile targets

**Target Platform**: macOS and Linux developer machines running Claude Code (other harnesses through existing adapters)

**Project Type**: Claude Code plugin / spec-kit extension bundle (CLI-style scripts plus agent command markdown)

**Performance Goals**: `prepare` finishes in under 5 seconds on a typical repository (dominated by `rsync` of `.claude/` and `.specify/`)

**Constraints**: No changes to upstream spec-kit files (FR-015). No changes to other extensions' hooks (Constitution III). Main checkout untouched in `early` mode (FR-002, FR-004)

**Scale/Scope**: 1 new script (~300 lines), 1 new test script plus one case in `tests/test_ship_statusline.sh`, 2 manifests, 5 command markdown files (worktrees manage, ship, brainstorm, using-superpowers, init skill), `spex-init.sh`, Makefile, README, help.md, CHANGELOG, and an upstream proposal draft

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | Pass | Tracked feature with spec, plan and tasks |
| II. Extension Architecture | Pass | New behavior is a hook in the `spex-worktrees` manifest plus a script shipped inside that extension |
| III. Extension Composability | Pass | The `git` extension's hooks and files are untouched. Ordering relies only on spex's own `priority` values, and `late` mode handles agents that ignore priority. `spex-worktrees` still declares `git` as required |
| IV. Quality Gates | Pass | No gate changes |
| V. Naming Discipline | Pass | Branch naming delegated to the `git` extension's script. Script name `spex-worktree.sh` follows `spex-*` |
| VI. Skill Autonomy | Pass | `manage` keeps a single purpose (worktree lifecycle), with a new `prepare`/`finalize` action routing |
| VII. State as Scripts | Pass (improves) | The inline `create` bash, including the state and `feature.json` writes, moves into `spex-worktree.sh` |

**Post-design re-check**: Pass. The design adds no cross-extension writes. `.specify/extensions.yml` is only changed through spex's own manifests on reinstall.

## Project Structure

### Documentation (this feature)

```text
specs/056-worktree-with-branch/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── spex-worktree-cli.md
├── checklists/
│   └── requirements.md
├── upstream-proposal.md  # T026 draft (not filed)
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
spex/
├── scripts/
│   ├── spex-worktree.sh                 # NEW: prepare | finalize | adopt
│   └── spex-init.sh                     # init fails when worktrees lacks git
├── extensions/
│   ├── spex/
│   │   ├── extension.yml                # flow-state before_specify priority 1 → 2
│   │   └── commands/
│   │       ├── speckit.spex.ship.md             # stage 0 runs prepare first; git prerequisite
│   │       ├── speckit.spex.brainstorm.md       # handoff runs prepare before specify
│   │       └── speckit.spex.using-superpowers.md # dispatch hooks by priority
│   └── spex-worktrees/
│       ├── extension.yml                # + before_specify hook (prepare); after_specify → finalize
│       ├── scripts/spex-worktree.sh     # synced copy (make sync-scripts)
│       └── commands/speckit.spex-worktrees.manage.md  # actions delegate to the script
├── skills/init/SKILL.md                 # describe the new init failure
└── docs/help.md

tests/
├── test_worktree.sh                     # NEW
└── test_ship_statusline.sh              # + main-checkout case

Makefile                                 # SCRIPTS_spex_worktrees, EXTENSIONS, test-worktree
README.md                                # spex-worktrees description, ship worktree section
CHANGELOG.md
```

**Structure Decision**: Follow the existing split. The canonical script lives in `spex/scripts/` and is copied into the extension by `make sync-scripts`. The command markdown delegates to the script, and tests live in `tests/`.

## Design

### `before_specify` (direct `/speckit-specify`)

1. The agent generates the feature's short name once and calls `/speckit-spex-worktrees-manage` as a `before_specify` hook. The action routes to **prepare** (a new routing rule, since hook args are dropped).
2. `manage` runs `spex-worktree.sh prepare --short-name <name> --description "<desc>"` and acts on the status line:
   - `PREPARED`: `cd` into the printed path. All later hooks and spec writes happen there. The agent reuses the same short name for `git.feature`.
   - `READY` or `SKIPPED`: continue.
   - Exit 1: stop `/speckit-specify` and show the error (FR-011). No fallback.
3. `git.feature` (priority 10) runs `create-new-feature.sh` inside the worktree. `git checkout -b` affects only the worktree.
4. Flow-state `before_specify` (priority 2) writes `.spex-state` in the worktree. In file order it may run earlier, in which case `prepare` has already moved its state.

### Brainstorm handoff

When the user picks "Specify step-by-step" after a brainstorm and `spex-worktrees` is enabled, the brainstorm command runs `prepare` itself, changes into the worktree and only then invokes `/speckit-specify`. The `before_specify` worktree hook then returns `READY` without a warning (the worktree is still detached, or, under file-order dispatch, already on its fresh commit-less branch), so this path does not depend on hook order.

### `after_specify`

`manage` routes to **finalize**. Inside the worktree it confirms the branch, renames the directory if the agent picked a different short name, and sets `feature.json` and the state fields. Outside a worktree (prepare skipped), it falls back to **adopt**. The interactive completion box keeps the session in the worktree and shows the `cd <path> && claude` hint (FR-013).

### Ship

- Prerequisites: if `spex-worktrees` is enabled and the `git` extension is not, stop with the same message as init.
- Stage 0, before invoking `/speckit-specify`: run `prepare` with a short name derived from the brainstorm file name, `cd` into the worktree, and `export SHIP_STATE_FILE=<worktree>/.specify/.spex-state` (prepare moved it, since `stage == specify`).
- After specify: `FEATURE_BRANCH=$(git branch --show-current)` now reads the worktree's branch (FR-010). Remove the "invoke manage create if no worktree" fallback and run `finalize` instead.
- A prepare failure pauses the pipeline as a blocker at every oversight level.

### Init

In `install_extensions()`, after the existing `specify extension enable git` attempt, check that `spex-worktrees` is enabled in `.specify/extensions/.registry`. If it is and `git` is still not enabled, print `ERROR: spex-worktrees requires the git extension` with both fixes and `exit 1`.

### Risks

| Risk | Mitigation |
|------|------------|
| Agent ignores priority, so `git.feature` switches main first | Brainstorm handoff and ship run `prepare` before specify. The methodology skill states priority dispatch. `late` mode restores main before any spec content is written and prints a `NOTICE` (FR-002 names this window). Upstream proposal drafted (T026) |
| Agent picks different short names for prepare and `git.feature` | `finalize` moves the worktree to match the branch |
| Session working directory drifts back to main | Existing `spex-worktree-cwd.sh` recovery (ship). In flow mode the worktree is inside the project, so the CWD persists |
| Moving another session's state | `prepare` moves state only when it belongs to a running specify (`running == specify` or `stage == specify`) |

## Complexity Tracking

No constitution violations.
